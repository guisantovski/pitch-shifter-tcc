function m = metricasPitchShift(x, y, fs, semitons, opts)
% metricasPitchShift  Métricas objetivas de um pitch shift: compara o
% sinal processado y com o sinal seco x que o gerou.
%
%   m = metricasPitchShift(x, y, fs, semitons)
%   m = metricasPitchShift(x, y, fs, semitons, opts)
%
% x e y são a entrada seca e a saída do pitch shifter (mono, mesma fs).
% Não precisam estar alinhados: o atraso é estimado pelo envelope.
%
% Campos de opts (todos opcionais):
%   atraso      atraso de y em relação a x, em amostras (se já for
%               conhecido; senão é estimado)
%   yin         opções do yinF0 (fmin, fmax, hop, W, limiar)
%   limiarDb    quadros com RMS abaixo de (máximo - limiarDb) são
%               ignorados (padrão 35 dB)
%
% Métricas (ver benchmark/README.md para a justificativa de cada uma):
%
%  Afinação, quadro a quadro com YIN (sinais monofônicos):
%   erroMedCents   mediana do erro de afinação nos quadros sem erro
%                  grosseiro (viés: o quanto a nota sai desafinada)
%   erroAbsP95     percentil 95 do |erro| (estabilidade/vibrato espúrio)
%   dentro5, dentro10  fração de quadros com |erro| <= 5 e <= 10 cents
%   gpe            gross pitch error: fração de quadros com |erro| > 50
%                  cents (oitava errada, nota errada, som sem altura)
%   nQuadros       quadros avaliados (com altura na entrada e na saída)
%
%  Transposição espectral (vale para acordes):
%   transpCents    deslocamento, em cents, que melhor alinha o espectro
%                  médio de y ao de x (correlação em eixo log-frequência)
%   erroTranspCents  transpCents - 100*semitons
%   simEspectral   correlação (0..1) entre os espectros alinhados
%   coloracaoDb    desvio RMS (dB, em bandas de 1/3 de oitava) entre o
%                  espectro de y e o espectro de x transposto
%                  idealmente (mudança de timbre além da transposição)
%
%  Artefatos:
%   dTonalRuidoDb  variação da razão tonal/ruído (energia nos picos
%                  espectrais / energia entre eles). Negativo = o
%                  algoritmo espalhou energia entre os harmônicos
%                  (phasiness, "chiado", ruído de fase)
%   dFlutuacaoDb   variação da flutuação rápida do envelope (4-40 Hz).
%                  Positivo = modulação de amplitude espúria ("warble",
%                  batimentos, som robótico)
%   dAtaqueMs      variação mediana do tempo de ataque (10%->90% do
%                  envelope) nos ataques detectados na entrada.
%                  Positivo = transiente borrado (palhetada "mole")
%   nAtaques       ataques usados nessa mediana
%   ganhoDb        RMS de y / RMS de x
%   atrasoMs       atraso usado no alinhamento (estimado pelos ataques;
%                  é aproximado, a latência de verdade é medida com o
%                  medeLatencia.m)

    if nargin < 5, opts = struct(); end
    x = mean(x, 2); y = mean(y, 2);
    L = min(numel(x), numel(y));
    x = x(1:L); y = y(1:L);
    limiarDb = campo(opts, 'limiarDb', 35);
    alfa = 2^(semitons/12);

    %% Alinhamento
    if isfield(opts, 'atraso')
        atraso = opts.atraso;
    else
        atraso = estimaAtraso(x, y, fs);
    end
    m.atrasoMs = 1e3 * atraso / fs;
    if atraso >= 0
        xa = x(1:L-atraso);  ya = y(1+atraso:L);
    else
        xa = x(1-atraso:L);  ya = y(1:L+atraso);
    end
    m.ganhoDb = 20*log10(rms(ya) / max(rms(xa), eps));

    %% Afinação (YIN)
    oy = campo(opts, 'yin', struct());
    [fx, ax, ~, rx] = yinF0(xa, fs, oy);
    [fy, ay, ~, ry] = yinF0(ya, fs, oy);
    n  = min(numel(fx), numel(fy));
    fx = fx(1:n); fy = fy(1:n);
    ativo = rx(1:n) > max(rx) - limiarDb & ry(1:n) > max(ry) - limiarDb;
    ok = ativo & ax(1:n) < 0.2 & ay(1:n) < 0.3 & ~isnan(fx) & ~isnan(fy);
    % Só avalia notas cuja saída cai na faixa do estimador
    fminY = campo(oy, 'fmin', 38);
    ok = ok & fx * alfa > 1.05 * fminY;
    err = 1200*log2(fy(ok) ./ fx(ok)) - 100*semitons;
    m.nQuadros = numel(err);
    if isempty(err)
        [m.erroMedCents, m.erroAbsP95, m.dentro5, m.dentro10, m.gpe] = deal(NaN);
    else
        fino = abs(err) <= 50;
        m.gpe = mean(~fino);
        e = err(fino);
        if isempty(e)
            [m.erroMedCents, m.erroAbsP95, m.dentro5, m.dentro10] = deal(NaN);
        else
            m.erroMedCents = median(e);
            m.erroAbsP95   = prctile_(abs(e), 95);
            m.dentro5      = mean(abs(err) <= 5);
            m.dentro10     = mean(abs(err) <= 10);
        end
    end
    m.errosCents = err;          % para histogramas

    %% Espectro médio (Welch) e transposição por correlação em log-frequência
    Nw = 16384;
    [Px, f] = espectroMedio(xa, fs, Nw, limiarDb);
    Py      = espectroMedio(ya, fs, Nw, limiarDb);
    passo = 1;                                    % cents
    c     = (0 : passo : 1200*log2(5000/60))';    % 60 Hz .. 5 kHz
    fl    = 60 * 2.^(c/1200);
    Sx = sqrt(interp1(f, Px, fl, 'linear', 0));   % magnitude
    Sy = sqrt(interp1(f, Py, fl, 'linear', 0));
    alvo = 100*semitons;
    lags = round((alvo - 150)/passo) : round((alvo + 150)/passo);
    cc = zeros(numel(lags), 1);
    for k = 1:numel(lags)
        cc(k) = corrDesloc(Sx, Sy, lags(k));
    end
    [cmax, k] = max(cc);
    p = 0;
    if k > 1 && k < numel(cc)
        den = cc(k-1) - 2*cc(k) + cc(k+1);
        if den < 0, p = 0.5*(cc(k-1) - cc(k+1)) / den; end
    end
    m.transpCents     = (lags(k) + p) * passo;
    m.erroTranspCents = m.transpCents - alvo;
    m.simEspectral    = cmax;

    % Coloração: bandas de 1/3 de oitava entre 100 Hz e 8 kHz
    fc  = 100 * 2.^((0:3*log2(80))/3);
    Ex  = zeros(size(fc)); Ey = Ex;
    for b = 1:numel(fc)
        lo = fc(b) * 2^(-1/6); hi = fc(b) * 2^(1/6);
        Ey(b) = sum(Py(f >= lo & f < hi));
        Ex(b) = sum(Px(f >= lo/alfa & f < hi/alfa)) / alfa;  % x transposto
    end
    v = Ex > 0 & Ey > 0 & Ex > max(Ex) * 1e-6;
    d = 10*log10(Ey(v) ./ Ex(v));
    d = d - mean(d);                              % ignora o ganho
    m.coloracaoDb = sqrt(mean(d.^2));

    %% Razão tonal/ruído
    m.dTonalRuidoDb = tonalRuido(ya, fs, limiarDb) - tonalRuido(xa, fs, limiarDb);

    %% Envelope: flutuação, ataques e pré-eco
    [ex, fe] = envelope_(xa, fs);
    ey       = envelope_(ya, fs);
    m.dFlutuacaoDb = flutuacao(ey, fe, limiarDb) - flutuacao(ex, fe, limiarDb);
    [m.dAtaqueMs, m.nAtaques] = ataques(ex, ey, fe);
