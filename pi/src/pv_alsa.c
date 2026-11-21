/*
 * pv_alsa - pitch shifter em tempo real no Raspberry Pi (ou qualquer
 * Linux) com ALSA direto, sem JACK. Equivale a matlab/pitchShiftRT.m e,
 * com --latencia, a matlab/medeLatencia.m.
 *
 *   ./pv_alsa [opções]
 *     -d DEV   dispositivo ALSA (padrão hw:USB, a Scarlett; veja `aplay -l`)
 *     -r FS    taxa de amostragem (padrão 44100, igual ao MATLAB)
 *     -p B     período = bloco de I/O em amostras (padrão 64)
 *     -n NP    períodos no buffer de saída (padrão 2)
 *     -c CH    canal de entrada, contando do 0 (padrão 0 = Input 1)
 *     -s ST    semitons iniciais (padrão -5)
 *     -N N     quadro/FFT (padrão 1024)   -H Ha  hop de análise (padrão 256)
 *     -g G     ganho de saída (padrão 1.0)
 *     --bypass     só copia entrada -> saída (passthrough)
 *     --latencia   mede a latência com um cabo de loopback (ver README)
 *     --grava SEG  grava SEG segundos da entrada e da saída do phase vocoder
 *                  em grav_entrada.wav e grav_saida.wav (para comparar com o
 *                  processamento offline; mantenha os semitons fixos)
 *
 * Durante a execução, digite no terminal e tecle Enter:
 *     número (ex.: -7)  troca os semitons     + / -  sobe / desce 1
 *     e  estatísticas    q  sai
 */
#define _GNU_SOURCE
#include "pv.h"
#include "wav.h"

#include <alsa/asoundlib.h>
#include <math.h>
#include <pthread.h>
#include <sched.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>

/* ---------- configuração ---------- */
static const char *dev = "hw:USB";
static unsigned fs = 44100;
static int B = 64, NP = 2, canalIn = 0, semitons = -5, N = 1024, Ha = 256;
static float ganho = 1.0f;
static int bypass = 0, latencia = 0;
static int linkado = 0;
static int gravaSeg = 0;

/* ---------- estado compartilhado com a thread de controle ---------- */
static atomic_int rodando = 1;
static atomic_long xruns, blocos, acimaOrcamento;
static atomic_llong piorNs, somaNs;   /* 64 bits também no Pi 2 (32 bits) */

/* ---------- ALSA ---------- */
typedef struct {
    snd_pcm_t *pcm;
    snd_pcm_format_t fmt;
    unsigned canais;
    void *buf;
} lado_t;

