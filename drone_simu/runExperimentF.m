function B = runExperimentF(outDir, opts)
%RUNEXPERIMENTF Experiment F: algorithm benchmark + scenario-conditioned selection.
%
%   B = runExperimentF                 % full benchmark (about 30-40 min), writes results/benchmark/
%   B = runExperimentF(outDir, struct('quick', true))   % small smoke version
%
%   Implements the research-charter protocol in the existing MATLAB engine (all enhancement
%   flags are set INSIDE this script; the default simulation is never changed):
%
%   Part 1  Routing benchmark: 7 strategies on the frozen all-diseased target set of 5 field
%           seeds, equal speed, same start; geometric and flown distance, travel time, planning time.
%   Part 2  Pipeline benchmark: 6 configurations (guidance PID / pure pursuit x spray none /
%           wind compensation / wind + valve-lag compensation) x 24 conditions (wind 1 / 2.5 m/s x
%           gusts 0 / 0.5 m/s x localization ground truth / optical-flow odometry / Kalman x valve
%           delay 0 / 0.5 s), on a TRAIN field and two held-out TEST fields (different disease
%           layouts, wind directions and noise seeds). Realistic-physics base: payload, dynamics,
%           energy, atmosphere, actuation and safety enabled.
%   Selection: best fixed configuration (highest mean primary metric on train), scenario-
%           conditioned selector (best configuration for each train condition, applied to the
%           matching test condition) and per-instance oracle (unattainable upper bound).
%   Hypotheses: H1 rank reversals, H2 selector vs best fixed on held-out tests (paired bootstrap),
%           H3 two-factor interactions, H4 robustness to an alternative spray kernel.
%   Primary metric (pre-specified): simulated target deposition, % of emitted spray landing on
%   truly diseased canopies. Everything is a SIMULATED, UNCALIBRATED surrogate.

    if nargin < 1 || isempty(outDir), outDir = fullfile(fileparts(mfilename('fullpath')), 'results', 'benchmark'); end
    if nargin < 2, opts = struct(); end
    quick = isfield(opts, 'quick') && opts.quick;
    if isfile(fullfile(outDir, 'benchmark.mat')) && ~(isfield(opts, 'overwrite') && opts.overwrite)
        error('runExperimentF:frozen', ['%s already holds a benchmark (frozen evidence). Write a new run elsewhere, ' ...
            'e.g. runExperimentF(''results_F2''), or pass struct(''overwrite'', true) deliberately.'], outDir);
    end
    if ~isfolder(outDir), mkdir(outDir); end
    tAll = tic;
    B.meta.date = datestr(now, 'yyyy-mm-dd HH:MM');
    B.meta.matlab = version;
    B.meta.quick = quick;
    B.meta.primaryMetric = 'targetDepositionPct (simulated, % of emitted spray on truly diseased canopies)';

    %% ---------------- Part 1: routing benchmark ----------------
    algos = {'fixedOrder', 'nearestNeighbour', 'nearestNeighbour2opt', 'nearestNeighbourOrOpt', ...
             'cheapestInsertion', 'antColony', 'stage7Return'};
    seeds = [42 101 202 303 404];
    if quick, seeds = [42 101]; end
    rr = {};
    for s = seeds
        cfg = config(); cfg.internal2.enabled = true; cfg.internal2.seed = s;
        cfg.enhancements.enableAdvancedRouting = true;
        cfg.internal2.treat.speedFactor.stage7Return = 1.0;            % equal speed for all strategies
        fld = quietField(cfg);
        P = fld.plants; idx = frozenTargetOrder(fld);
        tgt = struct('plantIdx', idx, 'ID', P.ID(idx), 'XY', [P.X(idx), P.Y(idx)], ...
            'detectTime', zeros(numel(idx), 1), 'isTruePositive', true(numel(idx), 1));
        for a = 1:numel(algos)
            c = cfg; c.internal2.treat.routing = algos{a};
            r = runInternal2Scenario(c, fld, algos{a}, struct('targets', tgt));
            R = r.routes;
            switch algos{a}
                case 'fixedOrder', g = R.detOrderLength;
                case 'nearestNeighbour', g = R.nnLength;
                case 'stage7Return', g = R.stage7Length;
                otherwise, g = R.advancedLength;
            end
            pt = planTimeMs(algos{a}, r.startXY, tgt.XY);
            rr{end+1, 1} = struct('fieldSeed', s, 'algorithm', string(algos{a}), 'nTargets', numel(idx), ...
                'geometric_m', g, 'flown_m', R.actualDistance, 'travelTime_s', R.actualFlightTime, ...
                'totalTime_s', R.actualTotalTime, 'planTime_ms', pt); %#ok<AGROW>
        end
        fprintf('routing benchmark: field seed %d done\n', s);
    end
    RT = struct2table(vertcat(rr{:}));
    B.routing.runs = RT;
    B.routing.summary = summariseRouting(RT, algos);

    %% ---------------- Part 2: pipeline benchmark ----------------
    cfgDefs = { ...
        'PID | no compensation',          'pid',         false, 0; ...
        'PID | wind compensation',        'pid',         true,  0; ...
        'PID | wind + lag compensation',  'pid',         true,  1; ...
        'PurePursuit | no compensation',  'purePursuit', false, 0; ...
        'PurePursuit | wind compensation','purePursuit', true,  0; ...
        'PurePursuit | wind + lag comp.', 'purePursuit', true,  1};
    winds = [1.0 2.5]; gusts = [0 0.5]; locs = {'groundTruth', 'flowOdometry', 'kalman'}; delays = [0 0.5];
    if quick, winds = 2.5; locs = {'groundTruth', 'kalman'}; end
    splits = struct('name', {'train', 'test1', 'test2'}, 'fieldSeed', {42, 101, 202}, 'dirDeg', {90, 60, 120}, ...
                    'gustSeed', {7, 17, 27}, 'locSeed', {3, 13, 23});
    if quick, splits = splits(1:2); end
    conds = {};
    for w = winds, for gu = gusts, for li = 1:numel(locs), for de = delays
        conds{end+1} = struct('wind', w, 'gust', gu, 'loc', locs{li}, 'delay', de); %#ok<AGROW>
    end, end, end, end
    B.pipeline.configs = cfgDefs(:, 1);
    B.pipeline.conditions = conds;
    pr = runPipelineSet(cfgDefs, conds, splits, 'gaussian');
    PT = struct2table(vertcat(pr{:}));
    B.pipeline.runs = PT;

    %% ---------------- selection and hypotheses ----------------
    B.selection = analyseSelection(PT, cfgDefs(:, 1), conds);
    B.H1 = rankReversals(PT(PT.split == "train", :), cfgDefs(:, 1), conds);
    B.H3 = interactions(PT(PT.split == "train", :), cfgDefs(:, 1), B.selection.bestFixed);
    % H4: same train runs with the alternative (uncalibrated) wind-stretched kernel
    pr4 = runPipelineSet(cfgDefs, conds, splits(1), 'windStretched');
    PT4 = struct2table(vertcat(pr4{:}));
    B.H4 = kernelRobustness(PT(PT.split == "train", :), PT4, cfgDefs(:, 1), conds);
    B.pipeline.summary = summarisePipelines(PT, cfgDefs(:, 1));
    B.pipeline.pareto = paretoSet(B.pipeline.summary);

    %% ---------------- single-feature ablation (Fully Corrected, train field) ----------------
    B.ablation = featureAblation();

    B.meta.runtime_s = toc(tAll);
    B.meta.nRuns = height(RT) + height(PT) + height(PT4) + height(B.ablation);
    B.report = buildReport(B);

    writetable(RT, fullfile(outDir, 'routing_runs.csv'));
    writetable(B.routing.summary, fullfile(outDir, 'routing_summary.csv'));
    writetable(PT, fullfile(outDir, 'pipeline_runs.csv'));
    writetable(PT4, fullfile(outDir, 'pipeline_runs_altKernel.csv'));
    writetable(B.pipeline.summary, fullfile(outDir, 'pipeline_summary.csv'));
    writetable(B.selection.perTest, fullfile(outDir, 'selection_test.csv'));
    writetable(B.H3.table, fullfile(outDir, 'interactions.csv'));
    writetable(B.ablation, fullfile(outDir, 'feature_ablation.csv'));
    save(fullfile(outDir, 'benchmark.mat'), 'B', '-v7.3');
    fid = fopen(fullfile(outDir, 'benchmark_report.md'), 'w');
    fprintf(fid, '%s\n', B.report{:});
    fclose(fid);
    fprintf('Experiment F done: %d runs in %.1f min -> %s\n', B.meta.nRuns, B.meta.runtime_s / 60, outDir);
