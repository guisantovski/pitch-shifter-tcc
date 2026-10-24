%% pitchShiftRT.m
% Pitch shifter em tempo real: phase vocoder do Grondin
% (guitarpitchshifter.com) em streaming, com phase locking opcional.
% Entrada e saída pela Focusrite em ASIO, como no passthrough.m.
%
% Funções usadas: pvInit, pvSetSemitons, pvProcessBlock (nesta pasta).

clear; close all;

%% Parâmetros
fs        = 44100;  % taxa de amostragem (igual à do Focusrite Control)
B         = 64;     % bloco de I/O = buffer ASIO (64 ou 128)
N         = 1024;   % quadro/FFT do phase vocoder
Ha        = 256;    % hop de análise (75% de sobreposição)
semitons  = -5;     % transposição (Lá -> Mi = -5)
phaseLock = true;   % false = algoritmo original do Grondin
duracao   = 60;     % segundos
ganho     = 1.0;    % ganho de saída
usarSlider = false; % true abre uma janela com slider de semitons
                    % (o redesenho pode causar underrun com B = 64)

%% Dispositivos
if ispc
    driver = {'Driver', 'ASIO'};
else
    driver = {};
end
leitor   = audioDeviceReader(driver{:}, 'SampleRate', fs, ...
                             'SamplesPerFrame', B, 'NumChannels', 1);
escritor = audioDeviceWriter(driver{:}, 'SampleRate', fs);
leitor.Device   = 'Focusrite USB ASIO';
escritor.Device = 'Focusrite USB ASIO';

setup(leitor);
setup(escritor, zeros(B, 2));

%% Estado do phase vocoder
st = pvInit(N, Ha, B, semitons, phaseLock);

if usarSlider
    fig = uifigure('Name', 'Pitch shifter', 'Position', [100 100 420 110]);
    rot = uilabel(fig, 'Position', [20 70 380 22], ...
                  'Text', sprintf('Semitons: %d', semitons));
    sld = uislider(fig, 'Position', [20 50 380 3], 'Limits', [-12 12], ...
                   'MajorTicks', -12:2:12, 'Value', semitons);
end

nBlocos     = ceil(duracao * fs / B);
tProc       = zeros(nBlocos, 1);
totOverrun  = 0;
totUnderrun = 0;

fprintf('Rodando por %d s com %+d semitons (phase locking: %d)...\n', ...
        duracao, semitons, phaseLock);

%% Laço de tempo real
for n = 1:nBlocos
    [x, nOverrun] = leitor();

    t0 = tic;
    [y, st] = pvProcessBlock(x, st);
    y = ganho * y;
    tProc(n) = toc(t0);

    nUnderrun = escritor([y y]);

    totOverrun  = totOverrun  + nOverrun;
    totUnderrun = totUnderrun + nUnderrun;

    if usarSlider && mod(n, 64) == 0
        if ~isvalid(fig), break; end
        s = round(sld.Value);
        if s ~= st.semitons
            st = pvSetSemitons(st, s);
            rot.Text = sprintf('Semitons: %d', s);
        end
        drawnow limitrate;
    end
end

release(leitor);
release(escritor);
if usarSlider && isvalid(fig), close(fig); end

%% Relatório
orcamento = B / fs;
fprintf('\n--- Resultado ---\n');
fprintf('Overruns: %d | Underruns: %d\n', totOverrun, totUnderrun);
fprintf('Processamento por bloco: médio %.3f ms, máximo %.3f ms (orçamento %.2f ms)\n', ...
        1e3*mean(tProc(1:n)), 1e3*max(tProc(1:n)), 1e3*orcamento);
fprintf('Blocos acima do orçamento: %d de %d\n', sum(tProc(1:n) > orcamento), n);
fprintf('Latência do algoritmo: ~%.1f ms (mais a latência de I/O da interface)\n', ...
        1e3 * (N - B) / fs);
