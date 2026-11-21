# Pitch shifter no Raspberry Pi (C + ALSA)

Port em C do phase vocoder em streaming de [`matlab/`](../matlab) (algoritmo do Grondin), para rodar no Raspberry Pi com a Focusrite Scarlett 4i4 via USB. O alvo é o **Raspberry Pi 2 Model B v1.1** (4 núcleos Cortex-A7 de 900 MHz, só 32 bits), mas o código roda em qualquer Pi ou Linux.

| Arquivo | O que faz | Equivale a |
|---|---|---|
| [src/pv.c](src/pv.c), [src/pv.h](src/pv.h) | Phase vocoder em streaming, troca de semitons em tempo de execução | `pvInit.m`, `pvSetSemitons.m`, `pvProcessBlock.m` |
| [src/pv_alsa.c](src/pv_alsa.c) | Laço de tempo real com ALSA direto, controle pelo teclado, medida de latência | `pitchShiftRT.m`, `medeLatencia.m` |
| [src/pv_offline.c](src/pv_offline.c) | Processa um WAV em blocos de B amostras e mede o custo de CPU | `testeOffline.m` |
| [tools/referencia.py](tools/referencia.py) | Cópia em numpy do `pvProcessBlock.m`, para conferir o C | |

## Validação (no PC, sem o Pi)

O C foi comparado com a referência em numpy (double, FFT complexa, linha a linha igual ao MATLAB):

| Sinal | Semitons | Diferença C vs referência |
|---|---|---|
| `A_natural.wav` | −5 | 84 dB abaixo do sinal |
| `strumming_chords.wav` | −5 / +5 / −12 | 58 a 60 dB abaixo do sinal |

A diferença vem do C usar float na FFT (o MATLAB usa double) e não é audível. Também confere com o MATLAB: latência do algoritmo de 960 amostras (N − B) num impulso, e senos de 440 Hz transpostos com erro de até 2 cents (o mesmo do `Hs` arredondado documentado em `pvSetSemitons.m`). Num PC x86 o bloco que calcula um quadro (FFT + IFFT, 1 a cada Ha/B blocos) custa ~31 µs, 2% do período de 1,45 ms. O Pi 2 deve ser de 20 a 40 vezes mais lento, o que daria de 0,6 a 1,2 ms: cabe, mas com pouca folga. Por isso o primeiro teste no Pi é o `pv_offline`, que mostra essa conta na linha "Bloco com quadro". Se passar de ~70% do orçamento, use `-p 128` ou `-N 512 -H 128`.

## Preparar o Pi

1. Grave o **Raspberry Pi OS Lite (32 bits)** com o Raspberry Pi Imager (ative o SSH nas opções). O Pi 2 v1.1 não roda a versão de 64 bits. A versão Lite não tem desktop nem PipeWire, que poderiam ocupar a interface de áudio. O Pi 2 não tem Wi-Fi: acesse por SSH pelo cabo de rede, que no Pi 2 passa pelo mesmo USB da Scarlett, então evite copiar arquivos enquanto toca.
2. Instale as dependências e compile:
   ```bash
   sudo apt update
   sudo apt install build-essential git libfftw3-dev libasound2-dev alsa-utils
   git clone https://github.com/guisantovski/pitch-shifter-tcc.git
   cd pitch-shifter-tcc/pi && make
   ```
3. Permissão de tempo real sem `sudo` (depois, saia e entre de novo na sessão):
   ```bash
   sudo usermod -aG audio $USER
   echo '@audio - rtprio 95
   @audio - memlock unlimited' | sudo tee /etc/security/limits.d/audio.conf
   ```
4. CPU sempre no máximo (evita xruns quando o clock sobe e desce):
   ```bash
   echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   ```
5. Ligue a Scarlett numa porta USB e confira o nome com `aplay -l` e `arecord -l`. Ela costuma aparecer como card `USB`, e por isso o padrão é `-d hw:USB`. Se não for, use `-d hw:N` com o número do card.
   - Use a fonte na porta de alimentação USB da 4i4: as portas do Pi 2 fornecem pouca corrente (600 mA no total, por padrão).
   - Desligue o direct monitor da interface, senão o som original sai junto.

## Usar

```bash
./pv_offline ../audio_samples/A_natural.wav /tmp/A_-5.wav -5   # teste sem interface + custo de CPU
./pv_alsa --bypass                 # passthrough: confere a interface e os xruns
./pv_alsa -s -5                    # pitch shifter, guitarra no Input 1 (INST ligado)
./pv_alsa -s -5 -N 512 -H 128      # quadro menor: menos latência
./pv_alsa -p 128 -n 3              # se houver xruns com 64
```

Durante a execução, digite um número e Enter para trocar os semitons (ex.: `-7`), `+` ou `-` para subir ou descer 1, `e` para ver as estatísticas (xruns e tempo de processamento) e `q` para sair.

### Medir a latência

Mesma ligação do `medeLatencia.m`: cabo da saída Output 1 para o Input 2, com INST desligado e o ganho do Input 2 no mínimo.

```bash
./pv_alsa --latencia --bypass -c 1   # latência de I/O (USB + conversores + buffers)
./pv_alsa --latencia -c 1            # total, que é o que o guitarrista sente
```

O programa manda um clique a cada 0,5 s e mostra a mediana de 12 medidas. A diferença entre as duas medidas deve dar N − B (21,8 ms com N = 1024, B = 64 a 44,1 kHz).