end

% =====================================================================================
function pr = runPipelineSet(cfgDefs, conds, splits, kernel)
    pr = {};
    n = 0; total = size(cfgDefs, 1) * numel(conds) * numel(splits);
    for sp = 1:numel(splits)
        S = splits(sp);
        c0 = config(); c0.internal2.enabled = true; c0.internal2.seed = S.fieldSeed;
        fld = quietField(c0);
        for ci = 1:numel(conds)
            C = conds{ci};
            for k = 1:size(cfgDefs, 1)
                c = applyPreset(config(), struct('wind', 1, 'pid', 1, 'comp', cfgDefs{k, 3}, 'windSpeed', C.wind));
                c.internal2.seed = S.fieldSeed;
                c.internal2.wind.dirDeg = S.dirDeg;
                E = c.enhancements;
                E.enableAdvancedPhysics = true;
                for f = {'payload', 'dynamics', 'energy', 'atmosphere', 'actuation', 'safety', 'guidance'}
                    E.(f{1}).enabled = true;
                end
                E.guidance.mode = cfgDefs{k, 2};
                E.actuation.valveDelay_s = C.delay;
                E.actuation.lagCompensation = cfgDefs{k, 4};
                E.actuation.kernel = kernel;
                E.gusts.enabled = C.gust > 0; E.gusts.sigma_mps = max(C.gust, 0.01); E.gusts.seed = S.gustSeed;
                E.localization.enabled = ~strcmp(C.loc, 'groundTruth');
                if E.localization.enabled, E.localization.mode = C.loc; end
                E.localization.seed = S.locSeed;
                c.enhancements = E;
                r = runInternal2Scenario(c, fld, cfgDefs{k, 1});
                m = computeInternal2Metrics(r.cfgEffective, fld, r);
                A = r.advanced;
                pr{end+1, 1} = struct('split', string(S.name), 'kernel', string(kernel), 'config', string(cfgDefs{k, 1}), ...
                    'condIdx', ci, 'wind_mps', C.wind, 'gust_mps', C.gust, 'localization', string(C.loc), 'valveDelay_s', C.delay, ...
                    'targetDepositionPct', m.spray.targetDepositionPct, 'treatmentSuccessPct', 100 * m.spray.treatmentSuccess, ...
                    'offTargetPct', m.spray.offTargetPct, 'onHealthyPct', m.spray.onHealthyPct, 'offFieldPct', A.offFieldPct, ...
                    'recallPct', 100 * m.perception.recall, 'crossRMSE_m', m.survey.crossRMSE, 'estErrRMS_m', A.estErrRMS_m, ...
                    'missionTime_s', r.finalWorld.time, 'energy_Wh', A.energy_Wh, 'batteryLeftPct', A.batteryLeftPct, ...
                    'refills', A.refills, 'lagDisplacement_m', A.lagDisplacement_m, 'boundaryViolationPct', A.boundaryViolationPct, ...
                    'nAdvisories', numel(A.advisories)); %#ok<AGROW>
                n = n + 1;
                if mod(n, 24) == 0, fprintf('pipeline (%s kernel): %d / %d runs\n', kernel, n, total); end
            end
        end
    end