#define CHECA(x) do { int _e = (x); if (_e < 0) { \
    fprintf(stderr, "%s: %s\n", #x, snd_strerror(_e)); exit(1); } } while (0)

static void abre(lado_t *l, snd_pcm_stream_t dir)
{
    snd_pcm_hw_params_t *hw;
    snd_pcm_sw_params_t *sw;
    const char *nome = dir == SND_PCM_STREAM_CAPTURE ? "captura" : "reprodução";

    CHECA(snd_pcm_open(&l->pcm, dev, dir, 0));
    snd_pcm_hw_params_alloca(&hw);
    CHECA(snd_pcm_hw_params_any(l->pcm, hw));
    CHECA(snd_pcm_hw_params_set_access(l->pcm, hw, SND_PCM_ACCESS_RW_INTERLEAVED));

    /* A Scarlett usa S32_LE; S16_LE cobre interfaces mais simples. */
    l->fmt = SND_PCM_FORMAT_S32_LE;
    if (snd_pcm_hw_params_set_format(l->pcm, hw, l->fmt) < 0) {
        l->fmt = SND_PCM_FORMAT_S16_LE;
        CHECA(snd_pcm_hw_params_set_format(l->pcm, hw, l->fmt));
    }
    /* Interfaces USB costumam expor um número fixo de canais (a 4i4 tem
     * 4 de entrada e 4 de saída): usa o menor que o hardware aceita, no
     * mínimo 2 na saída. */
    unsigned cmin;
    CHECA(snd_pcm_hw_params_get_channels_min(hw, &cmin));
    if (dir == SND_PCM_STREAM_PLAYBACK && cmin < 2) cmin = 2;
    if (snd_pcm_hw_params_set_channels(l->pcm, hw, cmin) < 0)
        CHECA(snd_pcm_hw_params_set_channels_first(l->pcm, hw, &cmin));
    l->canais = cmin;

    CHECA(snd_pcm_hw_params_set_rate(l->pcm, hw, fs, 0));
    snd_pcm_uframes_t per = B, buf = (snd_pcm_uframes_t)B * NP;
    CHECA(snd_pcm_hw_params_set_period_size(l->pcm, hw, per, 0));
    if (dir == SND_PCM_STREAM_CAPTURE)
        buf = (snd_pcm_uframes_t)B * (NP > 4 ? NP : 4);   /* folga na captura não custa latência */
    CHECA(snd_pcm_hw_params_set_buffer_size_near(l->pcm, hw, &buf));
    CHECA(snd_pcm_hw_params(l->pcm, hw));

    snd_pcm_sw_params_alloca(&sw);
    CHECA(snd_pcm_sw_params_current(l->pcm, sw));
    CHECA(snd_pcm_sw_params_set_avail_min(l->pcm, sw, B));
    /* A reprodução só começa junto com a captura (snd_pcm_link). */
    CHECA(snd_pcm_sw_params_set_start_threshold(l->pcm, sw,
          dir == SND_PCM_STREAM_PLAYBACK ? buf * 2 : 1));
    CHECA(snd_pcm_sw_params(l->pcm, sw));

    l->buf = calloc((size_t)B * l->canais, snd_pcm_format_physical_width(l->fmt) / 8);
    fprintf(stderr, "%s: %s, %u canais, %s, período %d, buffer %lu\n", nome, dev,
            l->canais, snd_pcm_format_name(l->fmt), B, (unsigned long)buf);
}

static void para_float(const lado_t *l, int canal, float *x)
{
    if (l->fmt == SND_PCM_FORMAT_S32_LE)
        for (int i = 0; i < B; i++) x[i] = ((int32_t *)l->buf)[i * l->canais + canal] * (1.0f / 2147483648.0f);
    else
        for (int i = 0; i < B; i++) x[i] = ((int16_t *)l->buf)[i * l->canais + canal] * (1.0f / 32768.0f);
}

static void de_float(lado_t *l, const float *y)
{
    for (int i = 0; i < B; i++) {
        float v = y[i] * ganho;
        if (v > 1.0f) v = 1.0f; else if (v < -1.0f) v = -1.0f;
        for (unsigned c = 0; c < l->canais; c++) {
            float vc = c < 2 ? v : 0.0f;          /* Outputs 1 e 2 */
            if (l->fmt == SND_PCM_FORMAT_S32_LE)
                ((int32_t *)l->buf)[i * l->canais + c] = (int32_t)lrintf(vc * 2147483520.0f);
            else
                ((int16_t *)l->buf)[i * l->canais + c] = (int16_t)lrintf(vc * 32767.0f);
        }
    }
}

/* Zera a reprodução com NP períodos de silêncio e dispara as duas pontas
 * (que estão ligadas). Esses NP períodos são a latência de buffer. */
static void inicia(lado_t *cap, lado_t *rep)
{
    snd_pcm_drop(cap->pcm);
    snd_pcm_drop(rep->pcm);
    CHECA(snd_pcm_prepare(rep->pcm));      /* se linkadas, prepara as duas */
    if (!linkado) CHECA(snd_pcm_prepare(cap->pcm));
    memset(rep->buf, 0, (size_t)B * rep->canais * snd_pcm_format_physical_width(rep->fmt) / 8);
    for (int i = 0; i < NP; i++)
        CHECA(snd_pcm_writei(rep->pcm, rep->buf, B));
    CHECA(snd_pcm_start(cap->pcm));
    if (!linkado) CHECA(snd_pcm_start(rep->pcm));
}

/* ---------- thread de controle (teclado) ---------- */
static pv_t *pv;

static void imprime_estatisticas(void)
{
    long nb = atomic_load(&blocos);
    fprintf(stderr, "semitons %+d | blocos %ld | xruns %ld | proc. médio %.1f us, pior %.1f us "
            "(orçamento %.0f us) | acima do orçamento: %ld\n",
            pv ? pv_semitons(pv) : 0, nb, atomic_load(&xruns),
            nb ? 1e-3 * atomic_load(&somaNs) / nb : 0.0, 1e-3 * atomic_load(&piorNs),
            1e6 * B / fs, atomic_load(&acimaOrcamento));
}

static void *controle(void *arg)
{
    (void)arg;
    char linha[64];
    while (atomic_load(&rodando) && fgets(linha, sizeof linha, stdin)) {
        if (linha[0] == 'q') { atomic_store(&rodando, 0); break; }
        if (linha[0] == 'e') { imprime_estatisticas(); continue; }
        if (!pv) continue;
        int alvo = pv_semitons(pv);
        if (linha[0] == '+' && (linha[1] == '\n' || !linha[1])) alvo++;
        else if (linha[0] == '-' && (linha[1] == '\n' || !linha[1])) alvo--;
        else if (sscanf(linha, "%d", &alvo) != 1) continue;
        if (pv_pede_semitons(pv, alvo) == 0) fprintf(stderr, "-> %+d semitons\n", alvo);
        else fprintf(stderr, "use de -12 a 12\n");
    }
    return NULL;
}

static void sai(int s) { (void)s; atomic_store(&rodando, 0); }

static long long ns(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long long)t.tv_sec * 1000000000LL + t.tv_nsec;
}

