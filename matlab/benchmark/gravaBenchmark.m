%% gravaBenchmark.m
% Grava, ao vivo, a guitarra seca e a saída do pitch shifter em tempo
% real, por um tempo fixo, para o rodaBenchmark.m analisar depois.
%
% Ligação na Scarlett 4i4:
%   - guitarra no Input 1, com INST ligado;
%   - (opcional, loopback = true) cabo P10 da Output 1 para o Input 2,
%     com INST desligado e ganho no mínimo, como no medeLatencia.m. Assim
%     a saída é gravada como ela realmente sai da interface (com a latência
%     de I/O e qualquer falha de underrun). Com loopback = false grava-se
%     a saída digital que o MATLAB mandou para a interface;
%   - DIRECT MONITOR DESLIGADO: senão o sinal seco vai para a Output 1 e
%     contamina o loopback (e você ouve o seco junto com o transposto).
%
% Saída em benchmark/gravacoes/:
%   <nome>_seco.wav            Input 1 (guitarra seca)
%   <nome>_<+s>st_rt.wav       saída em tempo real (loopback ou digital)
%   <nome>_<+s>st_rt.mat       parâmetros, underruns e overruns
% O seco serve também para renderizar os plugins externos (README).
%
% Dica: grave um arquivo só com notas isoladas (uma por vez, deixando
% soar) e outro com acordes/riffs. As métricas de afinação por YIN só
% valem para notas isoladas; para acordes vale a transposição espectral.

clear; close all;
aqui = fileparts(mfilename('fullpath'));
addpath(fullfile(aqui, '..'));

%% Parâmetros
nome      = 'notas_isoladas';  % sem espaços; vira o prefixo dos arquivos
semitons  = -5;
duracao   = 30;      % segundos
fs        = 44100;
B         = 64;
N         = 1024;
Ha        = 256;
phaseLock = false;
loopback  = true;    % true = grava a saída pelo cabo Output 1 -> Input 2

%% Dispositivos
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

st = pvInit(N, Ha, B, semitons, phaseLock);
nBlocos = ceil(duracao * fs / B);
seco = zeros(nBlocos*B, 1);
saiD = zeros(nBlocos*B, 1);       % saída digital
saiL = zeros(nBlocos*B, 1);       % saída pelo loopback
totOverrun = 0; totUnderrun = 0;

for k = 3:-1:1
    fprintf('Começa em %d...\n', k); pause(1);
end
fprintf('GRAVANDO %d s com %+d semitons. Toque!\n', duracao, semitons);

%% Laço de tempo real (igual ao pitchShiftRT, guardando os sinais)
for n = 1:nBlocos
    idx = (n-1)*B + (1:B);
    [x, nOverrun] = leitor();
    [y, st] = pvProcessBlock(x(:, 1), st);
    nUnderrun = escritor([y y]);
    seco(idx) = x(:, 1);
    saiD(idx) = y;
    saiL(idx) = x(:, 2);
    if n*B > fs                  % ignora a partida do driver
        totOverrun  = totOverrun  + nOverrun;
        totUnderrun = totUnderrun + nUnderrun;
    end
end
release(leitor);
release(escritor);
fprintf('Fim. Overruns: %d | Underruns: %d\n', totOverrun, totUnderrun);

%% Salvar
pasta = fullfile(aqui, 'gravacoes');
if ~exist(pasta, 'dir'), mkdir(pasta); end
base = sprintf('%s_%+dst_rt', nome, semitons);
if loopback
    saida = saiL;
    if max(abs(saiL)) < 0.01
        warning(['O loopback está quase mudo (pico %.3f): confira o cabo e o ' ...
                 'Input 2. Salvando a saída digital no lugar.'], max(abs(saiL)));
        saida = saiD; loopback = false;
    end
else
    saida = saiD;
end
if max(abs(seco)) >= 0.99
    warning('A entrada clipou (pico %.2f): baixe o ganho do Input 1 e grave de novo.', max(abs(seco)));
end
audiowrite(fullfile(pasta, [nome '_seco.wav']), seco, fs, 'BitsPerSample', 24);
audiowrite(fullfile(pasta, [base '.wav']), saida, fs, 'BitsPerSample', 24);
info = struct('nome', nome, 'semitons', semitons, 'fs', fs, 'B', B, 'N', N, 'Ha', Ha, ...
              'phaseLock', phaseLock, 'loopback', loopback, 'overruns', totOverrun, ...
              'underruns', totUnderrun, 'data', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
save(fullfile(pasta, [base '.mat']), '-struct', 'info');

% Conferência: o loopback deve ser a saída digital atrasada (latência de
% I/O). Um resíduo alto indica falhas (underrun) ou o direct monitor ligado.
if loopback
    L = numel(saiD);
    c = real(ifft(fft(saiL, 2*L) .* conj(fft(saiD, 2*L))));
    [~, k] = max(c(1:round(0.1*fs)));
    d = k - 1;
    a = saiD(1:L-d); b = saiL(1+d:L);
    g = (a' * b) / max(a' * a, eps);
    res = 10*log10(sum((b - g*a).^2) / max(sum(b.^2), eps));
    fprintf('Loopback: latência de I/O %.1f ms, resíduo %.1f dB (bom: < -30 dB)\n', ...
            1e3*d/fs, res);
end
fprintf('Arquivos em %s\n', pasta);
