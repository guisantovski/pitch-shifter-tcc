/*
 * pv.c - Phase vocoder do Grondin em streaming (ver pv.h).
 *
 * Cada passo corresponde ao bloco de mesmo número em pvProcessBlock.m.
 */
#define _GNU_SOURCE   /* sincosf */
#include "pv.h"

#include <fftw3.h>
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define DOIS_PI 6.283185307179586

struct pv {
    int N, Ha, B, R, M;          /* M = N/2 + 1 bins (FFT real) */

    float *win;                  /* Hann periódica (análise e síntese) */
    double *omega;               /* freq. central de cada bin (rad/amostra) */
    double *hopFase;             /* Ha*omega reduzido a [0, 2pi) */

    float *inBuf;                /* últimas N amostras de entrada */
    float *ola;                  /* overlap-add, 2N + Ha amostras */
    float *outBlk;               /* hop pronto para sair (Ha amostras) */
    int    blk, cont;

    /* Estado recursivo (M bins). As fases ficam em double porque Hs*freqV
     * chega a ~1600 rad e o float perderia ~1e-4 rad por quadro. */
    double *fasePrev, *faseSint;

    /* Parâmetros que dependem dos semitons (pvSetSemitons.m) */
    int    semitons, Hs, L;
    double alfa;
    float  ganhoOla;
    atomic_int pedido;           /* semitons pedidos por outra thread */

    /* FFTW */
    float         *tempo;        /* N amostras: entrada da FFT / saída da IFFT */
    fftwf_complex *espec;        /* M bins */
    fftwf_plan     fwd, inv;
};

static void define_semitons(pv_t *pv, int semitons)
{
    pv->semitons = semitons;
    pv->Hs   = (int)lround(pow(2.0, semitons / 12.0) * pv->Ha);
    pv->alfa = (double)pv->Hs / pv->Ha;
    pv->L    = (int)floor((pv->N - 1) / pv->alfa) + 1;
    /* Hann^2 somada com hop Hs vale 3N/(8Hs). A IFFT da FFTW não divide
     * por N, então a normalização entra aqui também. */
    pv->ganhoOla = (float)(8.0 * pv->Hs / (3.0 * pv->N) / pv->N);
}

pv_t *pv_cria(int N, int Ha, int B, int semitons)
{
    if (N < 16 || (N & (N - 1)) || B <= 0 || Ha <= 0 || Ha % B || Ha > N ||
        semitons < -12 || semitons > 12)
        return NULL;

    pv_t *pv = calloc(1, sizeof *pv);
    if (!pv) return NULL;
    pv->N = N; pv->Ha = Ha; pv->B = B; pv->R = Ha / B; pv->M = N / 2 + 1;

    pv->win      = calloc(N, sizeof(float));
    pv->omega    = calloc(pv->M, sizeof(double));
    pv->hopFase  = calloc(pv->M, sizeof(double));
    pv->inBuf    = calloc(N, sizeof(float));
    pv->ola      = calloc(2 * N + Ha, sizeof(float));
    pv->outBlk   = calloc(Ha, sizeof(float));
    pv->fasePrev = calloc(pv->M, sizeof(double));
    pv->faseSint = calloc(pv->M, sizeof(double));
    pv->tempo    = fftwf_alloc_real(N);
    pv->espec    = fftwf_alloc_complex(pv->M);
    if (!pv->win || !pv->omega || !pv->hopFase || !pv->inBuf || !pv->ola ||
        !pv->outBlk || !pv->fasePrev || !pv->faseSint || !pv->tempo || !pv->espec) {
        pv_destroi(pv);
        return NULL;
    }

    for (int n = 0; n < N; n++)
        pv->win[n] = (float)(0.5 - 0.5 * cos(DOIS_PI * n / N));
    for (int k = 0; k < pv->M; k++) {
        double w = DOIS_PI * k / N;
        pv->omega[k]   = w;
        pv->hopFase[k] = fmod(Ha * w, DOIS_PI);
    }

    /* FFTW_MEASURE escolhe o algoritmo mais rápido para esta CPU (leva
     * alguns ms, só na inicialização). */
    pv->fwd = fftwf_plan_dft_r2c_1d(N, pv->tempo, pv->espec, FFTW_MEASURE);
    pv->inv = fftwf_plan_dft_c2r_1d(N, pv->espec, pv->tempo, FFTW_MEASURE);
    if (!pv->fwd || !pv->inv) { pv_destroi(pv); return NULL; }

    pv->blk = 0;
    pv->cont = 0;
    define_semitons(pv, semitons);
    atomic_init(&pv->pedido, semitons);
    return pv;
}

