%% preparaTesteEscuta.m
% Prepara os arquivos de um teste de escuta cego (MUSHRA ou ABX) com
% terceiros: corta o mesmo trecho de cada condição, iguala a intensidade
% (RMS), dá nomes aleatórios e grava o gabarito à parte.
%
% Use as saídas que o rodaBenchmark grava em resultados/audio/ (e os
% renders externos). Para cada trecho do teste, liste a referência (a nota
% tocada de verdade na altura de destino) e as condições.
%
% Saída em benchmark/escuta/<trecho>/: <código>.wav e, em benchmark/escuta/,
% gabarito.csv (código -> condição). Não mande o gabarito aos ouvintes.

clear;
aqui = fileparts(mfilename('fullpath'));
res  = fullfile(aqui, 'resultados', 'audio');
amos = fullfile(aqui, '..', '..', 'audio_samples');
ext  = fullfile(aqui, 'externos');

%% Trechos: nome, referência, {condições}
trechos = {
    'La_para_Mi', fullfile(amos, 'E_natural.wav'), { ...
        fullfile(res, 'A_natural_-5st_PV_N1024_Ha256.wav'), ...
        fullfile(res, 'A_natural_-5st_PV_N1024_Ha128.wav'), ...
        fullfile(ext, 'A_natural_-5st_neural.wav')}
    'Mi_para_La', fullfile(amos, 'A_natural.wav'), { ...
        fullfile(res, 'E_natural_+5st_PV_N1024_Ha256.wav'), ...
        fullfile(ext, 'E_natural_+5st_neural.wav')}
};
inicio  = 0.5;     % s
duracao = 6;       % s (MUSHRA recomenda trechos curtos, até ~10 s)
rmsAlvo = -23;     % dBFS
fade    = 0.02;    % s

%% Gerar
saida = fullfile(aqui, 'escuta');
if ~exist(saida, 'dir'), mkdir(saida); end
fid = fopen(fullfile(saida, 'gabarito.csv'), 'w');
fprintf(fid, 'trecho,codigo,condicao,arquivo\n');
rng('shuffle');
for t = 1:size(trechos, 1)
    pasta = fullfile(saida, trechos{t, 1});
    if ~exist(pasta, 'dir'), mkdir(pasta); end
    arqs = [trechos(t, 2), trechos{t, 3}];
    conds = [{'referencia'}, cell(1, numel(trechos{t, 3}))];
    for k = 2:numel(arqs)
        [~, nm] = fileparts(arqs{k}); conds{k} = nm;
    end
    % A referência entra duas vezes: aberta (REF) e escondida entre as
    % condições, como pede o MUSHRA (ITU-R BS.1534-3)
    arqs  = [arqs, arqs(1)];
    conds = [conds, {'referencia_escondida'}];
    codigos = randperm(900, numel(arqs)) + 99;
    for k = 1:numel(arqs)
        if ~exist(arqs{k}, 'file')
            fprintf('Pulando (não existe): %s\n', arqs{k}); continue;
        end
        [y, fs] = audioread(arqs{k});
        y = mean(y, 2);
        i0 = round(inicio*fs) + 1; i1 = min(numel(y), i0 + round(duracao*fs) - 1);
        y = y(i0:i1);
        nf = round(fade*fs); r = (0:nf-1)'/nf;
        y(1:nf) = y(1:nf) .* r; y(end-nf+1:end) = y(end-nf+1:end) .* flipud(r);
        y = y * 10^(rmsAlvo/20) / max(sqrt(mean(y.^2)), eps);
        if max(abs(y)) > 0.99, y = y * 0.99 / max(abs(y)); end
        if k == 1
            cod = 'REF';
        else
            cod = sprintf('%03d', codigos(k));
        end
        audiowrite(fullfile(pasta, [cod '.wav']), y, fs, 'BitsPerSample', 24);
        fprintf(fid, '%s,%s,%s,%s\n', trechos{t, 1}, cod, conds{k}, arqs{k});
    end
end
fclose(fid);
fprintf('Arquivos em %s (gabarito.csv fica com você)\n', saida);
