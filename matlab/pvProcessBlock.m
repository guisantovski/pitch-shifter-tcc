function [y, st] = pvProcessBlock(x, st)
% pvProcessBlock  Processa um bloco de B amostras em tempo real.
%   [y, st] = pvProcessBlock(x, st)
%
% Phase vocoder do Grondin (guitarpitchshifter.com) reescrito para
% streaming. A cada Ha amostras de entrada:
%   1. FFT do quadro de N amostras com janela Hann;
%   2. frequência verdadeira de cada bin pela diferença de fase;
%   3. fase de síntese acumulada com o hop Hs = alfa*Ha (time-stretch);
%      opcionalmente com phase locking (st.phaseLock, ver pvInit);
%   4. IFFT e janela de síntese;
%   5. reamostragem do grão por interpolação linear (N -> N/alfa), o que
%      equivale a reamostrar o sinal esticado inteiro, como no original;
%   6. overlap-add com hop Ha.
% Entre um quadro e outro só copia amostras, então o custo fica
% concentrado em 1 de cada R = Ha/B chamadas.

    N = st.N; Ha = st.Ha; B = st.B;

    % Entrada: desloca o buffer e acrescenta o bloco novo
    st.inBuf(1:N-B)   = st.inBuf(B+1:N);
    st.inBuf(N-B+1:N) = x;
    st.cont = st.cont + 1;

    if st.cont == st.R
        st.cont = 0;

        % 1. Análise
        X    = fft(st.win .* st.inBuf);
        mag  = abs(X);
        fase = angle(X);

        % 2. Frequência verdadeira (rad/amostra)
        dfase = fase - st.fasePrev - Ha * st.omega;
        dfase = dfase - 2*pi * round(dfase / (2*pi));
        freqV = st.omega + dfase / Ha;
        st.fasePrev = fase;

        % 3. Fase de síntese
        st.faseSint = st.faseSint + st.Hs * freqV;

        % 3b. Phase locking (Laroche-Dolson, "identity"): cada bin segue a
        %     fase do pico espectral mais próximo, mantendo a diferença de
        %     fase que tinha na análise. Não existe no original do Grondin;
        %     sem isso a relação de fase entre bins vizinhos se perde e o
        %     som fica "distante" (phasiness), principalmente em acordes.
        if st.phaseLock
            M  = N/2 + 1;
            m  = mag(1:M);
            pk = find(m(2:M-1) > m(1:M-2) & m(2:M-1) >= m(3:M)) + 1;
            if numel(pk) >= 2
                dono = interp1(pk, pk, (1:M)', 'nearest', 'extrap');
            else
                dono = repmat(pk, M, 1);   % um pico só (ex.: seno puro)
            end
            if ~isempty(pk)
                fh   = st.faseSint(dono) + fase(1:M) - fase(dono);
                st.faseSint(1:M)     = fh;
                st.faseSint(M+1:N)   = -fh(M-1:-1:2);   % simetria (sinal real)
            end
        end
        st.faseSint = st.faseSint - 2*pi * round(st.faseSint / (2*pi));

        % 4. Síntese
        grao = real(ifft(mag .* exp(1i * st.faseSint))) .* st.win;

        % 5. Reamostragem linear do grão
        i0   = floor(st.tGrao);
        frac = st.tGrao - i0;
        i1   = min(i0 + 2, N);
        grao = (1 - frac) .* grao(i0 + 1) + frac .* grao(i1);

        % 6. Overlap-add
        L = st.L;
        st.ola(1:L) = st.ola(1:L) + st.ganhoOla * grao;
        st.outBlk   = st.ola(1:Ha);
        st.ola(1:end-Ha)     = st.ola(Ha+1:end);
        st.ola(end-Ha+1:end) = 0;
        st.blk = 1;
    end

    % Saída: próximo pedaço de B amostras do hop pronto
    y = st.outBlk((st.blk-1)*B + 1 : st.blk*B);
    st.blk = st.blk + 1;
end
