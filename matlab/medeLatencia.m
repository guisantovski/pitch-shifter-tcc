%% medeLatencia.m
% Mede a latência de ponta a ponta com um cabo de loopback.
%
% Ligação: cabo P10 da saída Output 1 (ou 2) da Scarlett para a entrada
% Input 2, com o botão INST DESLIGADO (nível de linha) e o ganho do
% Input 2 no mínimo. Deixe o knob de monitor num volume médio e desligue o
% direct monitor. Tire os fones/monitores do ouvido: os cliques são altos.
%
% O script roda duas medidas seguidas:
%   'io' - os cliques vão direto para a saída: latência de I/O
%          (conversores + USB + driver + buffers do MATLAB)
%   'pv' - os cliques passam pelo pvProcessBlock antes de sair: I/O +
%          algoritmo, que é o que o guitarrista sente ao tocar
% A ordem das etapas não muda a soma dos atrasos, então gerar o clique
% dentro do MATLAB mede o mesmo que entrar com a guitarra.

clear; close all;

%% Parâmetros
fs        = 44100;
B         = 64;          % buffer ASIO (64 ou 128)
N         = 1024;        % quadro do phase vocoder
Ha        = 256;         % hop de análise
semitons  = 0;           % 0 deixa o clique reconhecível na saída
duracao   = 6;           % segundos por medida
periodo   = round(0.5 * fs);   % um clique a cada 0,5 s
amplitude = 0.5;

%% Dispositivos (2 canais de entrada: o loopback chega no Input 2)
if ispc
    driver = {'Driver', 'ASIO'};
else
    driver = {};
end
leitor   = audioDeviceReader(driver{:}, 'SampleRate', fs, ...
                             'SamplesPerFrame', B, 'NumChannels', 2);
escritor = audioDeviceWriter(driver{:}, 'SampleRate', fs);
leitor.Device   = 'Focusrite USB ASIO';
escritor.Device = 'Focusrite USB ASIO';
setup(leitor);
setup(escritor, zeros(B, 2));

nBlocos = ceil(duracao * fs / B);
modos   = {'io', 'pv'};
res     = zeros(1, numel(modos));

for m = 1:numel(modos)
    modo = modos{m};
    st   = pvInit(N, Ha, B, semitons, false);
    ref  = zeros(nBlocos*B, 1);
    rec  = zeros(nBlocos*B, 1);
    totUnderrun = 0;

    for n = 1:nBlocos
        idx = (n-1)*B + (1:B);

        % Trem de cliques (impulsos de uma amostra)
        clique = zeros(B, 1);
        clique(mod(idx - 1, periodo) == 0) = amplitude;
        ref(idx) = clique;

        if strcmp(modo, 'pv')
            [y, st] = pvProcessBlock(clique, st);
        else
            y = clique;
        end

        x = leitor();
        rec(idx) = x(:, 2);
        nUnderrun = escritor([y y]);
        if idx(1) > fs                      % ignora a partida, como na medida
            totUnderrun = totUnderrun + nUnderrun;
        end
    end

    % Descarta o primeiro segundo (partida do driver)
    ini = fs + 1;
    [atraso, conf] = medeAtraso(ref(ini:end), rec(ini:end), periodo);
    res(m) = atraso;
    fprintf('Modo %-2s: %5d amostras = %5.1f ms  (confiança %.1f, underruns %d, pico gravado %.2f)\n', ...
            modo, atraso, 1e3*atraso/fs, conf, totUnderrun, max(abs(rec(ini:end))));
    if conf < 2 || max(abs(rec(ini:end))) < 0.01
        warning(['Medida pouco confiável: confira o cabo, o Input 2 em modo ' ...
                 'linha e o volume de saída.']);
    end
end

release(leitor);
release(escritor);

%% Resumo
fprintf('\n--- Latência (B = %d, N = %d, Ha = %d) ---\n', B, N, Ha);
fprintf('I/O (ida e volta pela interface): %5.1f ms\n', 1e3*res(1)/fs);
fprintf('Algoritmo (pv - io):              %5.1f ms  (teórico N - B = %.1f ms)\n', ...
        1e3*(res(2)-res(1))/fs, 1e3*(N-B)/fs);
fprintf('Total (o que o guitarrista sente): %5.1f ms\n', 1e3*res(2)/fs);
