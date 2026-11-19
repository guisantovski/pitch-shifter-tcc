/*
 * pv_offline - passa um WAV pelo pv_processa_bloco em blocos de B amostras,
 * exatamente como o laço de tempo real (equivale a matlab/testeOffline.m).
 * Também mede o custo do algoritmo na CPU em que roda (útil no Pi).
 *
 *   ./pv_offline entrada.wav saida.wav semitons [N] [Ha] [B]
 */
#include "pv.h"
#include "wav.h"

#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static double agora(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + 1e-9 * t.tv_nsec;
}

int main(int argc, char **argv)
{
    if (argc < 4) {
        fprintf(stderr, "uso: %s entrada.wav saida.wav semitons [N=1024] [Ha=256] [B=64]\n", argv[0]);
        return 1;
    }
    int st = atoi(argv[3]);
    int N  = argc > 4 ? atoi(argv[4]) : 1024;
    int Ha = argc > 5 ? atoi(argv[5]) : 256;
    int B  = argc > 6 ? atoi(argv[6]) : 64;

    int n = 0, fs = 0;
    float *x = wav_le(argv[1], &n, &fs);
    if (!x) { fprintf(stderr, "não consegui ler %s\n", argv[1]); return 1; }

    pv_t *pv = pv_cria(N, Ha, B, st);
    if (!pv) { fprintf(stderr, "parâmetros inválidos (N potência de 2, Ha múltiplo de B, |semitons| <= 12)\n"); return 1; }

    int nBlocos = n / B;
    float *y = calloc((size_t)nBlocos * B + 1, sizeof(float));
    double pior = 0, total = 0;
    for (int b = 0; b < nBlocos; b++) {
        double t0 = agora();
        pv_processa_bloco(pv, x + (size_t)b * B, y + (size_t)b * B);
        double dt = agora() - t0;
        total += dt;
        if (dt > pior) pior = dt;
    }

    if (wav_grava(argv[2], y, nBlocos * B, fs)) { fprintf(stderr, "não consegui gravar %s\n", argv[2]); return 1; }

    double orcamento = (double)B / fs;
    printf("%d amostras a %d Hz, %+d semitons, N=%d Ha=%d B=%d\n", n, fs, st, N, Ha, B);
    printf("Processamento: médio %.1f us/bloco, pior %.1f us (orçamento %.0f us, uso médio %.1f%%)\n",
           1e6 * total / nBlocos, 1e6 * pior, 1e6 * orcamento, 100 * total / (nBlocos * orcamento));
    printf("Latência do algoritmo: %d amostras = %.1f ms\n", pv_latencia(pv), 1e3 * pv_latencia(pv) / fs);

    pv_destroi(pv);
    free(x); free(y);
    return 0;
}
