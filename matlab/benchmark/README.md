# Benchmark de afinação e qualidade do pitch shift

Validação objetiva do pitch shifter, que não depende só do ouvido do autor, e comparação com produtos comerciais (transposer da Neural DSP) usando **os mesmos sinais secos e as mesmas métricas**. Também serve para comparar as variantes do nosso algoritmo entre si (hop, phase locking e, depois, o Ocean).

## Arquivos

| Arquivo | O que faz |
|---|---|
| `rodaBenchmark.m` | Script principal, offline. Roda todos os algoritmos e renders externos e imprime/salva as métricas |
| `gravaBenchmark.m` | Grava ao vivo, pela Scarlett, a guitarra seca e a saída do pitch shifter em tempo real |
| `preparaTesteEscuta.m` | Gera os arquivos de um teste de escuta cego (mesmo trecho, mesma intensidade, nomes aleatórios, gabarito à parte) |
| `metricasPitchShift.m` | Calcula as métricas de um par (seco, processado) |
| `yinF0.m` | Estimador de f0 YIN (implementação própria, sem toolbox) |
| `geraNotasTeste.m` | Notas sintéticas de Mi2 a Mi5 com f0 exata |
| `distanciaTimbre.m` | Distância de envelope espectral entre o transposto e a nota tocada de verdade |
| `estimaAtraso.m`, `latenciaAlgoritmo.m`, `comparaRT.m` | Alinhamento temporal e conferência tempo real × offline |
| `idaVolta.m` | ViSQOL do teste de ida e volta (+s e depois −s), se o Audio Toolbox tiver `visqol` |
| `procuraExternos.m` | Acha os renders externos pelo nome |
| `../pvProcessaSinal.m` | Passa um sinal inteiro pelo `pvProcessBlock` em blocos de B, igual ao tempo real |

Tudo roda no MATLAB e no GNU Octave (testado no Octave 8.4). As figuras só são geradas no MATLAB.

## Como rodar

1. **Offline, só com as amostras do repositório.** Na pasta `matlab/`, rode `benchmark/rodaBenchmark`. Na primeira vez ele grava `benchmark/sinais/teste_notas.wav` (notas sintéticas). Os resultados vão para `benchmark/resultados/` (`notas_<data>.csv`, `gravacoes_<data>.csv`, figuras e `audio/` com cada saída para ouvir).
2. **Gravação ao vivo.** Ajuste `nome`, `semitons` e `duracao` no topo de `gravaBenchmark.m` e rode. A ligação está descrita no cabeçalho do script (guitarra no Input 1, loopback opcional Output 1 → Input 2, **direct monitor desligado**). Os arquivos vão para `benchmark/gravacoes/` e o `rodaBenchmark` passa a incluí-los automaticamente. Com o `.mat` da gravação, ele também reprocessa o seco offline e confere se o tempo real saiu idêntico (resíduo < −30 dB); um resíduo alto indica falhas de áudio (underrun) ou direct monitor ligado.
3. **Neural DSP (ou qualquer outro pitch shifter).** Veja a seção abaixo.
4. **Teste de escuta.** Edite a lista `trechos` de `preparaTesteEscuta.m` e rode. Ver a seção "Teste de escuta".

Para incluir um algoritmo novo (o Ocean, por exemplo), acrescente uma linha em `algs` no topo do `rodaBenchmark.m` com uma função `@(x, semitons)` que devolva o sinal processado.

## Comparação com a Neural DSP

A comparação só é justa se os dois algoritmos processarem **exatamente o mesmo sinal seco**. Por isso a gravação do transposer não é feita tocando de novo, e sim renderizando o mesmo arquivo:

1. Numa DAW (Reaper, por exemplo), importe o arquivo seco: `benchmark/sinais/teste_notas.wav`, as amostras de `audio_samples/` (`A_natural.wav`, `E_natural.wav`, `strumming_chords.wav`…) e/ou os `*_seco.wav` de `benchmark/gravacoes/`.
2. Insira o plugin da Neural DSP **só com o transposer ativo**: amp, cab, pedais e efeitos desligados, mix 100% transposto, sem dobra (o sinal seco não pode estar misturado). Se não der para desligar o amp, passe também o seco pelo mesmo plugin com transposição 0 e use isso como seco, para que os dois lados tenham a mesma cadeia.
3. Renderize em 44,1 kHz, 24 bits, mono, a partir do início do arquivo e com o mesmo tamanho. A DAW compensa a latência do plugin; mesmo assim o benchmark estima o atraso nas notas sintéticas e reaproveita o valor nos outros arquivos.
4. Salve em `benchmark/externos/` com o nome `<seco>_<+s>st_<tag>.wav`, onde `<tag>` é só letras e números. Exemplos: `teste_notas_-5st_neural.wav`, `A_natural_-5st_neural.wav`, `E_natural_+5st_neural.wav`, `strumming_chords_+5st_neural.wav`.
5. (Opcional, para o ViSQOL) Renderize também a ida e volta: duas instâncias em série, +s e depois −s, salvas como `<seco>_<+s>st_<tag>_idavolta.wav`.

