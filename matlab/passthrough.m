%% passthrough.m
% Teste de entrada/saída em tempo real com o Audio Toolbox.
% Lê blocos da interface de áudio e devolve o mesmo sinal na saída,
% medindo overruns, underruns e o tempo gasto em cada iteração.
% O bloco de 256 amostras é o mesmo hop que o pitch shifter vai usar.

clear; close all;

%% Parâmetros
fs       = 44100;   % taxa de amostragem (tem que bater com a do driver)
hop      = 64;      % amostras por bloco. No ASIO o MATLAB impõe este valor
                    % como buffer da interface (ignora o Focusrite Control).
                    % Teste 64, 128 e 256 e compare a latência.
duracao  = 30;      % segundos de teste
ganho    = 1.0;     % ganho de saída

%% Dispositivos
% No Windows use ASIO (driver da Focusrite). O driver tem que ser passado
% na criação do objeto; com o padrão (DirectSound) a latência fica enorme.
if ispc
    driver = {'Driver', 'ASIO'};
else
    driver = {};
end

leitor = audioDeviceReader(driver{:}, ...
                           'SampleRate', fs, ...
                           'SamplesPerFrame', hop, ...
                           'NumChannels', 1);
escritor = audioDeviceWriter(driver{:}, 'SampleRate', fs);

disp('Dispositivos de entrada:');  disp(getAudioDevices(leitor)');
disp('Dispositivos de saída:');    disp(getAudioDevices(escritor)');

% No ASIO a entrada e a saída usam o MESMO dispositivo:
% leitor.Device   = 'Focusrite USB ASIO';
% escritor.Device = 'Focusrite USB ASIO';

if ispc
    fprintf('Driver: %s | ', leitor.Driver);
end
fprintf('Entrada: %s | Saída: %s\n', leitor.Device, escritor.Device);

%% Preparação (aloca tudo antes do laço)
setup(leitor);
setup(escritor, zeros(hop, 2));

nBlocos     = ceil(duracao * fs / hop);
tProc       = zeros(nBlocos, 1);
totOverrun  = 0;
totUnderrun = 0;
picoEntrada = 0;
orcamento   = hop / fs;   % tempo máximo por bloco

fprintf('Rodando por %d s. Toque a guitarra...\n', duracao);

%% Laço de tempo real
for n = 1:nBlocos
    [x, nOverrun] = leitor();

    t0 = tic;
    y  = ganho * x;               % <- aqui entra o pitch shifter depois
    tProc(n) = toc(t0);

    nUnderrun = escritor([y y]);  % mesmo sinal nos dois canais

    totOverrun  = totOverrun  + nOverrun;
    totUnderrun = totUnderrun + nUnderrun;
    picoEntrada = max(picoEntrada, max(abs(x)));
end

%% Libera os dispositivos
release(leitor);
release(escritor);

%% Relatório
fprintf('\n--- Resultado ---\n');
fprintf('Amostras perdidas na entrada (overrun):  %d\n', totOverrun);
fprintf('Amostras faltando na saída (underrun):   %d\n', totUnderrun);
fprintf('Pico de entrada: %.3f (perto de 1.0 = clipando)\n', picoEntrada);
fprintf('Processamento por bloco: médio %.3f ms, máximo %.3f ms\n', ...
        1e3 * mean(tProc), 1e3 * max(tProc));
fprintf('Orçamento por bloco: %.2f ms\n', 1e3 * orcamento);
