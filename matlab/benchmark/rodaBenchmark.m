%% rodaBenchmark.m
% Benchmark objetivo de afinação e qualidade do pitch shift.
%
% Roda offline (não precisa da interface) e compara, com as mesmas
% métricas e os mesmos sinais secos:
%   - os nossos algoritmos (lista "algs" abaixo; o Ocean entra aqui);
%   - renderizações externas (ex.: transposer da Neural DSP) colocadas em
%     benchmark/externos/ com o nome <seco>_<+s>st_<tag>.wav;
%   - gravações ao vivo feitas com o gravaBenchmark.m (benchmark/gravacoes/).
%
% Partes:
%   1. Grade de notas sintéticas (Mi2..Mi5, f0 exata) x semitons: erro de
%      afinação em cents, erro grosseiro, razão tonal/ruído e ataque.
%   2. Gravações reais (amostras do repositório + gravações ao vivo):
%      todas as métricas do metricasPitchShift, distância de timbre para a
%      nota tocada de verdade e, se o Audio Toolbox tiver visqol, o ViSQOL
%      do teste de ida e volta (+s seguido de -s).
% Resultados: tabelas no console e CSVs/figuras em benchmark/resultados/.
% Detalhes das métricas e do protocolo: benchmark/README.md.

clear; close all;
aqui = fileparts(mfilename('fullpath'));
raiz = fullfile(aqui, '..', '..');
addpath(fullfile(aqui, '..'));
addpath(aqui);

%% Configuração
fs = 44100;
B  = 64;                       % bloco de I/O usado no tempo real

% Algoritmos internos: nome (sem espaços) e função @(x, semitons)
algs = struct('nome', {}, 'proc', {});
algs(end+1) = struct('nome', 'PV_N1024_Ha256', ...
    'proc', @(x, s) pvProcessaSinal(x, pvInit(1024, 256, B, s, false)));
algs(end+1) = struct('nome', 'PV_N1024_Ha128', ...
    'proc', @(x, s) pvProcessaSinal(x, pvInit(1024, 128, B, s, false)));
% Descomente para incluir as variantes já descartadas como referência:
% algs(end+1) = struct('nome', 'PV_phaseLock', ...
%     'proc', @(x, s) pvProcessaSinal(x, pvInit(1024, 256, B, s, true)));
% algs(end+1) = struct('nome', 'PV_N512_Ha128', ...
%     'proc', @(x, s) pvProcessaSinal(x, pvInit(512, 128, B, s, false)));
% Quando o Ocean existir:
% algs(end+1) = struct('nome', 'Ocean', 'proc', @(x, s) ...);

semitonsGrade = [-12 -7 -5 -2 -1 1 2 5 7 12];

% Amostras do repositório: seco, semitons, referência natural na altura
% de destino ('' se não houver), tipo ('mono' = nota isolada, vale a
% métrica de afinação por YIN; 'poli' = acordes, vale a transposição
% espectral)
casos = {
    'A_natural',            -5, 'E_natural',            'mono'
    'A_natural_bleed',      -5, 'E_natural_bleed',      'mono'
    'A_natural_pedal_open', -5, 'E_natural_pedal_open', 'mono'
    'A_natural_pedal_pm',   -5, 'E_natural_pedal_pm',   'mono'
    'E_natural',             5, 'A_natural',            'mono'
    'E_natural_bleed',       5, 'A_natural_bleed',      'mono'
    'strumming_chords',     -5, '',                     'poli'
    'strumming_chords',      5, '',                     'poli'
};

fazerIdaVolta = true;          % ViSQOL de ida e volta (precisa de visqol)
salvarSaidas  = true;          % grava as saídas em resultados/audio/ para ouvir
pastaAmostras = fullfile(raiz, 'audio_samples');
pastaExt   = fullfile(aqui, 'externos');
pastaGrav  = fullfile(aqui, 'gravacoes');
pastaSin   = fullfile(aqui, 'sinais');
pastaRes   = fullfile(aqui, 'resultados');
for p = {pastaSin, pastaRes}
    if ~exist(p{1}, 'dir'), mkdir(p{1}); end
