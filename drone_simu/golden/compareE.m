function ok = compareE(projDir, goldenFile, tol)
%COMPAREE Experiment-E regression: current runExperimentE vs the pre-refactor golden.
%   ok = compareE(projDir, goldenFile [, tol])
%
%   Scenarios are matched by position (labels were renamed by the refactor:
%   'PID only' -> 'Navigation Corrected', 'Corrected' -> 'Fully Corrected').
%   Every numeric leaf in the golden runs, mets and table is classified:
%     BIT-IDENTICAL                    isequaln
%     EQUAL WITHIN NUMERICAL TOLERANCE |a-b| <= tol*max(1,|a|)  (default tol 1e-9)
%     CHANGED                          anything else
%   Pure label fields (name / scenario strings) are listed separately and do
%   not count as behavioural changes. New fields in current output are allowed.
    if nargin < 3, tol = 1e-9; end
    addpath(projDir);
    G = load(goldenFile);
    cfg = config();
    cfg.internal2.enabled = true;
    field = generateIrregularField(cfg);
    res = runExperimentE(cfg, field, false);

    nS = numel(G.runs);
    assert(numel(res.runs) == nS, 'compareE: scenario count differs (%d vs %d)', numel(res.runs), nS);

    cnt = struct('ident', 0, 'tol', 0, 'changed', 0, 'label', 0);
    ok = true;
    fprintf('Experiment-E regression: golden "%s" vs current code\n', goldenFile);
    for i = 1:nS
        L = {};
        L = [L, walk(G.runs{i}, res.runs{i}, 'run', tol)]; %#ok<AGROW>
        L = [L, walk(G.mets{i}, res.mets{i}, 'met', tol)]; %#ok<AGROW>
        rowG = table2struct(G.table(i, :));
        rowC = table2struct(res.table(i, :));
        L = [L, walk(rowG, rowC, 'table', tol)]; %#ok<AGROW>
        cls = cellfun(@(x) x{2}, L, 'UniformOutput', false);
        nI = sum(strcmp(cls, 'I')); nT = sum(strcmp(cls, 'T')); nC = sum(strcmp(cls, 'C')); nL = sum(strcmp(cls, 'L'));
        cnt.ident = cnt.ident + nI; cnt.tol = cnt.tol + nT; cnt.changed = cnt.changed + nC; cnt.label = cnt.label + nL;
        if nC > 0
            verdict = 'CHANGED';
        elseif nT > 0
            verdict = 'EQUAL WITHIN NUMERICAL TOLERANCE';
        else
            verdict = 'BIT-IDENTICAL';
        end
        fprintf('  [%d] %-22s -> %-22s : %-32s (identical %d, tolerance %d, changed %d, label-only %d)\n', ...
            i, char(G.scn(i).name), char(res.scn(i).name), verdict, nI, nT, nC, nL);
        for k = 1:numel(L)
            if any(strcmp(L{k}{2}, {'C', 'T'}))
                fprintf('        %-8s %s  (golden=%s, now=%s)\n', ...
                    ternary(L{k}{2} == 'C', 'CHANGED', 'TOL-EQ'), L{k}{1}, L{k}{3}, L{k}{4});
            end
        end
        if nC > 0, ok = false; end
    end
    detOK = isequal(res.determinismOK, G.determinismOK);
    fprintf('  determinismOK: golden=%d now=%d\n', G.determinismOK, res.determinismOK);
    ok = ok && detOK;
    fprintf('TOTAL leaves: bit-identical %d | tolerance-equal %d | changed %d | label-only %d\n', ...
        cnt.ident, cnt.tol, cnt.changed, cnt.label);
    if ok, fprintf('E-LEVEL GATE: PASS\n'); else, fprintf('E-LEVEL GATE: FAIL\n'); end
end

function L = walk(a, b, path, tol)
% Returns cell of {path, class, goldenStr, nowStr}; class I/T/C/L.
    L = {};
    if isstruct(a)
        if ~isstruct(b), L = {{path, 'C', 'struct', class(b)}}; return; end
        f = fieldnames(a);
        for k = 1:numel(f)
            if ~isfield(b, f{k}), L{end+1} = {[path '.' f{k}], 'C', 'present', 'missing'}; continue; end %#ok<AGROW>
            L = [L, walk(a.(f{k}), b.(f{k}), [path '.' f{k}], tol)]; %#ok<AGROW>
        end
    elseif iscell(a)
        if ~iscell(b) || ~isequal(size(a), size(b)), L = {{path, 'C', 'cell', 'cell/size'}}; return; end
        for k = 1:numel(a)
            L = [L, walk(a{k}, b{k}, sprintf('%s{%d}', path, k), tol)]; %#ok<AGROW>
        end
    elseif isstring(a) || ischar(a)
        if isequaln(a, b)
            L = {{path, 'I', '', ''}};
        else
            L = {{path, 'L', char(join(string(a))), char(join(string(b)))}};   % label text (scenario names)
        end
    elseif isnumeric(a) || islogical(a)
        if isequaln(a, b)
            L = {{path, 'I', '', ''}};
        elseif isnumeric(b) && isequal(size(a), size(b)) && all(abs(double(a(:)) - double(b(:))) <= tol * max(1, abs(double(a(:)))) | ...
                (isnan(a(:)) & isnan(b(:))))
            L = {{path, 'T', sprintf('%.17g', a(1)), sprintf('%.17g', b(1))}};
        else
            L = {{path, 'C', mat2str(a(1:min(end, 3)), 6), mat2str(b(1:min(end, 3)), 6)}};
        end
    else
        if isequaln(a, b), L = {{path, 'I', '', ''}}; else, L = {{path, 'C', class(a), class(b)}}; end
    end
end

function s = ternary(c, a, b)
    if c, s = a; else, s = b; end
end
