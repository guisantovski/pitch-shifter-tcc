import sounddevice as sd
import numpy as np

SAMPLE_RATE   = 48000
BUFFER_SIZE   = 256  # reduzido do 1024 original
INPUT_DEVICE  = 20
OUTPUT_DEVICE = 21

def callback(indata, outdata, frames, time, status):
    if status:
        print(status)
    outdata[:] = indata

print("Iniciando passthrough — Ctrl+C para parar")
with sd.Stream(samplerate=SAMPLE_RATE,
               blocksize=BUFFER_SIZE,
               dtype='int16',
               channels=1,
               device=(INPUT_DEVICE, OUTPUT_DEVICE),
               callback=callback):
    sd.sleep(10_000)