end

function ms = planTimeMs(algo, s, XY)
    reps = 3; t = zeros(reps, 1);
    for i = 1:reps
        tic;
        switch algo
            case {'fixedOrder', 'stage7Return'}, o = (1:size(XY, 1))'; %#ok<NASGU>
            case 'nearestNeighbour', planTreatmentRoute(s, XY);
            otherwise, planRouteAdvanced(s, XY, algo);
        end
        t(i) = toc;
    end
    ms = 1000 * median(t);
end

function T = summariseRouting(RT, algos)
    rows = {};
    nn = RT(RT.algorithm == "nearestNeighbour", :);
    for a = 1:numel(algos)
        X = RT(RT.algorithm == algos{a}, :);
        [~, ia] = ismember(X.fieldSeed, nn.fieldSeed);
        ratio = 100 * (X.geometric_m ./ nn.geometric_m(ia) - 1);
        [gm, gci] = meanCI(X.geometric_m); [fm, fci] = meanCI(X.flown_m); [tm, tci] = meanCI(X.travelTime_s);
        rows{end+1, 1} = struct('algorithm', string(algos{a}), 'nFields', height(X), ...
            'geometric_m', gm, 'geometricCI95_m', gci, 'flown_m', fm, 'flownCI95_m', fci, ...
            'travelTime_s', tm, 'travelTimeCI95_s', tci, 'vsNearestNeighbourPct', mean(ratio), ...
            'planTime_ms', median(X.planTime_ms)); %#ok<AGROW>
    end
    T = struct2table(vertcat(rows{:}));
