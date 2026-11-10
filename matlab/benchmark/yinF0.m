function [f0, aper, t, rmsDb] = yinF0(x, fs, opts)
% yinF0  Estimador de frequência fundamental YIN (de Cheveigné & Kawahara,
% "YIN, a fundamental frequency estimator for speech and music", JASA
% 2002). Implementação própria para não depender do Audio Toolbox e para
% que o mesmo estimador seja usado em todos os sinais comparados.
%
%   [f0, aper, t, rmsDb] = yinF0(x, fs)
%   [...] = yinF0(x, fs, opts)   com campos opcionais:
%       fmin (38 Hz: Mi1, guitarra -12 st)   fmax (1500 Hz)   hop (256)
%       W (2048, janela de integração: >= 2 períodos de fmin)
%       limiar (0.15)
%
%   f0     frequência por quadro (Hz), NaN onde não há periodicidade
%   aper   aperiodicidade = mínimo da diferença média normalizada (0 =
%          periódico perfeito, ~1 = ruído); serve como confiança
%   t      instante do centro de cada quadro (s)
%   rmsDb  RMS do quadro em dB (para descartar silêncio)

    if nargin < 3, opts = struct(); end
    fmin   = campo(opts, 'fmin', 38);
    fmax   = campo(opts, 'fmax', 1500);
    hop    = campo(opts, 'hop', 256);
    W      = campo(opts, 'W', 2048);
    limiar = campo(opts, 'limiar', 0.15);

    x      = x(:);
    tauMax = ceil(fs / fmin);
    tauMin = max(2, floor(fs / fmax));
    L      = W + tauMax + 1;
    nFr    = max(0, floor((numel(x) - L) / hop) + 1);
    nfft   = 2^nextpow2(L + W);

    f0    = nan(nFr, 1);
    aper  = ones(nFr, 1);
    rmsDb = -inf(nFr, 1);
    t     = ((0:nFr-1)' * hop + W/2) / fs;

    tau  = (1:tauMax)';
    bloco = 256;                                  % quadros por lote (memória)
    for q0 = 1:bloco:nFr
        q   = q0 : min(nFr, q0 + bloco - 1);
        ini = (q - 1) * hop;
        F   = x(ini + (1:L)');                    % L x nq (índices vetoriais)
        if size(F, 2) ~= numel(q), F = reshape(F, L, numel(q)); end
        A   = F(1:W, :);

        % d(tau) = sum_j (x_j - x_{j+tau})^2 = e0 + e_tau - 2 r(tau)
        r   = real(ifft(fft(F, nfft) .* conj(fft(A, nfft))));
        r   = r(2:tauMax+1, :);
        cs  = cumsum([zeros(1, numel(q)); F.^2]);
        e0  = cs(W+1, :);
        et  = cs(tau + W + 1, :) - cs(tau + 1, :);
        d   = max(bsxfun(@plus, e0, et) - 2*r, 0);

        % Diferença média normalizada cumulativa
        dn  = d .* bsxfun(@rdivide, tau, max(cumsum(d), eps));

        rmsDb(q) = 10*log10(e0 / W + eps);

        for k = 1:numel(q)
            c = dn(:, k);
            i = find(c(tauMin:end) < limiar, 1) + tauMin - 1;
            if isempty(i)
                [~, i] = min(c(tauMin:end));
                i = i + tauMin - 1;
            else
                while i < tauMax && c(i+1) < c(i)  % desce até o mínimo local
                    i = i + 1;
                end
            end
            aper(q(k)) = c(i);
            if i <= tauMin || i >= tauMax, continue; end
            % Interpolação parabólica do mínimo
            a = c(i-1); b = c(i); g = c(i+1);
            den = a - 2*b + g;
            p = 0;
            if den > 0, p = 0.5 * (a - g) / den; end
            f0(q(k)) = fs / (i + p);
        end
    end
end

function v = campo(s, nome, padrao)
    if isfield(s, nome), v = s.(nome); else, v = padrao; end
end
