function y = pvProcessaSinal(x, st)
% pvProcessaSinal  Passa um sinal inteiro pelo pvProcessBlock em blocos de
% st.B amostras, exatamente como o laço de tempo real faz. Como o
% algoritmo é determinístico, a saída é idêntica (amostra por amostra) à
% do pitchShiftRT.m com os mesmos parâmetros, desde que não haja underrun.
%   y = pvProcessaSinal(x, pvInit(N, Ha, B, semitons))
% O sinal é completado com zeros até um múltiplo de B; y tem numel(x).

    x  = x(:);
    B  = st.B;
    L  = numel(x);
    nB = ceil(L / B);
    x(end+1 : nB*B) = 0;
    y  = zeros(nB*B, 1);
    for n = 1:nB
        idx = (n-1)*B + (1:B);
        [y(idx), st] = pvProcessBlock(x(idx), st);
    end
    y = y(1:L);
end
