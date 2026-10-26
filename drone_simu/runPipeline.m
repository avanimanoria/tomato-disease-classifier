function res = runPipeline(pc)
%RUNPIPELINE Run ONE complete two-pass mission for a PipelineConfig (manual or saved mode).
%
%   res = runPipeline(pc)
%
%   Same engine and metric extractor as every other entry point (resolvePipeline ->
%   runInternal2Scenario -> computeInternal2Metrics / computeRunMetrics).
%   Modes:
%     manual           run pc.pipeline as selected
%     bestFixed        controller + spray stages from the saved Experiment F best fixed configuration
%     scenarioSelector controller + spray stages chosen by the saved Experiment F selector for this
%                      scenario; FAILS CLOSED for scenarios outside its training conditions
%     oracle           runs all 6 controller x spray choices on this scenario and keeps the best by
%                      hindsight (research comparator, non-deployable); res.oracleCandidates lists all
%   res: runId, hashes, pc (as run), cfg, field, run, metrics, runMetrics (table), warnings, info,
%        codeHash, wallTime_s.
    t0 = tic;
    pcRun = pc;
    notes = {};
    switch pc.mode
        case 'manual'
        case {'bestFixed', 'scenarioSelector'}
            [ctrl, spray, why] = savedModelChoice(pc);
            pcRun.pipeline.controller = ctrl; pcRun.pipeline.sprayCompensation = spray;
            notes{end+1} = why;
        case 'oracle'
            res = oracleRun(pc, t0);
            return;
        otherwise
            error('runPipeline:mode', 'Unknown mode "%s".', pc.mode);
    end
    res = runOne(pcRun, t0);
    res.pcRequested = pc;
    res.warnings = [notes, res.warnings];
end

% ------------------------------------------------------------------------------------
function res = runOne(pc, t0)
    [~, ~, warns] = validatePipeline(pc);
    [cfg, info] = resolvePipeline(pc);
    evalc('field = generateIrregularField(cfg);');
    run = runInternal2Scenario(cfg, field, 'pipeline');
    if isfield(run, 'cfgEffective'), ce = run.cfgEffective; else, ce = cfg; end
    m = computeInternal2Metrics(ce, field, run);
    [hA, hS, hP] = pipelineHash(pc);
    res.runId = sprintf('R%s-%s', datestr(now, 'yyyymmddTHHMMSS'), hA(1:8));
    res.configHash = hA; res.scenarioHash = hS; res.pipelineHash = hP;
    res.pc = pc; res.cfg = ce; res.field = field; res.run = run; res.metrics = m;
    res.info = info; res.warnings = warns;
    res.codeHash = codeHash();
    res.wallTime_s = toc(t0);
    res.runMetrics = computeRunMetrics(res);
end

function res = oracleRun(pc, t0)
    combos = {'pid', 'none'; 'pid', 'wind'; 'pid', 'windLag'; 'purePursuit', 'none'; 'purePursuit', 'wind'; 'purePursuit', 'windLag'};
    cand = cell(size(combos, 1), 1); score = -inf(size(combos, 1), 1);
    for i = 1:size(combos, 1)
        p = pc; p.mode = 'manual';
        p.pipeline.controller = combos{i, 1}; p.pipeline.sprayCompensation = combos{i, 2};
        [ok, errs] = validatePipeline(p);
        if ~ok, cand{i} = struct('skipped', strjoin(errs, '; ')); continue; end
        cand{i} = runOne(p, tic);
        score(i) = cand{i}.metrics.spray.targetDepositionPct;
    end
    [~, b] = max(score);
    res = cand{b};
    res.pcRequested = pc;
    res.oracleCandidates = table(combos(:, 1), combos(:, 2), score, 'VariableNames', {'controller', 'sprayCompensation', 'targetDepositionPct'});
    res.warnings = [{sprintf('ORACLE (hindsight): best of %d candidates = %s + %s', size(combos, 1), combos{b, 1}, combos{b, 2})}, res.warnings];
    res.wallTime_s = toc(t0);
    res.runMetrics = computeRunMetrics(res);
end

function [ctrl, spray, why] = savedModelChoice(pc)
    f = fullfile(fileparts(mfilename('fullpath')), 'results', 'benchmark', 'benchmark.mat');
    if ~isfile(f)
        error('runPipeline:noSavedModel', 'Saved Experiment F results not found (%s): run runExperimentF first.', f);
    end
    S = load(f); B = S.B;
    if strcmp(pc.mode, 'bestFixed')
        name = char(B.selection.bestFixed);
        why = sprintf('BEST FIXED (saved Experiment F, trained %s): %s', B.meta.date, name);
    else
        sc = pc.scenario;
        if ~sc.wind.enabled
            error('runPipeline:selectorOutOfScope', 'Scenario selector was trained only with wind on (1.0 / 2.5 m/s); this scenario has wind off.');
        end
        locMap = struct('groundTruthOracle', 'groundTruth', 'flowOdometry', 'flowOdometry', 'kalman', 'kalman');
        if ~isfield(locMap, pc.pipeline.localization)
            error('runPipeline:selectorOutOfScope', 'Scenario selector was not trained for localization "%s".', pc.pipeline.localization);
        end
        conds = B.pipeline.conditions;
        winds = cellfun(@(c) c.wind, conds); gusts = cellfun(@(c) c.gust, conds); dels = cellfun(@(c) c.delay, conds);
        [~, iw] = min(abs(unique(winds) - sc.wind.speed)); uw = unique(winds); w = uw(iw);
        g = 0.5 * (sc.gust_mps >= 0.25); d = 0.5 * (sc.valveDelay_s >= 0.25);
        k = find(winds == w & gusts == g & dels == d & cellfun(@(c) strcmp(c.loc, locMap.(pc.pipeline.localization)), conds), 1);
        name = char(B.selection.selectorChoice.selected(B.selection.selectorChoice.condIdx == k));
        why = sprintf('SCENARIO SELECTOR (saved Experiment F): condition %d (wind %.1f, gust %.1f, %s, delay %.1f) -> %s', ...
            k, w, g, locMap.(pc.pipeline.localization), d, name);
        if ~(sc.physics.payload && sc.physics.dynamics && sc.physics.energy && sc.physics.atmosphere)
            why = [why ' [WARNING: selector was trained with payload, dynamics, energy and atmosphere ON]'];
        end
    end
    if startsWith(name, 'PID'), ctrl = 'pid'; else, ctrl = 'purePursuit'; end
    if contains(name, 'lag'), spray = 'windLag'; elseif contains(name, 'wind'), spray = 'wind'; else, spray = 'none'; end
end

function h = codeHash()
    p = fileparts(mfilename('fullpath'));
    [st, out] = system(['git -C "' p '" rev-parse --short HEAD']);
    if st == 0, h = strtrim(out); else, h = 'unknown'; end
    [st2, out2] = system(['git -C "' p '" status --porcelain --untracked-files=no']);
    if st2 == 0 && ~isempty(strtrim(out2)), h = [h '+uncommitted']; end
end
