function [d, resDb] = comparaRT(yOff, yRT, fs)
% comparaRT  Compara a saída gravada ao vivo com o mesmo seco processado
% offline. Devolve o atraso d (amostras, 0..300 ms) de yRT em relação a
% yOff e o resíduo (dB) depois de alinhar e igualar o ganho: < -30 dB
% indica que o tempo real reproduziu o offline sem falhas.

    yOff = yOff(:); yRT = mean(yRT, 2);
    L = min(numel(yOff), numel(yRT));
    yOff = yOff(1:L); yRT = yRT(1:L);
    nfft = 2^nextpow2(2*L);
    c = real(ifft(fft(yRT, nfft) .* conj(fft(yOff, nfft))));
    [~, k] = max(c(1:round(0.3*fs)));
    d = k - 1;
    a = yOff(1:L-d); b = yRT(1+d:L);
    g = (a' * b) / max(a' * a, eps);
    resDb = 10*log10(sum((b - g*a).^2) / max(sum(b.^2), eps));
end