end
carimbo = datestr(now, 'yyyy-mm-dd_HHMM');

%% Sinal sintético (salvo para poder ser renderizado por plugins externos)
[xNotas, seg] = geraNotasTeste(fs);
arqNotas = fullfile(pastaSin, 'teste_notas.wav');
if ~exist(arqNotas, 'file')
    audiowrite(arqNotas, xNotas, fs, 'BitsPerSample', 24);
end

%% Latência de cada algoritmo interno (trem de cliques), por semitom
todosS = unique([semitonsGrade, cell2mat(casos(:, 2))', -cell2mat(casos(:, 2))']);
lat = nan(numel(algs), numel(todosS));
for a = 1:numel(algs)
    for k = 1:numel(todosS)
        lat(a, k) = latenciaAlgoritmo(algs(a).proc, fs, todosS(k));
    end
end
latDe = @(a, s) lat(a, todosS == s);

latExt = containers.Map();     % atraso dos externos, estimado nas notas

%% ===== Parte 1: grade de notas sintéticas =====
fprintf('\n===== Parte 1: notas sintéticas (Mi2..Mi5) =====\n');
% Linhas da tabela: algoritmos internos e externos que renderizaram
% teste_notas em algum semitom
fontes = struct('nome', {}, 'proc', {}, 'ext', {});
for a = 1:numel(algs)
    fontes(end+1) = struct('nome', algs(a).nome, 'proc', algs(a).proc, 'ext', []); %#ok<SAGROW>
end
ext = procuraExternos(pastaExt, 'teste_notas');
tags = unique({ext.tag});
for t = 1:numel(tags)
    fontes(end+1) = struct('nome', tags{t}, 'proc', [], 'ext', ext(strcmp({ext.tag}, tags{t}))); %#ok<SAGROW>
end

nS = numel(semitonsGrade); nNt = numel(seg);
rotS = arrayfun(@(s) sprintf('%+d', s), semitonsGrade, 'UniformOutput', false);
pre = round(0.1 * fs);         % 100 ms de silêncio antes da nota (ataque)
G.erro = nan(numel(fontes), nS, nNt);    % mediana do erro (cents)
G.p95  = G.erro; G.gpe = G.erro; G.tnr = G.erro; G.atq = G.erro;
arqCsv = fullfile(pastaRes, ['notas_' carimbo '.csv']);
fid = fopen(arqCsv, 'w');
fprintf(fid, 'algoritmo,semitons,nota,f0_Hz,erro_mediano_cents,erro_abs_p95_cents,dentro_5c,dentro_10c,gpe,d_tonal_ruido_dB,d_ataque_ms,ganho_dB\n');
for a = 1:numel(fontes)
    for j = 1:nS
        s = semitonsGrade(j);
        if isempty(fontes(a).ext)
            y = fontes(a).proc(xNotas, s);
            atr = latDe(a, s);
        else
            e = fontes(a).ext([fontes(a).ext.s] == s);
            if isempty(e), continue; end
            y = mean(audioread(e(1).arq), 2);
            atr = estimaAtraso(xNotas, y, fs);
            latExt(sprintf('%s|%d', fontes(a).nome, s)) = atr;
        end
        y(end+1 : numel(xNotas) + atr + 1) = 0;
        for k = 1:nNt
            i0 = seg(k).ini - pre; i1 = seg(k).fim;
            if i0 + atr < 1, continue; end
            m = metricasPitchShift(xNotas(i0:i1), y(i0+atr : i1+atr), fs, s, ...
                                   struct('atraso', 0));
            G.erro(a, j, k) = m.erroMedCents; G.p95(a, j, k) = m.erroAbsP95;
            G.gpe(a, j, k)  = m.gpe;          G.tnr(a, j, k) = m.dTonalRuidoDb;
            G.atq(a, j, k)  = m.dAtaqueMs;
            fprintf(fid, '%s,%d,%s,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%.2f,%.1f,%.2f\n', ...
                    fontes(a).nome, s, seg(k).nome, seg(k).f0, m.erroMedCents, ...
                    m.erroAbsP95, m.dentro5, m.dentro10, m.gpe, m.dTonalRuidoDb, ...
                    m.dAtaqueMs, m.ganhoDb);
        end
    end
