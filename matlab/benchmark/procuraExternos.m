function ext = procuraExternos(pasta, seco)
% procuraExternos  Renderizações externas de um sinal seco, pelo nome:
%   <pasta>/<seco>_<+s>st_<tag>.wav   (ex.: A_natural_-5st_neural.wav)
% Devolve struct com campos tag, s (semitons) e arq. O arquivo de ida e
% volta opcional, <seco>_<+s>st_<tag>_idavolta.wav, fica em arqVolta
% ('' se não existir).

    ext = struct('tag', {}, 's', {}, 'arq', {}, 'arqVolta', {});
    if ~exist(pasta, 'dir'), return; end
    d = dir(fullfile(pasta, [seco '_*st_*.wav']));
    padrao = ['^' regexptranslate('escape', seco) '_([+-]?\d+)st_([A-Za-z0-9]+)\.wav$'];
    for k = 1:numel(d)
        t = regexp(d(k).name, padrao, 'tokens', 'once');
        if isempty(t), continue; end
        volta = fullfile(pasta, strrep(d(k).name, '.wav', '_idavolta.wav'));
        if ~exist(volta, 'file'), volta = ''; end
        ext(end+1) = struct('tag', t{2}, 's', str2double(t{1}), ...
                            'arq', fullfile(pasta, d(k).name), ...
                            'arqVolta', volta); %#ok<AGROW>
    end
end
