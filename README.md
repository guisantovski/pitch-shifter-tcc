# pitch-shifter-tcc

Pitch shifter de áudio em tempo real, desenvolvido como Trabalho de Conclusão de Curso (USP).

O objetivo é transpor o sinal de um instrumento ao vivo, com latência baixa o suficiente para tocar, e comparar o resultado com a mesma nota tocada de forma natural. O caso de teste principal é **Lá → Mi (−5 semitons)**.

## Estado atual

| Componente | Arquivo | Situação |
|---|---|---|
| Exploração offline (librosa) | [notebooks/01_exploracao.ipynb](notebooks/01_exploracao.ipynb) | Funcional |
| Passthrough ASIO (teste de latência) | [src/passthrough.py](src/passthrough.py) | Funcional |
| Passthrough ASIO em MATLAB (Audio Toolbox) | [matlab/passthrough.m](matlab/passthrough.m) | Funcional |
| Phase vocoder do Grondin em tempo real (MATLAB) | [matlab/pitchShiftRT.m](matlab/pitchShiftRT.m) | Funcional: testado com a guitarra até ±6 semitons; validação offline em [matlab/testeOffline.m](matlab/testeOffline.m) |
| Medição de latência por loopback (MATLAB) | [matlab/medeLatencia.m](matlab/medeLatencia.m) | Validado em simulação; falta medir na Scarlett |
| Phase vocoder em tempo real | [src/phase_vocoder_real_time.py](src/phase_vocoder_real_time.py) | Em ajuste |
| PSOLA | [src/psola.py](src/psola.py) | A implementar |
| Pipeline em tempo real | [src/realtime.py](src/realtime.py) | A implementar |

[src/passthrough_old.py](src/passthrough_old.py) é a versão antiga do passthrough (MME/WASAPI, `int16`, buffer 256), mantida para referência.

## Estrutura

```
audio_samples/           Gravações originais (Lá e Mi naturais) e teste com "gardenia"
audio_samples_shifted/   Lá transposto para Mi pelo librosa, para comparação com o Mi natural
notebooks/               Análise exploratória: forma de onda, estimativa de f0 (pYIN), pitch shift offline
src/                     Scripts de processamento em tempo real
```

As amostras `A_*` e `E_*` vêm em quatro variações: `natural`, `bleed`, `pedal_open` e `pedal_pm` (palm mute). Cada `A_*_shifted_to_E.wav` deve ser comparado com o `E_*` correspondente.

## Requisitos

- Windows com uma interface de áudio ASIO (desenvolvido com Focusrite USB ASIO)
- Python 3.11
- Uma build do `sounddevice` com suporte a ASIO (veja abaixo)

## Instalação

```powershell
python -m venv venv311
.\venv311\Scripts\Activate.ps1
pip install -r requirements.txt
```

**Atenção:**

- O `requirements.txt` está codificado em UTF-16 (gerado por `pip freeze >` no PowerShell). O pip lê o arquivo normalmente, mas algumas ferramentas mostram o conteúdo com espaços entre os caracteres. Para gerar um arquivo em UTF-8: `pip freeze | Out-File -Encoding utf8 requirements.txt`.
- A linha do `sounddevice` aponta para um wheel local (`C:/Users/User/Downloads/sounddevice-0.4.3-py3-none-win_amd64.whl`), uma build com ASIO habilitado. Em outra máquina, remova essa linha e instale o wheel manualmente, ou use `pip install sounddevice` (a versão do PyPI pode não incluir ASIO).

## Uso

### 1. Encontrar o índice do dispositivo

Os índices de dispositivo estão fixos no código e mudam de máquina para máquina (e às vezes quando a interface é reconectada). Para listar os dispositivos:

```powershell
python -m sounddevice
```

Procure a entrada com `ASIO` no nome e atualize a constante `ASIO_DEVICE` no script que for executar.

### 2. Passthrough (teste de latência)

```powershell
python src/passthrough.py
```

Copia a entrada para a saída por 10 segundos, com 48 kHz e buffer de 128 amostras (~2,7 ms). Serve para validar o driver e a latência base antes de qualquer processamento. O tamanho de buffer precisa ser compatível com o configurado no painel da interface (Focusrite Control).

### 3. Phase vocoder em tempo real

```powershell
python src/phase_vocoder_real_time.py
```

Roda por 30 segundos. Parâmetros no topo do arquivo:

| Constante | Padrão | Descrição |
|---|---|---|
| `SAMPLE_RATE` | 96000 | Taxa de amostragem (Hz) |
| `BUFFER_SIZE` | 256 | Tamanho do bloco ASIO |
| `ASIO_DEVICE` | 17 | Índice do dispositivo |
| `SEMITONES` | −5 | Transposição; negativo = para baixo |
| `FFT_SIZE` | 4096 | Janela de análise (~43 ms a 96 kHz) |
| `HOP_SIZE` | `FFT_SIZE // 4` | Hop de síntese (75% de overlap) |

O algoritmo estima a frequência instantânea de cada bin pela diferença de fase entre frames, remapeia os bins pela razão `2^(semitons/12)` e reconstrói por overlap-add com janela de Hann. A janela de 4096 amostras dá boa resolução para notas graves, mas é a principal fonte de latência.

### 4. Notebook de exploração

```powershell
jupyter lab notebooks/01_exploracao.ipynb
```

Usa `librosa.effects.pitch_shift` como referência offline: gera os arquivos de `audio_samples_shifted/` e compara a f0 estimada (pYIN) do Lá transposto com a do Mi natural.
