function st = pvInit(N, Ha, B, semitons, phaseLock)
% pvInit  Cria o estado do phase vocoder em streaming (algoritmo do Grondin).
%   st = pvInit(N, Ha, B, semitons)
%     N        tamanho do quadro/FFT (ex.: 1024)
%     Ha       hop de análise (ex.: 256, 75% de sobreposição)
%     B        tamanho do bloco de I/O da interface (ex.: 64); Ha tem que
%              ser múltiplo de B
%     semitons transposição em semitons (pode ser trocada depois com
%              pvSetSemitons)
%     phaseLock true liga o phase locking de Laroche-Dolson; false
%              (padrão) reproduz o algoritmo original do Grondin.
%              Testado em 25/10/2026: melhora o RMS, mas piora o som de
%              ouvido (mais phasiness), por isso fica desligado.

    if nargin < 5
        phaseLock = false;
    end
    if mod(Ha, B) ~= 0
        error('pvInit: Ha (%d) tem que ser múltiplo de B (%d).', Ha, B);
    end

    st.N  = N;
    st.Ha = Ha;
    st.B  = B;
    st.R  = Ha / B;                         % blocos de I/O por quadro
    st.phaseLock = phaseLock;

    n = (0:N-1)';
    st.win   = 0.5 - 0.5 * cos(2*pi*n/N);   % Hann periódica
    st.omega = 2*pi*n/N;                    % freq. central de cada bin (rad/amostra)

    % Buffers de entrada e de overlap-add. O grão reamostrado pode ter até
    % N/alfa amostras; o buffer cobre até -12 semitons (alfa = 0,5).
    st.inBuf  = zeros(N, 1);
    st.ola    = zeros(2*N + Ha, 1);
    st.outBlk = zeros(Ha, 1);               % último hop pronto para saída
    st.blk    = 1;                          % próximo bloco de outBlk a enviar
    st.cont   = 0;                          % blocos recebidos desde o último quadro

    % Fases (estado recursivo do phase vocoder)
    st.fasePrev  = zeros(N, 1);
    st.faseSint  = zeros(N, 1);

    st = pvSetSemitons(st, semitons);
end
