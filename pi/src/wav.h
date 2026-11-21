/* wav.h - leitura e escrita mínimas de WAV (só para o teste offline). */
#ifndef WAV_H
#define WAV_H

/* Lê PCM 16/24/32 bits ou float 32 e mistura os canais em mono.
 * Devolve o vetor (liberar com free) ou NULL; *n = amostras, *fs = taxa. */
float *wav_le(const char *arq, int *n, int *fs);

/* Grava mono em float 32. Devolve 0 se ok. */
int wav_grava(const char *arq, const float *x, int n, int fs);

#endif