end
fclose(fid);

for a = 1:numel(fontes)
    fprintf('\n%s: erro mediano de afinação (cents) [GPE > 0 marcado com *]\n', fontes(a).nome);
    fprintf('%6s', 'nota'); fprintf('%7s ', rotS{:}); fprintf('\n');
    for k = 1:nNt
        fprintf('%6s', seg(k).nome);
        for j = 1:nS
            v = G.erro(a, j, k); g = G.gpe(a, j, k);
            marca = ' '; if g > 0, marca = '*'; end
            fprintf('%7.1f%s', v, marca);
        end
        fprintf('\n');
    end
    fprintf('  média |erro| %.2f cents | pior p95 %.1f cents | GPE médio %.1f%% | d tonal/ruído médio %.1f dB | d ataque médio %.1f ms\n', ...
            mean(abs(G.erro(a, :)), 'omitnan'), max(G.p95(a, :)), 100*mean(G.gpe(a, :), 'omitnan'), ...
            mean(G.tnr(a, :), 'omitnan'), mean(G.atq(a, :), 'omitnan'));
end
fprintf('\nCSV: %s\n', arqCsv);

%% ===== Parte 2: gravações reais =====
fprintf('\n===== Parte 2: gravações reais =====\n');
% Junta as gravações ao vivo (gravaBenchmark) aos casos do repositório
lista = struct('seco', {}, 'arqSeco', {}, 's', {}, 'ref', {}, 'tipo', {}, 'rt', {});
for c = 1:size(casos, 1)
    arqRef = '';
    if ~isempty(casos{c, 3}), arqRef = fullfile(pastaAmostras, [casos{c, 3} '.wav']); end
    lista(end+1) = struct('seco', casos{c, 1}, 'arqSeco', fullfile(pastaAmostras, [casos{c, 1} '.wav']), ...
                          's', casos{c, 2}, 'ref', arqRef, 'tipo', casos{c, 4}, 'rt', ''); %#ok<SAGROW>
end
if exist(pastaGrav, 'dir')
    d = dir(fullfile(pastaGrav, '*_seco.wav'));
    for k = 1:numel(d)
        nome = d(k).name(1:end-9);
        r = dir(fullfile(pastaGrav, [nome '_*st_rt.wav']));
        for q = 1:numel(r)
            t = regexp(r(q).name, '_([+-]?\d+)st_rt\.wav$', 'tokens', 'once');
            if isempty(t), continue; end
            lista(end+1) = struct('seco', nome, 'arqSeco', fullfile(pastaGrav, d(k).name), ...
                                  's', str2double(t{1}), 'ref', '', 'tipo', '-', ...
                                  'rt', fullfile(pastaGrav, r(q).name)); %#ok<SAGROW>
        end
    end
end

arqCsv2 = fullfile(pastaRes, ['gravacoes_' carimbo '.csv']);
fid = fopen(arqCsv2, 'w');
fprintf(fid, ['sinal,tipo,semitons,algoritmo,erro_mediano_cents,erro_abs_p95_cents,dentro_5c,dentro_10c,gpe,' ...
              'transp_erro_cents,sim_espectral,coloracao_dB,dist_timbre_natural_dB,d_tonal_ruido_dB,' ...
              'd_flutuacao_dB,d_ataque_ms,ganho_dB,atraso_ms,visqol_ida_volta\n']);
