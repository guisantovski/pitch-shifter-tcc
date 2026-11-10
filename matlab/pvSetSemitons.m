function st = pvSetSemitons(st, semitons)
% pvSetSemitons  Troca a transposição sem reiniciar o estado.
%   O hop de síntese é arredondado para um inteiro, então o fator efetivo
%   é Hs/Ha. O erro de afinação resultante, medido com o benchmark/, é de
%   até ~3 cents com Ha = 256 e até ~9 cents com Ha = 128 (ex.: -7 st dá
%   Hs = 85 em vez de 85,4). Testado em 10/11/2026: usar Hs real (sem
%   arredondar) acerta a altura, mas cria modulação de amplitude forte e
%   perde ~7 dB, então o arredondamento fica.

    if abs(semitons) > 12
        error('pvSetSemitons: use no máximo ±12 semitons.');
    end
    st.semitons = semitons;
    st.Hs    = round(2^(semitons/12) * st.Ha);   % hop de síntese
    st.alfa  = st.Hs / st.Ha;                    % fator de transposição efetivo
    st.L     = floor((st.N - 1) / st.alfa) + 1;  % tamanho do grão reamostrado
    st.tGrao = (0:st.L-1)' * st.alfa;            % posições de leitura no grão

    % Hann² somada com hop Hs vale 3N/(8Hs); este ganho normaliza o
    % overlap-add (a reamostragem não muda a soma, só a escala de tempo).
    st.ganhoOla = 8 * st.Hs / (3 * st.N);
end
