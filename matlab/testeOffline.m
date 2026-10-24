%% testeOffline.m
% Valida o pitch shifter em streaming sem a interface de áudio: passa os
% sinais pelo pvProcessBlock em blocos de B amostras, exatamente como o
% laço de tempo real faz, e compara o algoritmo original do Grondin com a
% versão com phase locking. Roda no MATLAB puro (sem Audio Toolbox).

clear; close all;

fs = 44100; N = 1024; Ha = 256; B = 64;

%% 1. Seno de 440 Hz em vários intervalos (teste igual ao do Grondin)
f0 = 440;
x  = 0.5 * sin(2*pi*f0*(0:2*fs-1)'/fs);
fprintf('Seno de %d Hz (ganho = RMS saída / RMS entrada; 1.00 = sem perda)\n', f0);
fprintf(' semitons | esperado (Hz) | medido (Hz) | erro (cents) | ganho original | ganho phase lock\n');
for s = [-12 -5 -4 -1 0 1 4 5 7 12]
    y0   = processaEmBlocos(x, pvInit(N, Ha, B, s, false));
    y1   = processaEmBlocos(x, pvInit(N, Ha, B, s, true));
    seg0 = y0(fs/2+1 : end);                     % ignora o início
    seg1 = y1(fs/2+1 : end);
    f    = estimaFreq(seg1, fs);
    esp  = f0 * 2^(s/12);
    fprintf(' %8d | %13.1f | %11.1f | %12.1f | %14.2f | %16.2f\n', s, esp, f, ...
            1200*log2(f/esp), rmsRel(seg0, x), rmsRel(seg1, x));
end

%% 2. Acorde (Lá maior, 6 harmônicos por nota)
t = (0:2*fs-1)'/fs;
x = zeros(size(t));
for fn = [110 138.59 164.81]
    for h = 1:6
        x = x + 0.1/h * sin(2*pi*fn*h*t + h);
    end
end
fprintf('\nAcorde de Lá maior: ganho de RMS\n');
for s = [-5 5]
    y0 = processaEmBlocos(x, pvInit(N, Ha, B, s, false));
    y1 = processaEmBlocos(x, pvInit(N, Ha, B, s, true));
    fprintf(' %+d semitons: original %.2f | phase lock %.2f\n', s, ...
            rmsRel(y0(fs/2+1:end), x), rmsRel(y1(fs/2+1:end), x));
end

%% 3. Latência do algoritmo com um impulso (semitons = 0)
x = zeros(fs/2, 1); x(5000) = 1;
y = processaEmBlocos(x, pvInit(N, Ha, B, 0));
[~, k] = max(abs(y));
fprintf('\nLatência do algoritmo (pico do impulso): %d amostras = %.1f ms\n', ...
        k - 5000, 1e3*(k - 5000)/fs);

%% 4. Áudio real do repositório: Lá -> Mi (-5 semitons)
arq = fullfile('..', 'audio_samples', 'A_natural.wav');
if exist(arq, 'file')
    [x, fsArq] = audioread(arq);
    x = mean(x, 2);
    if ~exist('saida', 'dir'), mkdir('saida'); end
    y = processaEmBlocos(x, pvInit(N, Ha, B, -5, false));
    audiowrite(fullfile('saida', 'A_natural_rt_original.wav'), 0.99*y/max(abs(y)), fsArq);
    y = processaEmBlocos(x, pvInit(N, Ha, B, -5, true));
    audiowrite(fullfile('saida', 'A_natural_rt_phaselock.wav'), 0.99*y/max(abs(y)), fsArq);
    fprintf('\nGravados saida/A_natural_rt_original.wav e saida/A_natural_rt_phaselock.wav\n');
    fprintf('(compare com audio_samples/E_natural.wav)\n');
end

%% Funções auxiliares
function y = processaEmBlocos(x, st)
    B  = st.B;
    nB = floor(numel(x) / B);
    y  = zeros(nB*B, 1);
    for n = 1:nB
        idx = (n-1)*B + (1:B);
        [y(idx), st] = pvProcessBlock(x(idx), st);
    end
end

function g = rmsRel(y, x)
    g = sqrt(mean(y.^2) / mean(x.^2));
end

function f = estimaFreq(x, fs)
    % Pico da FFT com zero-padding e interpolação parabólica
    L = numel(x);
    w = 0.5 - 0.5*cos(2*pi*(0:L-1)'/L);
    nfft = 2^nextpow2(8*L);
    X = abs(fft(x .* w, nfft));
    X = X(1:nfft/2);
    [~, k] = max(X);
    a = log(X(k-1)); b = log(X(k)); c = log(X(k+1));
    p = 0.5 * (a - c) / (a - 2*b + c);
    f = (k - 1 + p) * fs / nfft;
end