cab = sprintf('%-22s %-5s %4s %-16s %6s %6s %5s %6s %5s %5s %6s %6s %6s %6s %6s %5s\n', 'sinal', 'tipo', 'st', 'algoritmo', ...
              'erro', 'p95', 'GPE', 'transp', 'sim', 'color', 'timbre', 'dTNR', 'dFlut', 'dAtaq', 'ganho', 'ViSQ');
fprintf('%s', cab);
hist = struct('rotulo', {}, 'err', {});
avisouVisqol = false;
for c = 1:numel(lista)
    if ~exist(lista(c).arqSeco, 'file'), continue; end
    [x, fsArq] = audioread(lista(c).arqSeco);
    x = mean(x, 2);
    if fsArq ~= fs, error('rodaBenchmark: %s tem fs = %d (esperado %d).', lista(c).arqSeco, fsArq, fs); end
    s = lista(c).s;
    ref = [];
    if ~isempty(lista(c).ref) && exist(lista(c).ref, 'file'), ref = audioread(lista(c).ref); end

    % Saídas a comparar: internos, gravação ao vivo, externos
    saidas = struct('nome', {}, 'y', {}, 'atraso', {}, 'volta', {});
    for a = 1:numel(algs)
        y = algs(a).proc(x, s);
        volta = [];
        if fazerIdaVolta, volta = algs(a).proc(y, -s); end
        saidas(end+1) = struct('nome', algs(a).nome, 'y', y, 'atraso', latDe(a, s), 'volta', volta); %#ok<SAGROW>
    end
    if ~isempty(lista(c).rt)
        yrt = mean(audioread(lista(c).rt), 2);
        atr = estimaAtraso(x, yrt, fs);
        arqMat = strrep(lista(c).rt, '.wav', '.mat');
        if exist(arqMat, 'file')
            % Reprocessa o seco offline com os mesmos parâmetros e compara:
            % a diferença deve ser só o atraso de I/O (e o ganho do
            % loopback). Resíduo alto = falhas no tempo real.
            inf = load(arqMat);
            procRT = @(v, s) pvProcessaSinal(v, pvInit(inf.N, inf.Ha, inf.B, s, inf.phaseLock));
            yOff = procRT(x, s);
            [d, res] = comparaRT(yOff, yrt, fs);
            atr = latenciaAlgoritmo(procRT, fs, s) + d;
            fprintf('(%s: ao vivo = offline atrasado %.1f ms, resíduo %.1f dB, underruns %d)\n', ...
                    lista(c).seco, 1e3*d/fs, res, inf.underruns);
        end
        saidas(end+1) = struct('nome', 'ao_vivo', 'y', yrt, 'atraso', atr, 'volta', []); %#ok<SAGROW>
    end
    ext = procuraExternos(pastaExt, lista(c).seco);
    ext = ext([ext.s] == s);
    for e = 1:numel(ext)
        y = mean(audioread(ext(e).arq), 2);
        chave = sprintf('%s|%d', ext(e).tag, s);
        if isKey(latExt, chave), atr = latExt(chave); else, atr = estimaAtraso(x, y, fs); end
        volta = [];
        if ~isempty(ext(e).arqVolta), volta = mean(audioread(ext(e).arqVolta), 2); end
        saidas(end+1) = struct('nome', ext(e).tag, 'y', y, 'atraso', atr, 'volta', volta); %#ok<SAGROW>
    end

    for q = 1:numel(saidas)
        if salvarSaidas
            pa = fullfile(pastaRes, 'audio');
            if ~exist(pa, 'dir'), mkdir(pa); end
            yq = saidas(q).y / max(max(abs(saidas(q).y)) / 0.99, eps);
            audiowrite(fullfile(pa, sprintf('%s_%+dst_%s.wav', lista(c).seco, s, saidas(q).nome)), yq, fs);
        end
        m = metricasPitchShift(x, saidas(q).y, fs, s, struct('atraso', saidas(q).atraso));
        tim = NaN;
        if ~isempty(ref), tim = distanciaTimbre(saidas(q).y, ref, fs); end
        vq = NaN;
        if ~isempty(saidas(q).volta)
            vq = idaVolta(x, saidas(q).volta, fs);
            if isnan(vq) && ~avisouVisqol
                fprintf('(visqol indisponível: coluna ViSQ fica NaN)\n'); avisouVisqol = true;
            end
        end
        fprintf('%-22s %-5s %+4d %-16s %6.1f %6.1f %5.2f %6.1f %5.2f %5.1f %6.1f %6.1f %6.1f %6.1f %6.1f %5.2f\n', ...
                lista(c).seco, lista(c).tipo, s, saidas(q).nome, m.erroMedCents, m.erroAbsP95, m.gpe, ...
                m.erroTranspCents, m.simEspectral, m.coloracaoDb, tim, m.dTonalRuidoDb, ...
                m.dFlutuacaoDb, m.dAtaqueMs, m.ganhoDb, vq);
        fprintf(fid, '%s,%s,%d,%s,%.2f,%.2f,%.3f,%.3f,%.3f,%.2f,%.3f,%.2f,%.2f,%.2f,%.2f,%.1f,%.2f,%.1f,%.3f\n', ...
                lista(c).seco, lista(c).tipo, s, saidas(q).nome, m.erroMedCents, m.erroAbsP95, ...
                m.dentro5, m.dentro10, m.gpe, m.erroTranspCents, m.simEspectral, m.coloracaoDb, tim, ...
                m.dTonalRuidoDb, m.dFlutuacaoDb, m.dAtaqueMs, m.ganhoDb, m.atrasoMs, vq);
        if strcmp(lista(c).tipo, 'mono') || strcmp(lista(c).tipo, '-')
            hist(end+1) = struct('rotulo', sprintf('%s %+d %s', lista(c).seco, s, saidas(q).nome), ...
                                 'err', m.errosCents); %#ok<SAGROW>
        end
    end
    if ~isempty(ref)
        fprintf('%-22s %-5s %4s %-16s %62.1f   (sem transposição: seco contra a referência)\n', ...
                lista(c).seco, '', '', 'seco_vs_natural', distanciaTimbre(x, ref, fs));
    end
