function atraso = latenciaAlgoritmo(processa, fs, semitons)
% latenciaAlgoritmo  Atraso (amostras) que um algoritmo offline introduz,
% medido com um trem de cliques. Mais confiável que estimar o atraso pela
% música (que tem poucos ataques e notas longas), e serve para alinhar a
% saída do nosso algoritmo com a entrada nas métricas.
%   processa  função @(x, semitons) que devolve o sinal processado

    periodo = round(0.25 * fs);
    x = zeros(round(4 * fs), 1);
    x(round(0.5*fs) : periodo : end - periodo) = 0.5;
    y = processa(x, semitons);
    atraso = estimaAtraso(x, y, fs, [-20 200]);
end
