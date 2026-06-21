import sounddevice as sd
import numpy as np

SAMPLE_RATE   = 48000
BUFFER_SIZE   = 128  # ~2.7ms — limite configurado no Focusrite Control
ASIO_DEVICE   = 13   # Focusrite USB ASIO

def callback(indata, outdata, frames, time, status):
    if status:
        print(status)
    outdata[:] = indata

print("Iniciando passthrough ASIO — Ctrl+C para parar")
with sd.Stream(samplerate=SAMPLE_RATE,
               blocksize=BUFFER_SIZE,
               dtype='float32',       # ASIO suporta float32
               channels=1,
               device=(ASIO_DEVICE, ASIO_DEVICE),
               callback=callback):
    sd.sleep(10_000)