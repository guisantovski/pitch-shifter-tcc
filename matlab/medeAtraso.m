function [atraso, confianca] = medeAtraso(ref, rec, periodo)
% medeAtraso  Atraso (em amostras) entre o trem de cliques emitido e o
% gravado, por correlação cruzada circular via FFT.
%   ref      sinal emitido (cliques a cada 'periodo' amostras)
%   rec      sinal gravado na entrada (mesmo tamanho de ref)
%   periodo  distância entre cliques; o atraso procurado fica em [0, periodo)
%   confianca  pico da correlação dividido pelo segundo maior pico fora da
%              vizinhança (> 2 indica medida confiável)

    L = min(numel(ref), numel(rec));
    ref = ref(1:L); rec = rec(1:L);
    c = abs(real(ifft(fft(rec) .* conj(fft(ref)))));
    c = c(1:periodo);                       % atrasos de 0 a periodo-1
    [pico, k] = max(c);
    atraso = k - 1;

    viz = max(1, k-200) : min(periodo, k+200);
    resto = c; resto(viz) = 0;
    confianca = pico / max(max(resto), eps);
end
