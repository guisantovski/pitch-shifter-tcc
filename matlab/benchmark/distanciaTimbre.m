function d = distanciaTimbre(y, ref, fs)
% distanciaTimbre  Diferença de envelope espectral (dB RMS, bandas de 1/3
% de oitava de 100 Hz a 8 kHz) entre o sinal transposto y e uma gravação
% de referência da nota tocada de verdade na altura de destino (ex.: Lá
% transposto -5 st contra o Mi natural). O ganho médio é descontado.
% Mede verossimilhança de timbre: um pitch shift sem preservação de
% formantes "estica" o corpo da guitarra junto com a nota.

    [Py, f] = ltas(mean(y, 2), fs);
    Pr      = ltas(mean(ref, 2), fs);
    fc = 100 * 2.^((0:3*log2(80))/3);
    Ey = zeros(size(fc)); Er = Ey;
    for b = 1:numel(fc)
        sel = f >= fc(b)*2^(-1/6) & f < fc(b)*2^(1/6);
        Ey(b) = sum(Py(sel)); Er(b) = sum(Pr(sel));
    end
    v = Ey > max(Ey)*1e-6 & Er > max(Er)*1e-6;
    e = 10*log10(Ey(v) ./ Er(v));
    e = e - mean(e);
    d = sqrt(mean(e.^2));
end

function [P, f] = ltas(x, fs)
    N = 8192; hop = N/2;
    w = 0.5 - 0.5*cos(2*pi*(0:N-1)'/N);
    nFr = floor((numel(x) - N)/hop) + 1;
    Q = zeros(N/2+1, nFr); e = zeros(nFr, 1);
    for k = 1:nFr
        X = fft(x((k-1)*hop + (1:N)) .* w);
        Q(:, k) = abs(X(1:N/2+1)).^2;
        e(k) = sum(Q(:, k));
    end
    eDb = 10*log10(e + eps);
    P = mean(Q(:, eDb > max(eDb) - 35), 2);
    f = (0:N/2)' * fs / N;
end
