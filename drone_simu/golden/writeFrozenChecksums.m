function T = writeFrozenChecksums(projDir, outFile)
%WRITEFROZENCHECKSUMS SHA-256 of every frozen artifact: results/ (Experiments A-F, ablation,
%   screenshots) and golden/ reference data (*.mat, *.csv, *.json). Read by
%   tests/FrozenExperimentIntegrityTest. Run once on the verified baseline.
    files = [dir(fullfile(projDir, 'results', '**', '*.*')); dir(fullfile(projDir, 'golden', '**', '*.mat')); ...
             dir(fullfile(projDir, 'golden', '**', '*.csv')); dir(fullfile(projDir, 'golden', '**', '*.json'))];
    files = files(~[files.isdir]);
    rows = cell(numel(files), 2);
    for i = 1:numel(files)
        p = fullfile(files(i).folder, files(i).name);
        rel = strrep(p(numel(projDir) + 2:end), '\', '/');
        rows(i, :) = {rel, fileSha256(p)};
    end
    T = cell2table(rows, 'VariableNames', {'path', 'sha256'});
    T = T(~strcmp(T.path, strrep(outFile(numel(projDir) + 2:end), '\', '/')), :);
    T = sortrows(T, 'path');
    writetable(T, outFile);
    fprintf('%d frozen files hashed -> %s\n', height(T), outFile);
end