end
fclose(fid);
fprintf('\nCSV: %s\n', arqCsv2);

%% Figuras (só no MATLAB)
if ~exist('OCTAVE_VERSION', 'builtin')
    for a = 1:numel(fontes)
        f = figure('Name', fontes(a).nome);
        imagesc(squeeze(G.erro(a, :, :))'); colormap(f, parula);
        cb = colorbar; ylabel(cb, 'erro mediano (cents)');
        set(gca, 'XTick', 1:nS, 'XTickLabel', rotS, ...
                 'YTick', 1:nNt, 'YTickLabel', {seg.nome});
        xlabel('semitons'); ylabel('nota de entrada');
        title(strrep(fontes(a).nome, '_', ' '));
        exportgraphics(f, fullfile(pastaRes, ['grade_' fontes(a).nome '_' carimbo '.png']));
    end
    if ~isempty(hist)
        f = figure('Name', 'Erros de afinação');
        hold on;
        for h = 1:numel(hist)
            e = hist(h).err; e = e(abs(e) <= 50);
            if numel(e) > 10, histogram(e, -50:1:50, 'DisplayStyle', 'stairs', 'Normalization', 'probability'); end
        end
        legend(strrep({hist.rotulo}, '_', ' '), 'Location', 'eastoutside');
        xlabel('erro de afinação (cents)'); ylabel('fração dos quadros');
        exportgraphics(f, fullfile(pastaRes, ['histograma_' carimbo '.png']));
    end
end
