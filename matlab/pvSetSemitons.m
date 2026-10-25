function st = pvSetSemitons(st, semitons)
% pvSetSemitons  Troca a transposição sem reiniciar o estado.
%   O hop de síntese é arredondado para um inteiro, então o fator efetivo
%   é Hs/Ha (erro máximo de ~3 cents com Ha = 256).

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