end

function T = summarisePipelines(PT, names)
    rows = {};
    for k = 1:numel(names)
        for sp = ["train", "test"]
            if sp == "train", X = PT(PT.config == names{k} & PT.split == "train", :);
            else, X = PT(PT.config == names{k} & PT.split ~= "train", :); end
            if isempty(X), continue; end
            [pm, pci] = meanCI(X.targetDepositionPct);
            v = sort(X.targetDepositionPct);
            nw = max(1, ceil(0.1 * numel(v)));
            rows{end+1, 1} = struct('config', string(names{k}), 'split', sp, 'n', height(X), ...
                'targetDepositionPct', pm, 'targetDepositionCI95', pci, 'worstDecilePct', mean(v(1:nw)), ...
                'treatmentSuccessPct', mean(X.treatmentSuccessPct), 'offTargetPct', mean(X.offTargetPct), ...
                'offFieldPct', mean(X.offFieldPct), 'crossRMSE_m', mean(X.crossRMSE_m), ...
                'missionTime_s', mean(X.missionTime_s), 'energy_Wh', mean(X.energy_Wh), ...
                'lagDisplacement_m', mean(X.lagDisplacement_m), 'advisories', mean(X.nAdvisories)); %#ok<AGROW>
        end
    end
    T = struct2table(vertcat(rows{:}));
end

function P = paretoSet(T)
%PARETOSET Non-dominated configurations on TEST means: deposition up, off-field, energy, time down.
    X = T(T.split == "test", :);
    if isempty(X), X = T(T.split == "train", :); end
    obj = [-X.targetDepositionPct, X.offFieldPct, X.energy_Wh, X.missionTime_s];
    nd = true(height(X), 1);
    for i = 1:height(X)
        for j = 1:height(X)
            if i ~= j && all(obj(j, :) <= obj(i, :)) && any(obj(j, :) < obj(i, :)), nd(i) = false; end
        end
    end
    P = X(nd, {'config', 'targetDepositionPct', 'offFieldPct', 'energy_Wh', 'missionTime_s'});
end

