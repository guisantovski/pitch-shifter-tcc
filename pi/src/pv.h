/*
 * pv.h - Phase vocoder do Grondin (guitarpitchshifter.com) em streaming.
 *
 * Port em C de matlab/pvInit.m, pvSetSemitons.m e pvProcessBlock.m.
 * Mesmo algoritmo e mesmos parâmetros; a diferença é que a FFT é real
 * (FFTW r2c/c2r, só N/2+1 bins) e as contas são em float.
 *
 * Uso típico (laço de áudio):
 *     pv_t *pv = pv_cria(1024, 256, 64, -5);
 *     for (;;) { ler B amostras; pv_processa_bloco(pv, x, y); escrever y; }
 *     pv_destroi(pv);
 *
 * Troca de semitons em tempo de execução: pv_pede_semitons() pode ser
 * chamada de qualquer thread (ex.: a que lê o pedal/teclado); a troca é
 * aplicada pela thread de áudio no próximo quadro, sem reiniciar o estado.
 */
#ifndef PV_H
#define PV_H

typedef struct pv pv_t;

/* N: tamanho do quadro/FFT (potência de 2). Ha: hop de análise. B: bloco
 * de I/O (Ha tem que ser múltiplo de B). semitons: -12..12.
 * Devolve NULL se os parâmetros forem inválidos. */
pv_t *pv_cria(int N, int Ha, int B, int semitons);
void  pv_destroi(pv_t *pv);

/* Processa B amostras (x -> y). x e y podem ser o mesmo vetor.
 * Seguro para tempo real: não aloca memória nem trava. */
void  pv_processa_bloco(pv_t *pv, const float *x, float *y);

/* Pede a troca de semitons (thread-safe, sem lock). Devolve 0 se ok,
 * -1 se fora de -12..12. */
int   pv_pede_semitons(pv_t *pv, int semitons);
int   pv_semitons(const pv_t *pv);       /* valor em uso agora */

/* Latência do algoritmo em amostras (N - B, como medido no MATLAB). */
int   pv_latencia(const pv_t *pv);

#endif