static int compara(const void *a, const void *b) { return *(const int *)a - *(const int *)b; }

int main(int argc, char **argv)
{
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i], *v = i + 1 < argc ? argv[i + 1] : NULL;
        if (!strcmp(a, "--bypass")) bypass = 1;
        else if (!strcmp(a, "--latencia")) latencia = 1;
        else if (v && !strcmp(a, "--grava")) gravaSeg = atoi(argv[++i]);
        else if (v && !strcmp(a, "-d")) dev = argv[++i];
        else if (v && !strcmp(a, "-r")) fs = (unsigned)atoi(argv[++i]);
        else if (v && !strcmp(a, "-p")) B = atoi(argv[++i]);
        else if (v && !strcmp(a, "-n")) NP = atoi(argv[++i]);
        else if (v && !strcmp(a, "-c")) canalIn = atoi(argv[++i]);
        else if (v && !strcmp(a, "-s")) semitons = atoi(argv[++i]);
        else if (v && !strcmp(a, "-N")) N = atoi(argv[++i]);
        else if (v && !strcmp(a, "-H")) Ha = atoi(argv[++i]);
        else if (v && !strcmp(a, "-g")) ganho = (float)atof(argv[++i]);
        else { fprintf(stderr, "opção desconhecida: %s (veja o cabeçalho de pv_alsa.c)\n", a); return 1; }
    }
    if (latencia) semitons = 0;      /* clique reconhecível na saída */

    if (!bypass) {
        pv = pv_cria(N, Ha, B, semitons);
        if (!pv) { fprintf(stderr, "parâmetros inválidos do phase vocoder\n"); return 1; }
    }

    lado_t cap = {0}, rep = {0};
    abre(&cap, SND_PCM_STREAM_CAPTURE);
    abre(&rep, SND_PCM_STREAM_PLAYBACK);
    if ((unsigned)canalIn >= cap.canais) { fprintf(stderr, "canal %d não existe\n", canalIn); return 1; }
    /* Liga as duas pontas no mesmo relógio de partida (a Scarlett aceita;
     * se o dispositivo não aceitar, parte as duas em seguida). */
    linkado = snd_pcm_link(cap.pcm, rep.pcm) == 0;
    if (!linkado) fprintf(stderr, "aviso: snd_pcm_link indisponível, partindo as pontas separadamente\n");

    float *x = calloc(B, sizeof(float)), *y = calloc(B, sizeof(float));
    long nRec = 0, posRec = 0;           /* gravação opcional (--grava) */
    float *recX = NULL, *recY = NULL;
    if (gravaSeg > 0 && !latencia && !bypass) {
        nRec = (long)gravaSeg * (long)fs;
        recX = calloc(nRec, sizeof(float));
        recY = calloc(nRec, sizeof(float));
        if (!recX || !recY) { fprintf(stderr, "sem memória para --grava %d\n", gravaSeg); return 1; }
    }

    signal(SIGINT, sai);
    signal(SIGTERM, sai);
    if (!latencia) {
        /* Thread do teclado, criada ANTES do mlockall e com pilha pequena:
         * com MCL_FUTURE e o limite de memlock padrão do Pi OS (poucos MB),
         * uma pilha de 8 MB não cabe e o pthread_create falha. */
        pthread_attr_t at;
        pthread_attr_init(&at);
        pthread_attr_setstacksize(&at, 128 * 1024);
        pthread_t thCtl;
        int e = pthread_create(&thCtl, &at, controle, NULL);
        if (e) {
            fprintf(stderr, "aviso: sem controle pelo teclado (pthread_create: %s)\n", strerror(e));
        } else {
            pthread_detach(thCtl);
            fprintf(stderr, "Rodando %s. Digite semitons (ex.: -7), + ou -, e (estatísticas) ou q.\n",
                    bypass ? "em bypass" : "o phase vocoder");
        }
    }

    /* Tempo real: trava a memória e pede prioridade SCHED_FIFO. Precisa de
     * root ou do grupo audio com rtprio (ver README). Tudo já foi alocado
     * acima, então se o limite de memlock for baixo basta travar o que
     * existe. */
    if (mlockall(MCL_CURRENT | MCL_FUTURE) && mlockall(MCL_CURRENT))
        fprintf(stderr, "aviso: mlockall falhou (configure memlock, ver README)\n");
    struct sched_param sp = { .sched_priority = 80 };
    if (pthread_setschedparam(pthread_self(), SCHED_FIFO, &sp))
        fprintf(stderr, "aviso: sem SCHED_FIFO, pode haver xruns (rode com sudo ou configure rtprio)\n");

    const long long orcNs = (long long)(1e9 * B / fs);

    /* Medida de latência: clique a cada 0,5 s, procura o pico na entrada */
    const long periodo = fs / 2, janela = fs / 4;
    const int nCliques = 12;
    int atrasos[64], nAtr = 0;
    long t = 0, ultimoClique = -1, picoPos = -1;
    float picoVal = 0;
    if (latencia)
        fprintf(stderr, "Medindo latência (%s): ligue Output 1 -> Input %d com cabo, INST desligado.\n",
                bypass ? "só I/O" : "I/O + phase vocoder", canalIn + 1);

    inicia(&cap, &rep);
    while (atomic_load(&rodando)) {
        snd_pcm_sframes_t r = snd_pcm_readi(cap.pcm, cap.buf, B);
        if (r == -EPIPE || r == -ESTRPIPE || r == -EIO) {
            atomic_fetch_add(&xruns, 1); inicia(&cap, &rep); continue;
        } else if (r < 0) { fprintf(stderr, "readi: %s\n", snd_strerror((int)r)); break; }

        long long t0 = ns();
        para_float(&cap, canalIn, x);

        if (latencia) {
            /* procura o pico da entrada na janela depois de cada clique */
            for (int i = 0; i < B; i++) {
                long ti = t + i;
                if (ultimoClique >= 0 && ti - ultimoClique < janela && fabsf(x[i]) > picoVal) {
                    picoVal = fabsf(x[i]); picoPos = ti;
                }
                if (ultimoClique >= 0 && ti - ultimoClique == janela) {
                    if (picoVal > 0.05f && nAtr < 64) atrasos[nAtr++] = (int)(picoPos - ultimoClique);
                    picoVal = 0; picoPos = -1;
                }
                /* gera o clique; os 2 primeiros (partida) são descartados */
                x[i] = (ti % periodo == 0 && ti > 0) ? 0.5f : 0.0f;
                if (x[i] != 0 && ti / periodo > 2) ultimoClique = ti;
            }
            if (nAtr >= nCliques || t > 15L * (long)fs) atomic_store(&rodando, 0);   /* 15 s no máximo */
        }

        if (bypass) memcpy(y, x, B * sizeof(float));
        else pv_processa_bloco(pv, x, y);
        if (recX && posRec + B <= nRec) {
            memcpy(recX + posRec, x, B * sizeof(float));
            memcpy(recY + posRec, y, B * sizeof(float));
            posRec += B;
            if (posRec + B > nRec) atomic_store(&rodando, 0);   /* gravou tudo */
        }
        de_float(&rep, y);

        long long dt = ns() - t0;
        atomic_fetch_add(&blocos, 1);
        atomic_fetch_add(&somaNs, dt);
        if (dt > atomic_load(&piorNs)) atomic_store(&piorNs, dt);
        if (dt > orcNs) atomic_fetch_add(&acimaOrcamento, 1);

        snd_pcm_sframes_t w = snd_pcm_writei(rep.pcm, rep.buf, B);
        if (w == -EPIPE || w == -ESTRPIPE || w == -EIO) {
            atomic_fetch_add(&xruns, 1); inicia(&cap, &rep); continue;
        } else if (w < 0) { fprintf(stderr, "writei: %s\n", snd_strerror((int)w)); break; }
        t += B;
    }

    imprime_estatisticas();
    if (latencia) {
        if (nAtr == 0) {
            fprintf(stderr, "Nenhum clique detectado: confira o cabo e o ganho do Input %d.\n", canalIn + 1);
        } else {
            qsort(atrasos, nAtr, sizeof(int), compara);
            int med = atrasos[nAtr / 2];
            fprintf(stderr, "Latência %s: mediana %d amostras = %.2f ms (mín %.2f, máx %.2f, %d cliques)\n",
                    bypass ? "de I/O" : "total (I/O + algoritmo)", med, 1e3 * med / fs,
                    1e3 * atrasos[0] / fs, 1e3 * atrasos[nAtr - 1] / fs, nAtr);
            if (!bypass)
                fprintf(stderr, "Teoria do algoritmo: N - B = %d amostras = %.2f ms\n",
                        N - B, 1e3 * (N - B) / fs);
        }
    }

    if (recX) {
        if (wav_grava("grav_entrada.wav", recX, (int)posRec, (int)fs) ||
            wav_grava("grav_saida.wav", recY, (int)posRec, (int)fs))
            fprintf(stderr, "não consegui gravar grav_*.wav\n");
        else
            fprintf(stderr, "Gravados grav_entrada.wav e grav_saida.wav (%ld amostras, %+d semitons)\n",
                    posRec, pv_semitons(pv));
    }
    snd_pcm_drop(rep.pcm);
    snd_pcm_close(rep.pcm);
    snd_pcm_close(cap.pcm);
    pv_destroi(pv);
    return 0;
}
