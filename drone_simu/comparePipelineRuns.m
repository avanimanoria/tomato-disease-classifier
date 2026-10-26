function T = comparePipelineRuns(resList, allowDifferentScenario)
%COMPAREPIPELINERUNS Side-by-side per-run metrics of 2-4 runs on the SAME frozen scenario.
%
%   T = comparePipelineRuns({res1, res2, ...})
%   Columns: Group, Metric, Unit, one column per run, and "<run k> - <run 1>" differences.
%   Paired fairness: all runs must share the scenario hash (same field + seeds + wind / gust /
%   localization traces + vehicle). Pass allowDifferentScenario = true to override (the table
%   is then marked UNPAIRED).
    if nargin < 2, allowDifferentScenario = false; end
    assert(numel(resList) >= 1 && numel(resList) <= 4, 'comparePipelineRuns:count', 'Compare 1-4 runs.');
    sh = cellfun(@(r) r.scenarioHash, resList, 'UniformOutput', false);
    paired = all(strcmp(sh, sh{1}));
    if ~paired && ~allowDifferentScenario
        error('comparePipelineRuns:unpaired', 'Runs use different scenarios (field / seeds / environment): not a paired comparison.');
    end
    base = resList{1}.runMetrics;
    T = base(:, {'Group', 'Metric', 'Unit'});
    for k = 1:numel(resList)
        M = resList{k}.runMetrics;
        v = nan(height(T), 1);
        for i = 1:height(T)
            j = find(M.Group == T.Group(i) & M.Metric == T.Metric(i) & M.Unit == T.Unit(i), 1);
            if ~isempty(j), v(i) = M.Value(j); end
        end
        T.(sprintf('Run%d', k)) = v;
    end
    for k = 2:numel(resList)
        T.(sprintf('Run%d_minus_Run1', k)) = T.(sprintf('Run%d', k)) - T.Run1;
    end
    T.Properties.Description = ternary(paired, 'PAIRED (identical scenario)', 'UNPAIRED - scenarios differ');
    T.Properties.UserData = struct('runIds', {cellfun(@(r) r.runId, resList, 'UniformOutput', false)}, ...
        'pipelines', {cellfun(@(r) pipelineLabel(r.pc), resList, 'UniformOutput', false)}, 'paired', paired);
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end
