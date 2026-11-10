function [x, seg] = geraNotasTeste(fs)
% geraNotasTeste  Sinal sintético de teste: notas "dedilhadas" na
% extensão da guitarra (Mi2 a Mi5), com f0 exatamente conhecida.
%
%   [x, seg] = geraNotasTeste(fs)
%   seg(k).ini, seg(k).fim  amostras da nota k (sem o silêncio)
%   seg(k).f0, seg(k).nome
%
% Cada nota é uma soma de 20 harmônicos com amplitude 1/h, decaimento
% exponencial mais rápido nos harmônicos altos (como uma corda real),
% ataque de 2 ms e fases determinísticas. Não usa números aleatórios, para
% que o arquivo saia idêntico no MATLAB e no Octave e possa ser renderizado
% também por plugins externos (ver README).

    if nargin < 1, fs = 44100; end
    nomes = {'Mi2', 'La2', 'Re3', 'Sol3', 'Si3', 'Mi4', 'La4', 'Mi5'};
    midi  = [40 45 50 55 59 64 69 76];
    durNota = 1.5; durPausa = 0.3; durIni = 0.5;

    nN = round(durNota * fs);
    t  = (0:nN-1)' / fs;
    ataque = min(t / 0.002, 1);

    x = zeros(round(durIni*fs), 1);
    seg = struct('ini', {}, 'fim', {}, 'f0', {}, 'nome', {});
    for k = 1:numel(midi)
        f0 = 440 * 2^((midi(k) - 69)/12);
        nota = zeros(nN, 1);
        for h = 1:20
            fh = h * f0;
            if fh > 0.45*fs, break; end
            tau = 1.2 / (1 + 0.25*h);                % decaimento (s)
            nota = nota + (1/h) * exp(-t/tau) .* sin(2*pi*fh*t + 0.7*h^2);
        end
        nota = 0.3 * nota .* ataque / max(abs(nota));
        seg(k).ini  = numel(x) + 1;
        seg(k).fim  = numel(x) + nN;
        seg(k).f0   = f0;
        seg(k).nome = nomes{k};
        x = [x; nota; zeros(round(durPausa*fs), 1)]; %#ok<AGROW>
    end
    x = [x; zeros(round(durIni*fs), 1)];
end
