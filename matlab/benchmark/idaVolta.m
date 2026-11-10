function mos = idaVolta(x, yVolta, fs)
% idaVolta  ViSQOL (modo áudio) do teste de ida e volta: o sinal seco x é
% transposto +s e depois -s (yVolta) e comparado com o original. Como o
% resultado volta à altura original, dá para usar uma métrica perceptual
% com referência (intrusiva), que não se aplica diretamente ao pitch
% shift. A degradação acumula as duas passagens, então serve para
% comparar algoritmos entre si, não como nota absoluta.
% Precisa da função visqol (Audio Toolbox, R2023a+). Devolve NaN se não
% houver.

    mos = NaN;
    if ~exist('visqol', 'file') && ~exist('visqol', 'builtin'), return; end
    x = mean(x, 2); yVolta = mean(yVolta, 2);
    L = min(numel(x), numel(yVolta));
    x = x(1:L); yVolta = yVolta(1:L);

    % Alinhamento por correlação da forma de onda (mesma altura), 0..300 ms
    nfft = 2^nextpow2(2*L);
    c = real(ifft(fft(yVolta, nfft) .* conj(fft(x, nfft))));
    [~, k] = max(c(1 : round(0.3*fs)));
    d = k - 1;
    x = x(1:L-d); yVolta = yVolta(1+d:L);
    yVolta = yVolta * (sqrt(mean(x.^2)) / max(sqrt(mean(yVolta.^2)), eps));

    try
        if fs ~= 48000
            x = resample(x, 48000, fs); yVolta = resample(yVolta, 48000, fs);
        end
        mos = visqol(yVolta, x, 48000, 'Mode', 'audio');
    catch e
        warning('idaVolta: visqol falhou (%s)', e.message);
    end
end
