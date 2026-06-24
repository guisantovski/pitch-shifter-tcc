import numpy as np
import sounddevice as sd

# --- Configurações ---
SAMPLE_RATE   = 96000
BUFFER_SIZE   = 256
ASIO_DEVICE   = 17
SEMITONES     = -5       # negativo = transpor para baixo

# --- Parâmetros do Phase Vocoder ---
FFT_SIZE      = 4096     # tamanho da janela de análise
HOP_SIZE      = FFT_SIZE // 4  # 75% de overlap

# Razão de transposição
pitch_ratio   = 2 ** (SEMITONES / 12)

# --- Estado persistente entre callbacks ---
# Buffers de entrada e saída acumulados
input_buffer  = np.zeros(FFT_SIZE, dtype=np.float32)
output_buffer = np.zeros(FFT_SIZE * 2, dtype=np.float32)  # era FFT_SIZE + BUFFER_SIZE

# Estado do Phase Vocoder
phase_in_prev  = np.zeros(FFT_SIZE // 2 + 1, dtype=np.float64)
phase_out_prev = np.zeros(FFT_SIZE // 2 + 1, dtype=np.float64)

# Frequências esperadas de cada bin (em radianos por amostra)
bin_freqs = 2 * np.pi * np.arange(FFT_SIZE // 2 + 1) / FFT_SIZE

# Janela de análise/síntese
window = np.hanning(FFT_SIZE).astype(np.float64)

# Fator de normalização do overlap-add
win_sum = np.zeros(FFT_SIZE * 2, dtype=np.float32)  # era FFT_SIZE + BUFFER_SIZE
for i in range(0, FFT_SIZE, HOP_SIZE):
    win_sum[i:i + FFT_SIZE] += window ** 2
win_sum = np.where(win_sum < 1e-8, 1e-8, win_sum)


def phase_vocoder_chunk(chunk):
    """
    Processa um chunk de amostras com Phase Vocoder.
    Retorna um chunk transposto de mesmo tamanho.
    """
    global input_buffer, output_buffer
    global phase_in_prev, phase_out_prev

    n_new = len(chunk)

    # Acumula novas amostras no buffer de entrada
    input_buffer = np.roll(input_buffer, -n_new)
    input_buffer[-n_new:] = chunk

    # Desloca o buffer de saída
    output_buffer = np.roll(output_buffer, -n_new)
    output_buffer[-n_new:] = 0.0

    # Processa cada hop dentro do chunk
    for hop_start in range(0, n_new, HOP_SIZE):

        # --- Análise ---
        frame = input_buffer * window
        spectrum = np.fft.rfft(frame)

        magnitude = np.abs(spectrum)
        phase_in  = np.angle(spectrum)

        # Diferença de fase entre frames consecutivos
        delta_phase = phase_in - phase_in_prev - bin_freqs * HOP_SIZE
        # Normaliza para [-pi, pi]
        delta_phase = delta_phase - 2 * np.pi * np.round(delta_phase / (2 * np.pi))

        # Frequência instantânea real de cada bin
        true_freq = bin_freqs + delta_phase / HOP_SIZE

        phase_in_prev[:] = phase_in

        # --- Mapeamento de bins (pitch shifting) ---
        # Cada bin de saída recebe a magnitude e frequência do bin de entrada
        # correspondente à transposição desejada
        n_bins = FFT_SIZE // 2 + 1
        mag_out   = np.zeros(n_bins)
        freq_out  = np.zeros(n_bins)

        k_out  = np.arange(n_bins)
        k_src  = np.clip(np.round(k_out / pitch_ratio).astype(int), 0, n_bins - 1)
        valid  = (k_src >= 0) & (k_src < n_bins)
        mag_out[valid]  = magnitude[k_src[valid]]
        freq_out[valid] = true_freq[k_src[valid]] * pitch_ratio

        # --- Síntese ---
        # Acumula fase de saída
        phase_out_prev += freq_out * HOP_SIZE
        # Normaliza para [-pi, pi]
        phase_out_prev = phase_out_prev - 2 * np.pi * np.round(phase_out_prev / (2 * np.pi))

        spectrum_out = mag_out * np.exp(1j * phase_out_prev)
        frame_out    = np.fft.irfft(spectrum_out).astype(np.float32)
        frame_out   *= window.astype(np.float32)

        # Overlap-add na posição correta do buffer de saída
        out_pos = FFT_SIZE - n_new + hop_start
        output_buffer[out_pos:out_pos + FFT_SIZE] += frame_out

    # Normaliza pelo overlap e retorna o chunk de saída
    out_chunk = output_buffer[:n_new] / win_sum[:n_new]
    return out_chunk.astype(np.float32)


def callback(indata, outdata, frames, time, status):
    if status:
        print(status)

    mono = indata[:, 0].astype(np.float32)
    processed = phase_vocoder_chunk(mono)
    outdata[:, 0] = processed

    # Se a saída tiver mais de um canal, silencia os demais
    if outdata.shape[1] > 1:
        outdata[:, 1:] = 0


print(f"Pitch shifter em tempo real — {SEMITONES:+d} semitons")
print(f"FFT: {FFT_SIZE} | Hop: {HOP_SIZE} | Buffer ASIO: {BUFFER_SIZE}")
print("Ctrl+C para parar\n")

with sd.Stream(samplerate=SAMPLE_RATE,
               blocksize=BUFFER_SIZE,
               dtype='float32',
               channels=1,
               device=(ASIO_DEVICE, ASIO_DEVICE),
               callback=callback):
    sd.sleep(30_000)