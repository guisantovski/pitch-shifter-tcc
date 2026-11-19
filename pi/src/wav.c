#include "wav.h"

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static uint32_t u32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }
static uint16_t u16(const uint8_t *p) { return p[0] | p[1] << 8; }

float *wav_le(const char *arq, int *n, int *fs)
{
    FILE *f = fopen(arq, "rb");
    if (!f) return NULL;
    uint8_t h[12], ck[8];
    int fmt = 0, canais = 0, bits = 0;
    float *x = NULL;

    if (fread(h, 1, 12, f) != 12 || memcmp(h, "RIFF", 4) || memcmp(h + 8, "WAVE", 4))
        goto fim;
    while (fread(ck, 1, 8, f) == 8) {
        uint32_t tam = u32(ck + 4);
        if (!memcmp(ck, "fmt ", 4)) {
            uint8_t b[40] = {0};
            if (tam > sizeof b || fread(b, 1, tam, f) != tam) goto fim;
            fmt = u16(b); canais = u16(b + 2); *fs = (int)u32(b + 4); bits = u16(b + 14);
            if (fmt == 0xFFFE) fmt = u16(b + 24);       /* WAVE_FORMAT_EXTENSIBLE */
        } else if (!memcmp(ck, "data", 4)) {
            int bps = bits / 8;
            if (!canais || !bps || (fmt != 1 && fmt != 3)) goto fim;
            uint8_t *d = malloc(tam);
            if (!d) goto fim;
            tam = (uint32_t)fread(d, 1, tam, f);
            *n = (int)(tam / (bps * canais));
            x = calloc(*n ? *n : 1, sizeof(float));
            for (int i = 0; x && i < *n; i++) {
                double s = 0;
                for (int c = 0; c < canais; c++) {
                    const uint8_t *p = d + (size_t)(i * canais + c) * bps;
                    if (fmt == 3 && bits == 32) { float v; memcpy(&v, p, 4); s += v; }
                    else if (bits == 16) s += (int16_t)u16(p) / 32768.0;
                    else if (bits == 24) {
                        int32_t v = (int32_t)((uint32_t)p[0] << 8 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 24);
                        s += (v >> 8) / 8388608.0;
                    }
                    else if (bits == 32) s += (int32_t)u32(p) / 2147483648.0;
                }
                x[i] = (float)(s / canais);
            }
            free(d);
            goto fim;
        } else {
            fseek(f, tam + (tam & 1), SEEK_CUR);
        }
    }
fim:
    fclose(f);
    return x;
}

static void p32(FILE *f, uint32_t v) { uint8_t b[4] = {v, v >> 8, v >> 16, v >> 24}; fwrite(b, 1, 4, f); }
static void p16(FILE *f, uint16_t v) { uint8_t b[2] = {v, v >> 8}; fwrite(b, 1, 2, f); }

int wav_grava(const char *arq, const float *x, int n, int fs)
{
    FILE *f = fopen(arq, "wb");
    if (!f) return -1;
    uint32_t dados = (uint32_t)n * 4;
    fwrite("RIFF", 1, 4, f); p32(f, 36 + dados); fwrite("WAVE", 1, 4, f);
    fwrite("fmt ", 1, 4, f); p32(f, 16); p16(f, 3); p16(f, 1);
    p32(f, fs); p32(f, fs * 4); p16(f, 4); p16(f, 32);
    fwrite("data", 1, 4, f); p32(f, dados);
    fwrite(x, sizeof(float), n, f);          /* little-endian (x86 e ARM) */
    return fclose(f) ? -1 : 0;
}