function S = analyseSelection(PT, names, conds)
    tr = PT(PT.split == "train", :);
    te = PT(PT.split ~= "train", :);
    % best fixed: highest mean primary over all train conditions
    mu = cellfun(@(n) mean(tr.targetDepositionPct(tr.config == n)), names);
    [~, kb] = max(mu);
    S.bestFixed = string(names{kb});
    S.trainMeans = table(string(names), mu, 'VariableNames', {'config', 'trainMeanDepositionPct'});
    % selector: per condition, the config with the best train value
    sel = strings(numel(conds), 1);
    for ci = 1:numel(conds)
        X = tr(tr.condIdx == ci, :);
        [~, j] = max(X.targetDepositionPct);
        sel(ci) = X.config(j);
    end
    S.selectorChoice = table((1:numel(conds))', sel, 'VariableNames', {'condIdx', 'selected'});
    rows = {};
    for spn = unique(te.split)'
        for ci = 1:numel(conds)
            X = te(te.split == spn & te.condIdx == ci, :);
            if isempty(X), continue; end
            vf = X.targetDepositionPct(X.config == S.bestFixed);
            vs = X.targetDepositionPct(X.config == sel(ci));
            vo = max(X.targetDepositionPct);
            C = conds{ci};
            rows{end+1, 1} = struct('split', spn, 'condIdx', ci, 'wind_mps', C.wind, 'gust_mps', C.gust, ...
                'localization', string(C.loc), 'valveDelay_s', C.delay, 'selected', sel(ci), 'fixedPct', vf, ...
                'selectorPct', vs, 'oraclePct', vo, 'oracleConfig', X.config(find(X.targetDepositionPct == vo, 1))); %#ok<AGROW>
        end
    end
    S.perTest = struct2table(vertcat(rows{:}));
    d = S.perTest.selectorPct - S.perTest.fixedPct;
    S.meanFixed = mean(S.perTest.fixedPct);
    S.meanSelector = mean(S.perTest.selectorPct);
    S.meanOracle = mean(S.perTest.oraclePct);
    S.meanGain = mean(d);
    S.gainCI95 = bootCI(d);
    S.wins = nnz(d > 0.5); S.ties = nnz(abs(d) <= 0.5); S.losses = nnz(d < -0.5);
    S.regretFixed = mean(S.perTest.oraclePct - S.perTest.fixedPct);
    S.regretSelector = mean(S.perTest.oraclePct - S.perTest.selectorPct);
    S.H2supported = S.gainCI95(1) > 0;
end

function H = rankReversals(tr, names, conds)
    tol = 1.0;   % percentage points
    pairs = {};
    for i = 1:numel(names)
        for j = i+1:numel(names)
            d = zeros(numel(conds), 1);
            for ci = 1:numel(conds)
                X = tr(tr.condIdx == ci, :);
                d(ci) = X.targetDepositionPct(X.config == names{i}) - X.targetDepositionPct(X.config == names{j});
            end
            if any(d > tol) && any(d < -tol)
                pairs{end+1, 1} = struct('configA', string(names{i}), 'configB', string(names{j}), ...
                    'conditionsAbetter', nnz(d > tol), 'conditionsBbetter', nnz(d < -tol), 'maxGapPct', max(abs(d))); %#ok<AGROW>
            end
        end
    end
    if isempty(pairs)
        H.table = table(strings(0, 1), strings(0, 1), zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
            'VariableNames', {'configA', 'configB', 'conditionsAbetter', 'conditionsBbetter', 'maxGapPct'});
    else
        H.table = struct2table(vertcat(pairs{:}));
    end
    H.nReversals = height(H.table);
    H.supported = H.nReversals > 0;
    H.tolerancePct = tol;
end

function H = interactions(tr, names, bestFixed)
%INTERACTIONS Main effects and 2-factor interaction contrasts (pp of deposition), averaged over
%   the remaining factors; localization contrast = Kalman vs ground truth. Computed for the best
%   fixed configuration and for the mean over all configurations.
    tr = tr(tr.localization ~= "flowOdometry", :);
    lv.wind = [min(tr.wind_mps), max(tr.wind_mps)]; lv.gust = [0 0.5]; lv.delay = [0 0.5];
    lv.loc = ["groundTruth", "kalman"];
    fac = {'wind', 'gust', 'loc', 'delay'};
    rows = {};
    for subset = ["best fixed", "all configs"]
        if subset == "best fixed", X = tr(tr.config == bestFixed, :); else, X = tr; end
        y = @(mask) mean(X.targetDepositionPct(mask));
        lvl = @(f, i) facMask(X, f, lv, i);
        for a = 1:numel(fac)
            me = y(lvl(fac{a}, 2)) - y(lvl(fac{a}, 1));
            rows{end+1, 1} = struct('subset', subset, 'term', string(fac{a}), 'effectPct', me); %#ok<AGROW>
        end
        for a = 1:numel(fac)
            for b = a+1:numel(fac)
                I = (y(lvl(fac{a}, 2) & lvl(fac{b}, 2)) - y(lvl(fac{a}, 1) & lvl(fac{b}, 2))) ...
                  - (y(lvl(fac{a}, 2) & lvl(fac{b}, 1)) - y(lvl(fac{a}, 1) & lvl(fac{b}, 1)));
                rows{end+1, 1} = struct('subset', subset, 'term', string([fac{a} ' x ' fac{b}]), 'effectPct', I); %#ok<AGROW>
            end
        end
    end
    H.table = struct2table(vertcat(rows{:}));
    t = H.table(H.table.subset == "all configs" & contains(H.table.term, " x "), :);
    H.largestInteraction = t(find(abs(t.effectPct) == max(abs(t.effectPct)), 1), :);
    H.supported = any(abs(t.effectPct) > 2);      % > 2 pp non-additivity
end

function m = facMask(X, f, lv, i)
    switch f
        case 'wind', m = X.wind_mps == lv.wind(i);
        case 'gust', m = X.gust_mps == lv.gust(i);
        case 'delay', m = X.valveDelay_s == lv.delay(i);
        case 'loc', m = X.localization == lv.loc(i);
    end
end

function H = kernelRobustness(trG, trS, names, conds)
    mG = cellfun(@(n) mean(trG.targetDepositionPct(trG.config == n)), names);
    mS = cellfun(@(n) mean(trS.targetDepositionPct(trS.config == n)), names);
    H.configMeans = table(string(names), mG, mS, 'VariableNames', {'config', 'gaussianPct', 'windStretchedPct'});
    H.spearman = spearman(mG, mS);
    [~, bg] = max(mG); [~, bs] = max(mS);
    H.sameBestFixed = bg == bs;
    agree = 0;
    for ci = 1:numel(conds)
        XG = trG(trG.condIdx == ci, :); XS = trS(trS.condIdx == ci, :);
        [~, a] = max(XG.targetDepositionPct); [~, b] = max(XS.targetDepositionPct);
        agree = agree + (XG.config(a) == XS.config(b));
    end
    H.selectorAgreementPct = 100 * agree / numel(conds);
    H.supported = H.spearman > 0.8 && H.sameBestFixed;
end

function T = featureAblation()
    base = applyPreset(config(), 'Fully Corrected');
    fld = quietField(base);
    feats = advFeatures();
    rows = {};
    r = runInternal2Scenario(base, fld, 'x'); m = computeInternal2Metrics(base, fld, r);
    rows{end+1, 1} = abl("original", m);
    for i = 1:numel(feats)
        c = base; c.enhancements.enableAdvancedPhysics = true; c.enhancements.(feats{i}).enabled = true;
        if strcmp(feats{i}, 'localization'), c.enhancements.localization.mode = 'kalman'; end
        if strcmp(feats{i}, 'guidance'), c.enhancements.guidance.mode = 'purePursuit'; end
        r = runInternal2Scenario(c, fld, 'x'); m = computeInternal2Metrics(r.cfgEffective, fld, r);
        rows{end+1, 1} = abl(string(feats{i}), m); %#ok<AGROW>
    end
    c = base; c.enhancements.enableAdvancedPhysics = true;
    for i = 1:numel(feats), c.enhancements.(feats{i}).enabled = true; end
    c.enhancements.localization.mode = 'kalman';
    r = runInternal2Scenario(c, fld, 'x'); m = computeInternal2Metrics(r.cfgEffective, fld, r);
    rows{end+1, 1} = abl("ALL features", m);
    T = struct2table(vertcat(rows{:}));
end

function s = abl(name, m)
    s = struct('feature', name, 'targetDepositionPct', m.spray.targetDepositionPct, ...
        'treatmentSuccessPct', 100 * m.spray.treatmentSuccess, 'offTargetPct', m.spray.offTargetPct, ...
        'crossRMSE_m', m.survey.crossRMSE, 'recallPct', 100 * m.perception.recall);
end

function L = buildReport(B)
    S = B.selection; RS = B.routing.summary; PS = B.pipeline.summary;
    L = {};
    L{end+1} = '# Experiment F - algorithm benchmark and scenario-conditioned selection';
    L{end+1} = sprintf('Run %s, %d simulated missions, %.1f min (MATLAB %s)%s.', B.meta.date, B.meta.nRuns, ...
        B.meta.runtime_s / 60, B.meta.matlab, ternary(B.meta.quick, ' - QUICK smoke version', ''));
    L{end+1} = 'All numbers are SIMULATED with UNCALIBRATED, assumed parameters: relative comparisons only.';
    L{end+1} = ['Primary metric (pre-specified): ' B.meta.primaryMetric '.'];
    L{end+1} = '';
    L{end+1} = '## Routing (frozen all-diseased targets, equal speed)';
    [~, ib] = min(RS.geometric_m);
    L{end+1} = sprintf('- Shortest route: %s, %.1f m mean (%.1f%% vs nearest-neighbour) over %d fields.', ...
        RS.algorithm(ib), RS.geometric_m(ib), RS.vsNearestNeighbourPct(ib), RS.nFields(ib));
    for i = 1:height(RS)
        L{end+1} = sprintf('  - %-22s geometric %6.1f +- %4.1f m | flown %6.1f m | travel %5.1f s | %+5.1f%% vs NN | plan %.1f ms', ...
            RS.algorithm(i), RS.geometric_m(i), RS.geometricCI95_m(i), RS.flown_m(i), RS.travelTime_s(i), ...
            RS.vsNearestNeighbourPct(i), RS.planTime_ms(i)); %#ok<AGROW>
    end
    L{end+1} = '';
    L{end+1} = '## Pipelines (train / held-out test means)';
    for i = 1:height(PS)
        L{end+1} = sprintf('  - %-32s %-5s deposition %5.1f +- %4.1f%% (worst decile %5.1f%%) | treated %5.1f%% | off-field %4.1f%% | %5.1f Wh | %5.0f s', ...
            PS.config(i), PS.split(i), PS.targetDepositionPct(i), PS.targetDepositionCI95(i), PS.worstDecilePct(i), ...
            PS.treatmentSuccessPct(i), PS.offFieldPct(i), PS.energy_Wh(i), PS.missionTime_s(i)); %#ok<AGROW>
    end
    L{end+1} = sprintf('- Pareto-optimal on test (deposition, off-field, energy, time): %s.', strjoin(B.pipeline.pareto.config, '; '));
    L{end+1} = '';
    L{end+1} = '## Hypotheses';
    L{end+1} = sprintf('- H1 rank reversal: %s - %d configuration pair(s) swap order between conditions (> %.0f pp).', ...
        supp(B.H1.supported), B.H1.nReversals, B.H1.tolerancePct);
    L{end+1} = sprintf(['- H2 selector beats best fixed on held-out tests: %s - best fixed "%s" %.1f%%, selector %.1f%%, ' ...
        'oracle %.1f%%; gain %+.2f pp (95%% bootstrap CI %+.2f..%+.2f), wins/ties/losses %d/%d/%d; regret vs oracle %.2f -> %.2f pp.'], ...
        supp(S.H2supported), S.bestFixed, S.meanFixed, S.meanSelector, S.meanOracle, S.meanGain, S.gainCI95(1), S.gainCI95(2), ...
        S.wins, S.ties, S.losses, S.regretFixed, S.regretSelector);
    li = B.H3.largestInteraction;
    L{end+1} = sprintf('- H3 interactions: %s - largest two-factor interaction %s = %+.1f pp (all configs).', ...
        supp(B.H3.supported), li.term, li.effectPct);
    L{end+1} = sprintf(['- H4 robustness to an alternative (uncalibrated) spray kernel: %s - Spearman %.2f between ' ...
        'configuration rankings, same best fixed: %s, selector choices agree in %.0f%% of conditions.'], ...
        supp(B.H4.supported), B.H4.spearman, yesno(B.H4.sameBestFixed), B.H4.selectorAgreementPct);
    L{end+1} = '';
    L{end+1} = '## Single-feature ablation (Fully Corrected, one feature at a time)';
    for i = 1:height(B.ablation)
        L{end+1} = sprintf('  - %-14s deposition %5.1f%% | treated %5.1f%% | cross-track %.3f m', B.ablation.feature(i), ...
            B.ablation.targetDepositionPct(i), B.ablation.treatmentSuccessPct(i), B.ablation.crossRMSE_m(i)); %#ok<AGROW>
    end
    L{end+1} = '';
    L{end+1} = '## Claim boundaries';
    L{end+1} = '- Simulation-based decision support only: no field validation, no agronomic efficacy.';
    L{end+1} = '- Not GPS-denied validated: the Kalman mode is a linear position filter on modelled sensors.';
    L{end+1} = '- Deposition kernels are uncalibrated; the disease classifier is parametric (teammate CNN not integrated).';
    L{end+1} = '- "Best" is conditional on these scenarios; novelty of scenario-conditioned selection is NOT established.';
end

function [m, ci] = meanCI(x)
    x = x(:); n = numel(x); m = mean(x);
    if n < 2, ci = NaN; return; end
    ci = tcrit(n - 1) * std(x) / sqrt(n);
end

function t = tcrit(df)
    tab = [12.706 4.303 3.182 2.776 2.571 2.447 2.365 2.306 2.262 2.228 2.201 2.179 2.160 2.145 2.131 ...
           2.120 2.110 2.101 2.093 2.086 2.080 2.074 2.069 2.064 2.060 2.056 2.052 2.048 2.045 2.042];
    if df <= numel(tab), t = tab(df); else, t = 1.96; end
end

function ci = bootCI(d)
    rs = RandStream('mt19937ar', 'Seed', 2026);
    n = numel(d); Bn = 10000;
    idx = randi(rs, n, n, Bn);
    bm = mean(d(idx), 1);
    bm = sort(bm);
    ci = [bm(max(1, round(0.025 * Bn))), bm(round(0.975 * Bn))];
end

function r = spearman(a, b)
    ra = rankAvg(a); rb = rankAvg(b);
    c = corrcoef(ra, rb); r = c(1, 2);
end

function r = rankAvg(x)
    [~, ~, ic] = unique(x(:));
    [~, o] = sort(x(:)); r = zeros(numel(x), 1); r(o) = 1:numel(x);
    for u = unique(ic)'
        m = ic == u; r(m) = mean(r(m));
    end
end

function s = supp(b), if b, s = 'SUPPORTED'; else, s = 'NOT SUPPORTED'; end, end
function s = yesno(b), if b, s = 'yes'; else, s = 'no'; end, end
function v = ternary(c, a, b), if c, v = a; else, v = b; end, end

function f = quietField(c)
    evalc('f = generateIrregularField(c);');
end