Para a grade completa, renderize `teste_notas.wav` em cada semitom de `semitonsGrade` (−12, −7, −5, −2, −1, +1, +2, +5, +7, +12). Os que faltarem aparecem como NaN.

A latência do plugin não entra nessas métricas. Ela pode ser lida na DAW (o Reaper mostra o PDC de cada plugin) ou medida com o mesmo método do `medeLatencia.m`, rodando o plugin standalone com o cabo de loopback.

## Métricas

Todas comparam a saída com **o seco que a gerou**, depois de alinhar no tempo. A transposição esperada é exatamente `100·s` cents.

### Afinação (notas isoladas)

A f0 da entrada e da saída é estimada quadro a quadro pelo YIN (de Cheveigné e Kawahara, 2002; janela de 46 ms, hop de 5,8 ms, de 38 Hz a 1,5 kHz). O erro de cada quadro é `1200·log2(f0_saída / f0_entrada) − 100·s`. Por comparar com a f0 da própria entrada, a métrica não depende da afinação da guitarra nem do vibrato do guitarrista.

| Métrica | Coluna | Significado | Bom |
|---|---|---|---|
| Erro mediano | `erro` | viés de afinação: quanto a nota sai desafinada | perto de 0 |
| Percentil 95 do erro absoluto | `p95` | estabilidade da altura (oscilação espúria) | pequeno |
| Fração dentro de ±5 e ±10 cents | CSV | 5 cents é a ordem do limiar de percepção de diferença de altura em tons complexos; afinadores de guitarra trabalham em ±1 a ±3 cents | perto de 1 |
| Gross pitch error (GPE) | `GPE` | fração de quadros com erro > 50 cents: oitava errada, subharmônico, som sem altura definida. É a métrica clássica de avaliação de estimadores de f0 | 0 |

Essas métricas valem para notas isoladas (`tipo = mono`). Em acordes o YIN encontra só uma das notas, então para `poli` use a transposição espectral.

### Transposição e timbre (vale para acordes)

| Métrica | Coluna | Significado |
|---|---|---|
| Erro de transposição espectral | `transp` | deslocamento (cents) que melhor alinha o espectro médio da saída ao da entrada, por correlação num eixo de frequência logarítmico com passo de 1 cent, menos `100·s`. É a comparação de espectros que estava na ideia original e funciona com polifonia |
| Similaridade espectral | `sim` | correlação (0 a 1) entre os dois espectros depois do alinhamento. Cai quando a saída tem energia que não é a entrada transposta |
| Coloração | `color` | desvio RMS (dB, bandas de 1/3 de oitava) entre a saída e a entrada transposta idealmente. Mede mudança de timbre além da transposição |
| Distância de timbre para a nota natural | `timbre` | mesmo cálculo, mas contra a gravação da nota tocada de verdade na altura de destino (Lá −5 st contra o Mi natural). Mede verossimilhança. A linha `seco_vs_natural` mostra a distância antes de transpor, para referência |

### Artefatos

| Métrica | Coluna | Significado |
|---|---|---|
| Δ razão tonal/ruído | `dTNR` | variação (saída − entrada) da razão entre a energia nos picos espectrais e a energia entre eles. Negativo = o algoritmo espalhou energia entre os harmônicos (phasiness, ruído de fase) |
| Δ flutuação do envelope | `dFlut` | variação da modulação rápida (4–40 Hz) da amplitude. Positivo = "warble", batimentos, som robótico |
| Δ tempo de ataque | `dAtaq` | variação mediana do tempo de subida (10% → 90%) nos ataques da entrada. Positivo = transiente borrado ("palhetada mole"), típico de phase vocoder |
| Ganho | `ganho` | RMS da saída / RMS da entrada (dB) |
| ViSQOL ida e volta | `ViSQ` | ver abaixo |

## Métricas perceptuais

PEAQ (ITU-R BS.1387) e ViSQOL (Hines et al., 2015; ViSQOL v3, Chinen et al., 2020) são as métricas objetivas de qualidade percebida mais usadas, mas as duas são **intrusivas**: comparam o sinal degradado com uma referência de mesma altura e mesmo alinhamento, que não existe num pitch shift. Duas saídas possíveis:

- **Ida e volta** (implementado, `idaVolta.m`): transpõe +s, depois −s, e compara com o original. A degradação das duas passagens se acumula, então a nota não é absoluta, mas a comparação entre algoritmos é válida. Usa a função `visqol` do Audio Toolbox (R2023a ou mais novo); sem ela a coluna fica NaN. Uma implementação de PEAQ em MATLAB é a `PQevalAudio` (P. Kabal, McGill), que poderia substituir o ViSQOL aqui.
- **Fréchet Audio Distance** (Kilgour et al., 2019): compara a distribuição de embeddings de um conjunto de saídas com a de um conjunto de gravações naturais na altura de destino, sem pareamento. Precisa de Python e de um modelo pré-treinado (VGGish ou CLAP). Não implementado, fica como extensão se a banca pedir.

## Teste de escuta

A validação final deve ser um teste cego com outras pessoas, de preferência guitarristas. Sugestão:

