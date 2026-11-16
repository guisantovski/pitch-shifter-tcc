function atraso = estimaAtraso(x, y, fs, faixaMs)
% estimaAtraso  Atraso (amostras) de y em relação a x, pela correlação
% cruzada da "força de ataque" (derivada positiva do envelope em dB).
% Funciona mesmo com y transposto, porque o envelope não depende da
% altura. Resolução de 1 ms (o hop do envelope), refinada por parábola.
%   faixaMs  [mín máx] do atraso procurado (padrão [-50 300] ms)

    if nargin < 4, faixaMs = [-50 300]; end
    hop = round(fs / 1000);
    ox = forcaAtaque(x, hop);
    oy = forcaAtaque(y, hop);
    n = min(numel(ox), numel(oy));
    ox = ox(1:n); oy = oy(1:n);
    lags = round(faixaMs(1)) : round(faixaMs(2));
    c = zeros(numel(lags), 1);
    for k = 1:numel(lags)
        l = lags(k);
        if l >= 0
            c(k) = sum(ox(1:n-l) .* oy(1+l:n));
        else
            c(k) = sum(ox(1-l:n) .* oy(1:n+l));
        end
    end
    [~, k] = max(c);
    p = 0;
    if k > 1 && k < numel(c)
        den = c(k-1) - 2*c(k) + c(k+1);
        if den < 0, p = 0.5*(c(k-1) - c(k+1)) / den; end
    end
    atraso = round((lags(k) + p) * hop);
end

function o = forcaAtaque(x, hop)
    x = mean(x, 2);
    N = 4 * hop;
    nFr = floor((numel(x) - N) / hop) + 1;
    cs = cumsum([0; x.^2]);
    i0 = (0:nFr-1)' * hop;
    eDb = 10*log10((cs(i0 + N + 1) - cs(i0 + 1)) / N + 1e-10);
    eDb = max(eDb, max(eDb) - 50);
    o = max([0; diff(eDb)], 0);
    o = o - mean(o);
end