void pv_destroi(pv_t *pv)
{
    if (!pv) return;
    if (pv->fwd) fftwf_destroy_plan(pv->fwd);
    if (pv->inv) fftwf_destroy_plan(pv->inv);
    fftwf_free(pv->tempo);
    fftwf_free(pv->espec);
    free(pv->win); free(pv->omega); free(pv->hopFase);
    free(pv->inBuf); free(pv->ola); free(pv->outBlk);
    free(pv->fasePrev); free(pv->faseSint);
    free(pv);
}

int pv_pede_semitons(pv_t *pv, int semitons)
{
    if (semitons < -12 || semitons > 12) return -1;
    atomic_store_explicit(&pv->pedido, semitons, memory_order_relaxed);
    return 0;
}

int pv_semitons(const pv_t *pv) { return pv->semitons; }
int pv_latencia(const pv_t *pv) { return pv->N - pv->B; }

static inline double envolve(double f)  /* reduz uma fase a [-pi, pi] */
{
    return f - DOIS_PI * rint(f * (1.0 / DOIS_PI));
}

static void processa_quadro(pv_t *pv)
{
    const int N = pv->N, M = pv->M, Ha = pv->Ha;

    int pedido = atomic_load_explicit(&pv->pedido, memory_order_relaxed);
    if (pedido != pv->semitons)
        define_semitons(pv, pedido);

    /* 1. Análise */
    for (int n = 0; n < N; n++)
        pv->tempo[n] = pv->win[n] * pv->inBuf[n];
    fftwf_execute(pv->fwd);

    const double Hs = pv->Hs;
    for (int k = 0; k < M; k++) {
        float  re = pv->espec[k][0], im = pv->espec[k][1];
        float  mag  = sqrtf(re * re + im * im);
        double fase = atan2f(im, re);

        /* 2. Frequência verdadeira (rad/amostra) */
        double dfase = envolve(fase - pv->fasePrev[k] - pv->hopFase[k]);
        double freqV = pv->omega[k] + dfase / Ha;
        pv->fasePrev[k] = fase;

        /* 3. Fase de síntese acumulada com o hop Hs (em double; depois de
         * envolvida cabe em [-pi, pi] e o seno/cosseno em float bastam,
         * o que importa no Cortex-A7 do Pi 2) */
        double fs = envolve(pv->faseSint[k] + Hs * freqV);
        pv->faseSint[k] = fs;

        /* 4. Espectro de síntese (a IFFT vem logo abaixo) */
        float c, sn;
        sincosf((float)fs, &sn, &c);
        pv->espec[k][0] = mag * c;
        pv->espec[k][1] = mag * sn;
    }

    /* 4. Síntese */
    fftwf_execute(pv->inv);
    for (int n = 0; n < N; n++)
        pv->tempo[n] *= pv->win[n];

    /* 5 e 6. Reamostragem linear do grão (N -> L amostras) direto no
     * overlap-add */
    const int L = pv->L;
    const float g = pv->ganhoOla;
    /* Posição de leitura em ponto fixo (Hs/Ha exato, sem acumular erro):
     * t = i*Hs/Ha = i0 + num/Ha */
    const int Hs_ = pv->Hs;
    const float invHa = 1.0f / Ha;
    int i0 = 0, num = 0;
    for (int i = 0; i < L; i++) {
        float fr = num * invHa;
        int   i1 = i0 + 1 < N ? i0 + 1 : N - 1;
        float v  = pv->tempo[i0] + fr * (pv->tempo[i1] - pv->tempo[i0]);
        pv->ola[i] += g * v;
        num += Hs_;
        while (num >= Ha) { num -= Ha; i0++; }
    }
    const int tamOla = 2 * N + Ha;
    memcpy(pv->outBlk, pv->ola, Ha * sizeof(float));
    memmove(pv->ola, pv->ola + Ha, (tamOla - Ha) * sizeof(float));
    memset(pv->ola + tamOla - Ha, 0, Ha * sizeof(float));
    pv->blk = 0;
}

void pv_processa_bloco(pv_t *pv, const float *x, float *y)
{
    const int N = pv->N, B = pv->B;

    /* Entrada: desloca o buffer e acrescenta o bloco novo */
    memmove(pv->inBuf, pv->inBuf + B, (N - B) * sizeof(float));
    memcpy(pv->inBuf + N - B, x, B * sizeof(float));

    if (++pv->cont == pv->R) {
        pv->cont = 0;
        processa_quadro(pv);
    }

    /* Saída: próximo pedaço de B amostras do hop pronto */
    memcpy(y, pv->outBlk + pv->blk * B, B * sizeof(float));
    pv->blk++;
}