- **Formato MUSHRA** (ITU-R BS.1534-3): para cada trecho, o ouvinte compara as condições com uma referência aberta e dá uma nota de 0 a 100 para "naturalidade / semelhança com a nota tocada de verdade". A referência é a nota natural gravada na altura de destino (`E_natural` para o Lá −5 st). A referência também entra escondida entre as condições, para descartar ouvintes que não a reconhecem (nota < 90 em mais de 15% dos trechos, como manda a norma). Condições: nosso PV, Neural DSP e uma âncora ruim (por exemplo o PV com N = 512).
- **Ferramenta**: webMUSHRA (Schoeffler et al., 2018), gratuita e roda no navegador; os arquivos de `preparaTesteEscuta.m` já saem com intensidade igualada e nomes que não revelam a condição.
- **Tamanho**: 10 a 15 ouvintes é o habitual em trabalhos desse porte. Para dizer se há diferença entre dois algoritmos, use teste de Wilcoxon pareado nas notas.
- **ABX** é uma alternativa mais simples quando a pergunta é só "dá para distinguir o nosso do comercial?".
- **Teste de tocabilidade**: deixar guitarristas tocarem ao vivo com o pedal ligado e responderem se percebem atraso, complementando a medida do `medeLatencia.m`.

## Primeiros resultados (10/11/2026, PV do Grondin, N = 1024, B = 64)

Rodado no Octave com as amostras do repositório.

**Notas sintéticas, erro mediano de afinação (cents):** com Ha = 256 o erro fica entre −4,6 e +3,9 cents de −7 a +7 st em todas as notas, e é exatamente o arredondamento do hop de síntese (−5 st: Hs = 192 em vez de 191,8, ou seja +2,0 cents; a medida deu +1,9 a +2,3). Com Ha = 128 o arredondamento pesa mais: −8,7 cents em −7 st (Hs = 85 em vez de 85,4) e +5,0 em +1 st. Em +12 st com Ha = 256 a saída tem um subharmônico forte (o YIN encontra período 4 vezes maior que o esperado em quase todas as notas, GPE alto); com Ha = 128 isso some a partir de Sol3. Vale ouvir para confirmar.

**Gravações reais:**

| Sinal | st | Algoritmo | erro (c) | p95 (c) | transp (c) | sim | timbre (dB) | dTNR (dB) | dAtaq (ms) | ganho (dB) |
|---|---|---|---|---|---|---|---|---|---|---|
| A_natural | −5 | Ha 256 | 2,1 | 2,6 | 1,9 | 0,91 | 4,6 | −2,3 | 12 | −3,7 |
| A_natural | −5 | Ha 128 | 2,0 | 2,4 | 1,9 | 0,93 | 5,3 | −1,8 | 27 | −3,3 |
| E_natural | +5 | Ha 256 | 7,2 | 15,5 | 1,5 | 0,87 | 5,5 | −9,8 | 35 | −4,2 |
| E_natural | +5 | Ha 128 | 3,9 | 13,3 | 1,5 | 0,85 | 6,3 | −6,4 | 34 | −3,5 |
| strumming_chords | −5 | Ha 256 | (poli) | | 1,5 | 0,97 | | −5,2 | 14 | −3,2 |
| strumming_chords | +5 | Ha 256 | (poli) | | 1,9 | 0,94 | | −8,5 | 6 | −2,9 |

O seco do Lá está a 15,8 dB de distância de timbre do Mi natural; transposto, cai para 4,6 dB.

O que isso diz até aqui:

- A afinação está dentro de ±2 cents nas notas reais, abaixo do limiar de percepção, e o erro que sobra é o arredondamento do Hs.
- O ruído entre harmônicos (dTNR) é o artefato mais claro: piora para cima (+5 st) e em acordes, e o Ha = 128 melhora, o que bate com o que você ouviu ao vivo. As variantes descartadas também são coerentes com o ouvido: o phase locking piora a similaridade espectral em acordes (0,82 contra 0,97) e o N = 512 tem o pior dTNR.
- O PV perde 3 a 4 dB de volume. Isso precisa ser compensado antes de qualquer teste de escuta (o `preparaTesteEscuta.m` já iguala) e talvez no próprio pedal.
- Os ataques ficam 10 a 35 ms mais lentos, o borrão de transiente típico do phase vocoder com N = 1024. É uma métrica para observar quando o Ocean entrar.

## Limitações conhecidas

- **Estado de fase do PV.** O nível e o timbre da saída do PV dependem um pouco das fases acumuladas desde o início do sinal: o mesmo trecho processado depois de uma pré-rolagem diferente pode mudar 1 a 2 dB no ganho. Para comparar algoritmos use sempre os mesmos arquivos secos, como o benchmark faz.
- O atraso usado no alinhamento é estimado pelos ataques (`atraso_ms` no CSV) e é só aproximado. A latência de verdade é medida com o `medeLatencia.m`.
- O YIN pode errar a oitava em notas muito graves ou com pouco fundamental. Como o mesmo estimador é usado na entrada e na saída, isso aparece como GPE e não como erro fino.
