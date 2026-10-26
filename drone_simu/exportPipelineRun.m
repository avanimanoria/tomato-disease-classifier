function outDir = exportPipelineRun(res, baseDir, comparison)
%EXPORTPIPELINERUN Write one run (and optionally its comparison table) to disk.
%
%   outDir = exportPipelineRun(res [, baseDir [, comparisonTable]])
%   Creates <baseDir>/<runId>/ with config.json (as run), requested_config.json,
%   run_info.json (hashes, code hash, seeds, implementations, calibration, warnings),
%   metrics.csv and, if given, comparison.csv. Default baseDir: pipeline_runs/ (never results/).
    if nargin < 2 || isempty(baseDir)
        baseDir = fullfile(fileparts(mfilename('fullpath')), 'pipeline_runs');
    end
    outDir = fullfile(baseDir, res.runId);
    if ~isfolder(outDir), mkdir(outDir); end
    savePipelineConfig(res.pc, fullfile(outDir, 'config.json'));
    if isfield(res, 'pcRequested'), savePipelineConfig(res.pcRequested, fullfile(outDir, 'requested_config.json')); end
    S = res.pc.scenario;
    info = struct('runId', res.runId, 'configHash', res.configHash, 'scenarioHash', res.scenarioHash, ...
        'pipelineHash', res.pipelineHash, 'codeHash', res.codeHash, 'exportedAt', datestr(now, 'yyyy-mm-dd HH:MM:SS'), ...
        'seeds', struct('field', S.field.seed, 'gust', S.gustSeed, 'localization', S.locSeed), ...
        'implementations', res.info, 'warnings', {res.warnings}, 'wallTime_s', res.wallTime_s);
    fid = fopen(fullfile(outDir, 'run_info.json'), 'w');
    fwrite(fid, jsonencode(info, 'PrettyPrint', true), 'char');
    fclose(fid);
    writetable(res.runMetrics, fullfile(outDir, 'metrics.csv'));
    if nargin >= 3 && ~isempty(comparison)
        writetable(comparison, fullfile(outDir, 'comparison.csv'));
    end
end
