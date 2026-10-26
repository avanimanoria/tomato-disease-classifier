function ok = compareGolden(projDir, goldenFile)
%COMPAREGOLDEN Re-run the 4 original scenarios with CURRENT code; every field
%   present in the golden runs/metrics must be bit-identical (new fields allowed).
    addpath(projDir);
    G = load(goldenFile);
    cfgBase = config();
    cfgBase.internal2.enabled = true;
    field = generateIrregularField(cfgBase);
    sw = [0 0 0; 1 0 0; 1 1 0; 1 1 1];
    names = {'Baseline', 'Disturbed', 'PID only', 'Corrected'};
    ok = true;
    for i = 1:4
        cfg = cfgBase;
        cfg.internal2.wind.enabled     = logical(sw(i, 1));
        cfg.internal2.ctrl.enabled     = logical(sw(i, 2));
        cfg.internal2.spray.compensate = logical(sw(i, 3));
        run = runInternal2Scenario(cfg, field, names{i});
        met = computeInternal2Metrics(cfg, field, run);
        bad = {};
        bad = [bad, subsetDiff(G.runs{i}, run, sprintf('run{%d}', i))]; %#ok<AGROW>
        bad = [bad, subsetDiff(G.mets{i}, met, sprintf('met{%d}', i))]; %#ok<AGROW>
        if isempty(bad)
            fprintf('  %-10s : IDENTICAL\n', names{i});
        else
            ok = false;
            fprintf('  %-10s : DIFFERS in:\n', names{i});
            fprintf('      %s\n', bad{:});
        end
    end
    if ok, fprintf('GOLDEN GATE: PASS\n'); else, fprintf('GOLDEN GATE: FAIL\n'); end
end

function bad = subsetDiff(a, b, path)
    bad = {};
    if isstruct(a)
        if ~isstruct(b), bad = {path}; return; end
        f = fieldnames(a);
        for k = 1:numel(f)
            if ~isfield(b, f{k}), bad{end+1} = [path '.' f{k} ' (missing)']; continue; end %#ok<AGROW>
            bad = [bad, subsetDiff(a.(f{k}), b.(f{k}), [path '.' f{k}])]; %#ok<AGROW>
        end
    elseif iscell(a)
        if ~iscell(b) || ~isequal(size(a), size(b)), bad = {path}; return; end
        for k = 1:numel(a)
            bad = [bad, subsetDiff(a{k}, b{k}, sprintf('%s{%d}', path, k))]; %#ok<AGROW>
        end
    else
        if ~isequaln(a, b), bad = {path}; end
    end
end