end

%% ----------------------------------------------------------------------
function [P, f] = espectroMedio(x, fs, Nw, limiarDb)
    hop = Nw / 4;
    w = 0.5 - 0.5*cos(2*pi*(0:Nw-1)'/Nw);
    nFr = floor((numel(x) - Nw) / hop) + 1;
    P = zeros(Nw/2 + 1, 1);
    if nFr < 1
        x(end+1:Nw) = 0; nFr = 1;
    end
    e = zeros(nFr, 1); Q = zeros(Nw/2+1, nFr);
    for k = 1:nFr
        s = x((k-1)*hop + (1:Nw)) .* w;
        X = fft(s);
        Q(:, k) = abs(X(1:Nw/2+1)).^2;
        e(k) = sum(Q(:, k));
    end
    eDb = 10*log10(e + eps);
    use = eDb > max(eDb) - limiarDb;
    P = mean(Q(:, use), 2);
    f = (0:Nw/2)' * fs / Nw;
end

function r = corrDesloc(a, b, lag)
    % correlação de Pearson entre a(i) e b(i+lag)
    n = numel(a);
    if lag >= 0
        u = a(1:n-lag); v = b(1+lag:n);
    else
        u = a(1-lag:n); v = b(1:n+lag);
    end
    u = u - mean(u); v = v - mean(v);
    r = sum(u.*v) / max(sqrt(sum(u.^2) * sum(v.^2)), eps);
end

function tnr = tonalRuido(x, fs, limiarDb)
    % Mediana, nos quadros ativos, de 10log10(E_picos / E_resto). Um bin
    % é "pico" se é máximo local e está 6 dB acima da média móvel do
    % espectro (em dB); a máscara cobre o lóbulo principal (+-2 bins).
    N = 4096; hop = 1024;
    w = 0.5 - 0.5*cos(2*pi*(0:N-1)'/N);
    kmax = round(6000 / fs * N);                  % até 6 kHz
    nFr = floor((numel(x) - N) / hop) + 1;
    if nFr < 1, tnr = NaN; return; end
    v = nan(nFr, 1); e = zeros(nFr, 1);
    for k = 1:nFr
        X = abs(fft(x((k-1)*hop + (1:N)) .* w)).^2;
        X = X(2:kmax);
        e(k) = sum(X);
        Xd = 10*log10(X + eps);
        ref = movmean(Xd, 41);
        pk = find(Xd(2:end-1) > Xd(1:end-2) & Xd(2:end-1) >= Xd(3:end) ...
                  & Xd(2:end-1) > ref(2:end-1) + 6) + 1;
        mask = false(size(X));
        for dlt = -2:2
            i = pk + dlt; i = i(i >= 1 & i <= numel(X));
            mask(i) = true;
        end
        v(k) = 10*log10((sum(X(mask)) + eps) / (sum(X(~mask)) + eps));
    end
    eDb = 10*log10(e + eps);
    use = eDb > max(eDb) - limiarDb;
    tnr = median(v(use));
end

function [e, fe] = envelope_(x, fs)
    % Envelope RMS com hop de 1 ms e janela de 5 ms
    hop = round(fs / 1000); N = round(0.005 * fs);
    nFr = floor((numel(x) - N) / hop) + 1;
    cs = cumsum([0; x(:).^2]);
    i0 = (0:nFr-1)' * hop;
    e = sqrt((cs(i0 + N + 1) - cs(i0 + 1)) / N);
    fe = fs / hop;
end

function fl = flutuacao(e, fe, limiarDb)
    % RMS (em dB) da parte rápida do envelope logarítmico: passa-faixa
    % 4-40 Hz feito com duas médias móveis (25 ms e 250 ms).
    eDb = 20*log10(e + eps);
    rap = movmean(eDb, round(0.025*fe)) - movmean(eDb, round(0.25*fe));
    use = eDb > max(eDb) - limiarDb;
    fl = 20*log10(sqrt(mean(rap(use).^2)) + eps);
end

function [dAt, nAt] = ataques(ex, ey, fe)
    % Ataques: subidas de mais de 12 dB em 20 ms no envelope da entrada,
    % separadas por pelo menos 150 ms.
    exDb = 20*log10(ex + eps);
    d20 = round(0.02*fe);
    subida = [zeros(d20,1); exDb(1+d20:end) - exDb(1:end-d20)];
    cand = find(subida > 12 & exDb > max(exDb) - 30);
    on = [];
    for i = cand'
        if isempty(on) || i - on(end) > 0.15*fe, on(end+1) = i; end %#ok<AGROW>
    end
    at = [];
    for i = on
        j0 = max(1, i - d20 - round(0.03*fe));     % 30 ms antes da subida
        j1 = min(numel(ex), i + round(0.1*fe));
        if j0 < 1 || j1 > numel(ey), continue; end
        tx = tempoAtaque(ex(j0:j1));
        ty = tempoAtaque(ey(j0:j1));
        if isnan(tx) || isnan(ty), continue; end
        at(end+1) = (ty - tx) / fe * 1e3; %#ok<AGROW>
    end
    nAt = numel(at);
    if nAt == 0
        dAt = NaN;
    else
        dAt = median(at);
    end
end

function t = tempoAtaque(e)
    [pico, k] = max(e);
    i10 = find(e(1:k) < 0.1*pico, 1, 'last');
    i90 = find(e(1:k) >= 0.9*pico, 1, 'first');
    if isempty(i10) || isempty(i90), t = NaN; return; end
    t = i90 - i10;
end

function r = rms(x)
    r = sqrt(mean(x(:).^2));
end

function p = prctile_(x, q)
    % percentil sem Statistics Toolbox
    x = sort(x(:)); n = numel(x);
    if n == 1, p = x; return; end
    p = interp1((0.5:n)'/n * 100, x, min(max(q, 50/n), 100 - 50/n));
end

function v = campo(s, nome, padrao)
    if isfield(s, nome), v = s.(nome); else, v = padrao; end
end
