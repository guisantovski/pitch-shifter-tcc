"""Referência em numpy, linha a linha igual a matlab/pvProcessBlock.m
(double, FFT complexa completa), para conferir o port em C.

    python3 tools/referencia.py entrada.wav semitons saida_do_C.wav [N Ha B]

Processa a entrada com a referência e compara com a saída do pv_offline.
"""
import struct
import sys

import numpy as np


def le_wav(arq):
    with open(arq, "rb") as f:
        d = f.read()
    assert d[:4] == b"RIFF" and d[8:12] == b"WAVE"
    p, fmt = 12, None
    while p + 8 <= len(d):
        ck, tam = d[p:p + 4], struct.unpack("<I", d[p + 4:p + 8])[0]
        corpo = d[p + 8:p + 8 + tam]
        if ck == b"fmt ":
            fmt, canais, fs, _, _, bits = struct.unpack("<HHIIHH", corpo[:16])
            if fmt == 0xFFFE:
                fmt = struct.unpack("<H", corpo[24:26])[0]
        elif ck == b"data":
            if fmt == 3:
                x = np.frombuffer(corpo, "<f4").astype(float)
            elif bits == 16:
                x = np.frombuffer(corpo, "<i2") / 32768.0
            elif bits == 24:
                b = np.frombuffer(corpo[: len(corpo) // 3 * 3], np.uint8).reshape(-1, 3).astype(np.int32)
                x = ((b[:, 0] << 8 | b[:, 1] << 16 | b[:, 2] << 24) >> 8) / 8388608.0
            else:
                x = np.frombuffer(corpo, "<i4") / 2147483648.0
            return x.reshape(-1, canais).mean(axis=1), fs
        p += 8 + tam + (tam & 1)
    raise ValueError("WAV sem dados")


class PV:
    def __init__(self, N, Ha, B, semitons):
        self.N, self.Ha, self.B, self.R = N, Ha, B, Ha // B
        n = np.arange(N)
        self.win = 0.5 - 0.5 * np.cos(2 * np.pi * n / N)
        self.omega = 2 * np.pi * n / N
        self.inBuf = np.zeros(N)
        self.ola = np.zeros(2 * N + Ha)
        self.outBlk = np.zeros(Ha)
        self.blk, self.cont = 0, 0
        self.fasePrev = np.zeros(N)
        self.faseSint = np.zeros(N)
        self.set_semitons(semitons)

    def set_semitons(self, s):
        self.Hs = int(np.floor(2 ** (s / 12) * self.Ha + 0.5))   # round() do MATLAB
        self.alfa = self.Hs / self.Ha
        self.L = int(np.floor((self.N - 1) / self.alfa)) + 1
        self.tGrao = np.arange(self.L) * self.alfa
        self.ganhoOla = 8 * self.Hs / (3 * self.N)

    def bloco(self, x):
        N, Ha, B = self.N, self.Ha, self.B
        self.inBuf[: N - B] = self.inBuf[B:]
        self.inBuf[N - B:] = x
        self.cont += 1
        if self.cont == self.R:
            self.cont = 0
            X = np.fft.fft(self.win * self.inBuf)
            mag, fase = np.abs(X), np.angle(X)
            dfase = fase - self.fasePrev - Ha * self.omega
            dfase -= 2 * np.pi * np.round(dfase / (2 * np.pi))
            freqV = self.omega + dfase / Ha
            self.fasePrev = fase
            self.faseSint = self.faseSint + self.Hs * freqV
            self.faseSint -= 2 * np.pi * np.round(self.faseSint / (2 * np.pi))
            grao = np.real(np.fft.ifft(mag * np.exp(1j * self.faseSint))) * self.win
            i0 = np.floor(self.tGrao).astype(int)
            frac = self.tGrao - i0
            i1 = np.minimum(i0 + 1, N - 1)
            grao = (1 - frac) * grao[i0] + frac * grao[i1]
            L = self.L
            self.ola[:L] += self.ganhoOla * grao
            self.outBlk = self.ola[:Ha].copy()
            self.ola[:-Ha] = self.ola[Ha:].copy()
            self.ola[-Ha:] = 0
            self.blk = 0
        y = self.outBlk[self.blk * B:(self.blk + 1) * B]
        self.blk += 1
        return y


def main():
    entrada, st, saidaC = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    N, Ha, B = (int(v) for v in (sys.argv[4:7] + ["1024", "256", "64"][len(sys.argv[4:7]):]))
    x, fs = le_wav(entrada)
    pv = PV(N, Ha, B, st)
    nb = len(x) // B
    yr = np.concatenate([pv.bloco(x[b * B:(b + 1) * B]) for b in range(nb)])
    yc, _ = le_wav(saidaC)
    n = min(len(yr), len(yc))
    err = yc[:n] - yr[:n]
    snr = 10 * np.log10(np.sum(yr[:n] ** 2) / max(np.sum(err ** 2), 1e-30))
    print(f"{entrada} {st:+d} st: erro máx {np.max(np.abs(err)):.2e}, "
          f"SNR C vs referência {snr:.1f} dB, RMS saída/entrada {np.sqrt(np.mean(yr**2)/np.mean(x**2)):.2f}")


if __name__ == "__main__":
    main()
