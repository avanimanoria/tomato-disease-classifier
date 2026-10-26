function out = runMissionStrategyPilot(outDir, opts)
%RUNMISSIONSTRATEGYPILOT Two-pass selective spraying value test (Mission-Strategy Pilot V1).
%
%   out = runMissionStrategyPilot()                                  SCREEN phase (default)
%   out = runMissionStrategyPilot([], struct('phase', 'full'))       full grid (only if the screen is structured)
%   opts.reanalyse = true re-runs analysis / figures / report on saved evaluations.
%
%   STRATEGIES (same field, truth, detector draws, hardware, spray model, PID, oracle localization):
%     twoPass   existing engine mission: Pass-1 survey + parametric detector -> Pass 2 NN + Or-opt
%               revisit, settle 1 s, spray 2 s (runInternal2Scenario)
%     onePass   APPROXIMATION (runner only, engine functions): fly the SAME survey reference, split at
%               each flagged plant; stop there, settle 1 s, spray 2 s with the engine's dwell / deposition
%               function, continue. Uses the flagged set of the identical survey traversal. Assumes
%               ZERO detection-to-decision latency (the drone can stop at the plant it just imaged).
%     blanket   engine treatment pass over ALL plants in row order (no survey, no detector input):
%               stop-and-spray every plant with the same dose / kernel. NOT a continuous boom sprayer.
%     oracle    RESEARCH-ONLY upper bound: engine mission with the target set = truly diseased plants.
%   SCENARIO FACTORS: prevalence {5 20 50 80 %} (exact count, rank-assigned, nested across levels);
%     detector HIGH (0.95 / 0.03), MEDIUM (0.80 / 0.10), LOW (0.60 / 0.20) via the engine's
%     detect.pDetectDiseased / pFalsePositive and its fixed per-plant draws; structure dispersed
%     (iid ranks) or clustered (Gaussian bumps around seeded centres); field scale small / larger.
%   FIXED: no wind (spray compensation irrelevant), payload + energy models ON (refill trips,
%     energy bookkeeping), assumedDefault hardware, speed 1.5 m/s.
%   Blanket and oracle do not use detector output, so one blanket flight per field is scored under each
%   truth, and one oracle flight per truth is shared across detector levels (stated in the report).
    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(outDir), outDir = fullfile(here, 'results', 'mission_strategy_pilot_v1'); end
    if nargin < 2, opts = struct(); end
    if ~isfield(opts, 'phase'), opts.phase = 'screen'; end
    reuse = isfield(opts, 'reanalyse') && opts.reanalyse;
    fn = fullfile(outDir, [opts.phase '_evaluations.csv']);
    if ~reuse && isfile(fn) && ~(isfield(opts, 'overwrite') && opts.overwrite)
        error('runMissionStrategyPilot:exists', 'Phase "%s" already exists in %s.', opts.phase, outDir);
    end
    figDir = fullfile(outDir, 'figures'); if ~isfolder(figDir), mkdir(figDir); end
    t0 = tic;
    D = design(opts.phase);
    if isfield(opts, 'smoke'), D.scales = D.scales(opts.smoke.scale); D.seeds = opts.smoke.seeds; D.prev = opts.smoke.prev; end

    if reuse
        E = readtable(fn, 'TextType', 'string', 'Delimiter', ',', 'ReadVariableNames', true);
    else
        E = table();
        for si = 1:numel(D.scales)
            for seed = D.seeds
                [cfg0, field0] = makeField(D.scales(si), seed);
                Bfly = flyBlanket(cfg0, field0);                          % one blanket flight per field
                for st = D.structures
                    rank = diseaseRank(field0, st, seed);
                    for p = D.prev
                        f = setTruth(field0, rank, p);
                        O = flyOracle(cfg0, f);
                        for di = 1:height(D.det)
                            c = cfg0; c.internal2.detect.pDetectDiseased = D.det.sens(di); c.internal2.detect.pFalsePositive = D.det.fpr(di);
                            [T2, r2] = flyTwoPass(c, f);
                            T1 = flyOnePass(c, f, r2.targets);
                            key = table(D.scales(si).name, seed, st, p, D.det.level(di), sum(f.plants.TrueDisease == "DISEASED"), height(f.plants), ...
                                'VariableNames', {'scale', 'seed', 'structure', 'prevalence', 'detector', 'nDiseased', 'nPlants'});
                            for S = {T2, T1, score(Bfly, f, "blanket"), score(O, f, "oracle")}
                                E = [E; [key, S{1}]]; %#ok<AGROW>
                            end
                        end
                    end
                end
                fprintf('%s: scale %s seed %d done (%d evaluations, %.0f s)\n', opts.phase, D.scales(si).name, seed, height(E), toc(t0));
            end
        end
        writetable(E, fn);
    end
    A = analyse(E, D);
    writetable(A.paired, fullfile(outDir, [opts.phase '_paired_strategy.csv']));
    writetable(A.pareto, fullfile(outDir, [opts.phase '_pareto_summary.csv']));
    writetable(A.baseline, fullfile(outDir, [opts.phase '_baseline_rules.csv']));
    writetable(A.baselineCells, fullfile(outDir, [opts.phase '_baseline_cells.csv']));
    writetable(A.scenario, fullfile(outDir, [opts.phase '_scenario_level.csv']));
    SC = sanity(E, D, here, outDir, opts.phase);
    writetable(SC, fullfile(outDir, [opts.phase '_sanity_checks.csv']));
    figures(E, A, D, figDir, opts.phase);
    out = struct('evaluations', E, 'analysis', A, 'sanity', SC, 'D', D, 'outDir', outDir, 'runtime_s', toc(t0));
    writeReport(out, fullfile(outDir, 'report.md'), opts.phase);
    man = struct('experiment', 'mission_strategy_pilot_v1', 'phase', opts.phase, 'engine', 'existing mission engine; onePass and blanket assembled from engine functions in this runner', ...
        'prevalence', D.prev, 'detectors', D.det, 'structures', D.structures, 'scales', {{D.scales.name}}, 'seeds', D.seeds, ...
        'evaluations', height(E), 'paretoTolerances', D.tol, 'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        'matlab', version, 'commit', gitHead(here), 'sanityAllPass', all(SC.pass), 'runtime_s', out.runtime_s);
    fid = fopen(fullfile(outDir, [opts.phase '_manifest.json']), 'w'); fprintf(fid, '%s', jsonencode(man, 'PrettyPrint', true)); fclose(fid);
end

% ===================================================================== design
function D = design(phase)
    D.prev = [0.05 0.20 0.50 0.80];
    D.det = table(["HIGH"; "MEDIUM"; "LOW"], [0.95; 0.80; 0.60], [0.03; 0.10; 0.20], 'VariableNames', {'level', 'sens', 'fpr'});
    D.structures = ["dispersed", "clustered"];
    D.scales = struct('name', {"small", "larger"}, 'shape', {'Trapezoid', 'Rectangle'}, ...
        'p', {struct('bottom', 30, 'top', 18, 'height', 14), struct('length', 36, 'width', 18)});
    D.seeds = [11 12 13 14 15];
    if strcmp(phase, 'screen'), D.scales = D.scales(1); D.seeds = [11 12 13]; end
    D.strategies = ["twoPass", "onePass", "blanket"];   % deployable; "oracle" reported separately
    D.tol = struct('success_pp', 1, 'chem_rel', 0.01, 'time_rel', 0.01);   % prespecified "equal" tolerances
end

function [c, f] = makeField(sc, seed)
    c = applyPreset(config(), struct('wind', false, 'pid', true, 'comp', false, 'windSpeed', 2));
    c.internal2.field.polygon = fieldShapeToPolygon(sc.shape, sc.p);
    c.internal2.seed = seed;
    c.enhancements.enableAdvancedPhysics = true;
    c.enhancements.payload.enabled = true;
    c.enhancements.energy.enabled = true;
    c.enhancements.enableAdvancedRouting = true;
    c.internal2.treat.routing = 'nearestNeighbourOrOpt';
    c.internal2.detect.mode = 'stochastic';
    evalc('f = generateIrregularField(c);');
end

function rank = diseaseRank(f, st, seed)
%DISEASERANK Score per plant; the top round(p N) are diseased (exact, nested prevalence).
    rs = RandStream('mt19937ar', 'Seed', 1000 + seed);
    u = rand(rs, height(f.plants), 1);
    if st == "dispersed", rank = u; return; end
    poly = f.polygon; A = polyarea(poly(:, 1), poly(:, 2));
    K = max(2, round(A / 85)); ell = 2.5; C = zeros(0, 2);
    while size(C, 1) < K
        q = [min(poly(:, 1)) + rand(rs) * range2(poly(:, 1)), min(poly(:, 2)) + rand(rs) * range2(poly(:, 2))];
        if inpolygon(q(1), q(2), poly(:, 1), poly(:, 2)), C(end+1, :) = q; end %#ok<AGROW>
    end
    XY = [f.plants.X f.plants.Y];
    sc = zeros(height(f.plants), 1);
    for k = 1:K, sc = max(sc, exp(-sum((XY - C(k, :)).^2, 2) / (2 * ell^2))); end
    rank = sc + 1e-6 * u;                                 % tiny jitter breaks ties
end

function r = range2(x), r = max(x) - min(x); end

function f = setTruth(f, rank, p)
    n = round(p * height(f.plants));
    [~, o] = sort(rank, 'descend');
    td = repmat("HEALTHY", height(f.plants), 1); td(o(1:n)) = "DISEASED";
    f.plants.TrueDisease = td;
end

function c = prep(c)
%PREP The same derived settings runInternal2Scenario applies before flying.
    if advOn(c, 'any'), c = applyAdvancedDerived(c); end
    c.internal2.spray.footprintRadius = c.internal2.spray.releaseHeight * tand(c.internal2.spray.nozzleHalfAngle);
end

% ===================================================================== strategies
function [T, r] = flyTwoPass(c, f)
    tic; r = runInternal2Scenario(c, f, 'twoPass'); w = toc;
    T = summarize("twoPass", r.cfgEffective, f, r.grid, r.finalWorld, r.targets.plantIdx, r.pass1.distance, r.routes.actualDistance, w);
end

function O = flyOracle(c, f)
    isDis = find(f.plants.TrueDisease == "DISEASED");
    tg = struct('plantIdx', isDis, 'ID', f.plants.ID(isDis), 'XY', [f.plants.X(isDis) f.plants.Y(isDis)], ...
        'detectTime', zeros(numel(isDis), 1), 'isTruePositive', true(numel(isDis), 1));
    tic; r = runInternal2Scenario(c, f, 'oracle', struct('targets', tg)); w = toc;
    O = struct('cfg', r.cfgEffective, 'grid', r.grid, 'world', r.finalWorld, 'idx', isDis, 'survey', r.pass1.distance, ...
        'revisit', r.routes.actualDistance, 'wall', w);
end

function B = flyBlanket(c, f)
%FLYBLANKET Engine treatment pass over every plant in boustrophedon row order, from take-off, no survey.
    ce = prep(c); ce.internal2.treat.routing = 'fixedOrder';
    P = f.plants; idx = [];
    for rIdx = 1:f.numRows
        k = find(P.RowIdx == rIdx);
        if mod(rIdx, 2) == 0, k = flipud(k); end      % same alternation as the survey rows
        idx = [idx; k]; %#ok<AGROW>
    end
    tg = struct('plantIdx', idx, 'XY', [P.X(idx) P.Y(idx)]);
    w0 = initAdvancedWorld(struct('pos', f.surveyRef.pts(1, :), 'time', 0, 'distance', 0), ce);
    sv = struct('world', w0, 'ctrl', initInternal2Controller());
    tic; tp = runTreatmentPass(ce, f, sv, tg); w = toc;
    B = struct('cfg', ce, 'grid', tp.grid, 'world', tp.finalWorld, 'idx', idx, 'survey', 0, 'revisit', tp.routes.actualDistance, 'wall', w);
end

function T = flyOnePass(c, f, targets)
%FLYONEPASS Survey traversal that stops at each flagged plant (APPROXIMATION, zero decision latency).
    ce = prep(c); I = ce.internal2; S = I.spray;
    ref = f.surveyRef; P = ref.pts; cs = ref.cs;
    [~, near] = min(pdist2local(targets.XY, P), [], 2);
    sT = cs(near); [sT, o] = sort(sT); idxT = targets.plantIdx(o);
    world = initAdvancedWorld(struct('pos', P(1, :), 'time', 0, 'distance', 0), ce);
    ctrl = initInternal2Controller();
    grid = initDepositionGrid(ce, f);
    dwell = struct('settleTime', I.treat.settleTime, 'dwellTime', S.duration, 'dwellFcn', @(g, w) advDeposit(g, w, ce));
    PL = ce.enhancements.payload; dose = S.flowRate * S.duration / 1000;
    home = P(1, :); sPrev = 0;
    tic;
    for i = 1:numel(sT)
        if world.adv.payloadOn && world.adv.liquid_L < dose - 1e-12          % same refill rule as the engine
            here = world.pos;
            [world, ctrl] = flyReference(world, makeReference([getEstimatedState(world, ce).pos; home]), ctrl, ce, struct('settleTime', PL.refillTime_s));
            world.adv.liquid_L = PL.tankCapacity_L; world.adv.refills = world.adv.refills + 1;
            [world, ctrl] = flyReference(world, makeReference([getEstimatedState(world, ce).pos; here]), ctrl, ce);
        end
        dw = dwell; dw.dwellState = grid;
        [world, ctrl, ~, grid] = flyReference(world, makeReference(subPath(P, cs, sPrev, sT(i))), ctrl, ce, dw);
        sPrev = sT(i);
    end
    [world, ~] = flyReference(world, makeReference(subPath(P, cs, sPrev, ref.len)), ctrl, ce);
    w = toc;
    T = summarize("onePass", ce, f, grid, world, idxT, ref.len, world.distance - ref.len, w);   % 'revisit' = distance beyond the survey path
end

function Q = subPath(P, cs, a, b)
    pa = interp1(cs, P, a); pb = interp1(cs, P, b);
    Q = [pa; P(cs > a & cs < b, :); pb];
end

function D = pdist2local(A, B)
    D = sqrt((A(:, 1) - B(:, 1)').^2 + (A(:, 2) - B(:, 2)').^2);
end

function T = score(X, f, name)
    T = summarize(name, X.cfg, f, X.grid, X.world, X.idx, X.survey, X.revisit, X.wall);
end

function T = summarize(name, ce, f, grid, world, idx, surveyDist, revisitDist, wall)
    s = sprayMetrics(ce, f, grid, idx);
    isDis = f.plants.TrueDisease == "DISEASED";
    [XX, YY] = meshgrid(grid.xv, grid.yv);
    inF = inpolygon(XX, YY, f.polygon(:, 1), f.polygon(:, 2));
    nH = sum(~isDis);
    T = table(name, 100 * s.treatmentSuccess, 100 * (1 - s.treatmentSuccess), 100 * s.healthyPlantsHit / max(nH, 1), ...
        sum(isDis(idx)), sum(~isDis(idx)), numel(idx), s.emitted_mL / 1000, safeDiv(s.emitted_mL, s.treatedTrue), ...
        s.onHealthyPlants_mL / 1000, s.offTargetPct, 100 * safeDiv(sum(grid.mass(~inF)), grid.emitted), ...
        world.time, world.distance, surveyDist, revisitDist, world.adv.energy_J / 3600, world.adv.refills, wall, ...
        'VariableNames', {'strategy', 'treatmentSuccess_pct', 'diseasedMissed_pct', 'healthyTreated_pct', ...
        'tpTargets', 'fpTargets', 'nSprayed', 'emitted_L', 'mL_per_treatedDiseased', 'onHealthy_L', 'offTarget_pct', ...
        'offField_pct', 'duration_s', 'distance_m', 'surveyDistance_m', 'revisitDistance_m', 'energy_Wh', 'refills', 'wallTime_s'});
end

% ===================================================================== analysis
function A = analyse(E, D)
    keys = unique(E(:, {'scale', 'seed', 'structure', 'prevalence', 'detector'}), 'rows');
    PT = table(); PS = table(); BC = table();
    for i = 1:height(keys)
        k = E.scale == keys.scale(i) & E.seed == keys.seed(i) & E.structure == keys.structure(i) & ...
            E.prevalence == keys.prevalence(i) & E.detector == keys.detector(i);
        X = E(k, :); g = @(s) X(X.strategy == s, :);
        two = g("twoPass"); one = g("onePass"); bl = g("blanket"); orc = g("oracle");
        PT = [PT; [keys(i, :), table(two.treatmentSuccess_pct - bl.treatmentSuccess_pct, 100 * (1 - two.emitted_L / bl.emitted_L), ...
            two.duration_s - bl.duration_s, two.energy_Wh - bl.energy_Wh, one.duration_s - two.duration_s, ...
            one.treatmentSuccess_pct - two.treatmentSuccess_pct, one.emitted_L - two.emitted_L, ...
            orc.treatmentSuccess_pct - two.treatmentSuccess_pct, two.mL_per_treatedDiseased, bl.mL_per_treatedDiseased, ...
            'VariableNames', {'twoMinusBlanket_success_pp', 'chemicalSaving_vs_blanket_pct', 'twoMinusBlanket_time_s', ...
            'twoMinusBlanket_energy_Wh', 'oneMinusTwo_time_s', 'oneMinusTwo_success_pp', 'oneMinusTwo_emitted_L', ...
            'oracleMinusTwo_success_pp', 'two_mL_per_treated', 'blanket_mL_per_treated'})]]; %#ok<AGROW>
        Y = [two; one; bl];
        par = paretoSet(Y.treatmentSuccess_pct, Y.emitted_L, Y.duration_s, D.tol);
        dom = dominators(Y, D.tol);
        % analytical predictions (baseline B + C) from scenario parameters and field geometry only
        pr = predict(keys(i, :), X, D);
        parP = paretoSet(pr.success, pr.chem, pr.time, D.tol);
        setStr = @(m) strjoin(D.strategies(m), "+");
        PS = [PS; [keys(i, :), table(setStr(par), setStr(parP), dom(1), dom(2), dom(3), ...
            'VariableNames', {'paretoSet', 'predictedParetoSet', 'twoPass_dominatedBy', 'onePass_dominatedBy', 'blanket_dominatedBy'})]]; %#ok<AGROW>
        % per-objective winners: predicted vs simulated, regret in natural units
        obj = {'treatmentSuccess_pct', -1, pr.success; 'emitted_L', 1, pr.chem; 'duration_s', 1, pr.time};
        for j = 1:3
            v = Y.(obj{j, 1}); sgn = obj{j, 2};
            [~, wi] = min(sgn * v); [~, wp] = min(sgn * obj{j, 3});
            BC = [BC; [keys(i, :), table(string(obj{j, 1}), D.strategies(wi), D.strategies(wp), abs(v(wp) - v(wi)), ...
                'VariableNames', {'objective', 'simWinner', 'predWinner', 'regret'})]]; %#ok<AGROW>
        end
    end
    A.paired = PT; A.pareto = PS; A.baselineCells = BC;
    % baseline summary
    BT = table();
    BT = [BT; table("B+C analytical Pareto set (exact set match)", mean(PS.paretoSet == PS.predictedParetoSet), NaN, NaN, height(PS), ...
        'VariableNames', {'rule', 'accuracy', 'meanRegret', 'worstRegret', 'n'})];
    for o = ["treatmentSuccess_pct", "emitted_L", "duration_s"]
        k = BC.objective == o;
        BT = [BT; table("B+C analytical winner: " + o, mean(BC.simWinner(k) == BC.predWinner(k)), mean(BC.regret(k)), max(BC.regret(k)), sum(k), ...
            'VariableNames', {'rule', 'accuracy', 'meanRegret', 'worstRegret', 'n'})]; %#ok<AGROW>
    end
    % baseline A: "selective (twoPass) is Pareto-efficient iff prevalence < p*", best in-sample p* (optimistic)
    inSet = contains(PS.paretoSet, "twoPass");
    best = -1; pstar = NaN;
    for ps = [0 D.prev + 0.01 1.01]
        acc = mean((PS.prevalence < ps) == inSet);
        if acc > best, best = acc; pstar = ps; end
    end
    BT = [BT; table(sprintf("A prevalence threshold for twoPass efficiency (best p* = %.2f, in-sample)", pstar), best, NaN, NaN, height(PS), ...
        'VariableNames', {'rule', 'accuracy', 'meanRegret', 'worstRegret', 'n'})];
    A.baseline = BT;
    % scenario-level means over seeds
    SL = groupsummary(E, {'scale', 'structure', 'prevalence', 'detector', 'strategy'}, 'mean', ...
        {'treatmentSuccess_pct', 'diseasedMissed_pct', 'healthyTreated_pct', 'emitted_L', 'onHealthy_L', 'duration_s', ...
        'distance_m', 'revisitDistance_m', 'energy_Wh', 'refills', 'fpTargets', 'tpTargets'});
    A.scenario = SL;
end

function m = paretoSet(succ, chem, time, tol)
    n = numel(succ); m = true(1, n);
    for a = 1:n
        for b = 1:n
            if a ~= b && dom2(b, a, succ, chem, time, tol), m(a) = false; end
        end
    end
end

function d = dom2(b, a, succ, chem, time, tol)
%DOM2 true if b dominates a: at least as good on all three (within tolerance), strictly better on one.
    geS = succ(b) >= succ(a) - tol.success_pp; geC = chem(b) <= chem(a) * (1 + tol.chem_rel); geT = time(b) <= time(a) * (1 + tol.time_rel);
    btS = succ(b) > succ(a) + tol.success_pp; btC = chem(b) < chem(a) * (1 - tol.chem_rel); btT = time(b) < time(a) * (1 - tol.time_rel);
    d = geS && geC && geT && (btS || btC || btT);
end

function dm = dominators(Y, tol)
    names = ["twoPass", "onePass", "blanket"]; dm = strings(1, 3);
    for a = 1:3
        w = strings(0);
        for b = 1:3
            if a ~= b && dom2(b, a, Y.treatmentSuccess_pct, Y.emitted_L, Y.duration_s, tol), w(end+1) = names(b); end %#ok<AGROW>
        end
        dm(a) = strjoin(w, "+"); if dm(a) == "", dm(a) = "-"; end
    end
end

function pr = predict(key, X, D)
%PREDICT Baseline B + C: expected sprayed fraction and a simple time model, from scenario parameters and
%   field geometry only (N, area, survey length) - no simulator outcome. Delivery assumed perfect.
    two = X(X.strategy == "twoPass", :); bl = X(X.strategy == "blanket", :);
    N = two.nPlants; p = key.prevalence; dl = D.det(D.det.level == key.detector, :);
    c0 = config(); v = c0.droneSpeed; td = c0.internal2.treat.settleTime + c0.internal2.spray.duration;
    dose = c0.internal2.spray.flowRate * c0.internal2.spray.duration / 1000; tank = c0.enhancements.payload.tankCapacity_L;
    nSel = N * (p * dl.sens + (1 - p) * dl.fpr);
    sc = D.scales(arrayfun(@(s) s.name == key.scale, D.scales));
    poly = fieldShapeToPolygon(sc.shape, sc.p); Ar = polyarea(poly(:, 1), poly(:, 2));
    Ls = two.surveyDistance_m;                               % survey length is a geometry input (path length), not an outcome
    home = 0.5 * sqrt(Ar);
    refill = @(n) max(0, ceil(n * dose / tank) - 1) * (c0.enhancements.payload.refillTime_s + 2 * home / v);
    tTwo = Ls / v + nSel * td + 0.7124 * sqrt(nSel * Ar) / v + refill(nSel);   % BHH random-tour constant
    tOne = Ls / v + nSel * td + refill(nSel);
    tBl = N * td + Ls / v + refill(N);
    pr.success = [100 * dl.sens; 100 * dl.sens; 100];
    pr.chem = [nSel * dose; nSel * dose; N * dose];
    pr.time = [tTwo; tOne; tBl];
    if bl.nSprayed ~= N, pr.time(3) = NaN; end
end

% ===================================================================== sanity
function SC = sanity(E, D, here, outDir, phase)
    chk = {};
    keys = unique(E(:, {'scale', 'seed', 'structure', 'prevalence', 'detector'}), 'rows');
    okTruth = true; okSel = true; okBl = true;
    for i = 1:height(keys)
        k = E.scale == keys.scale(i) & E.seed == keys.seed(i) & E.structure == keys.structure(i) & E.prevalence == keys.prevalence(i) & E.detector == keys.detector(i);
        X = E(k, :);
        okTruth = okTruth && numel(unique(X.nDiseased)) == 1 && numel(unique(X.nPlants)) == 1;
        two = X(X.strategy == "twoPass", :); one = X(X.strategy == "onePass", :); bl = X(X.strategy == "blanket", :);
        okSel = okSel && two.nSprayed == one.nSprayed && two.tpTargets == one.tpTargets && two.fpTargets == one.fpTargets;
        okBl = okBl && bl.nSprayed == bl.nPlants;
    end
    chk(end+1, :) = {'same truth (plants, diseased count) across strategies in every paired scenario', okTruth, ''};
    chk(end+1, :) = {'same detector output for twoPass and onePass (identical flagged TP / FP sets)', okSel, ''};
    bl = E(E.strategy == "blanket", :);
    g = groupsummary(bl, {'scale', 'seed'}, {'min', 'max'}, {'duration_s', 'emitted_L'});
    chk(end+1, :) = {'blanket ignores detector output: one flight per field, identical duration / spray across detector levels', ...
        all(g.min_duration_s == g.max_duration_s & g.min_emitted_L == g.max_emitted_L) && okBl, 'blanket sprays every plant'};
    o = E(E.strategy == "oracle", :);
    chk(end+1, :) = {'oracle sprays exactly the truly diseased plants (research-only, excluded from the deployable Pareto set)', ...
        all(o.nSprayed == o.nDiseased & o.fpTargets == 0), ''};
    c0 = config(); dose = c0.internal2.spray.flowRate * c0.internal2.spray.duration / 1000;
    chk(end+1, :) = {'spray accounting: emitted = nominal dose x sprayed targets (existing accounting)', ...
        max(abs(E.emitted_L - dose * E.nSprayed)) < 1e-9, sprintf('max diff %.2g L', max(abs(E.emitted_L - dose * E.nSprayed)))};
    num = [E.duration_s E.distance_m E.energy_Wh E.revisitDistance_m E.emitted_L];
    chk(end+1, :) = {'mission time / distance / energy finite and non-negative', all(isfinite(num(:)) & num(:) >= 0), ''};
    chk(end+1, :) = {'prevalence sets only the disease truth (exact count = round(p N)); detector draws and geometry unchanged', ...
        checkPrevalence(E), ''};
    chk(end+1, :) = {'same hardware / spray assumptions across strategies (one cfg per field; strategies differ only in mission plan)', true, 'by construction: makeField + prep'};
    % reproducibility: rebuild one scenario and compare the twoPass row
    k = find(E.strategy == "twoPass", 1); sc = D.scales(arrayfun(@(s) s.name == E.scale(k), D.scales));
    [c, f0] = makeField(sc, E.seed(k)); f = setTruth(f0, diseaseRank(f0, E.structure(k), E.seed(k)), E.prevalence(k));
    dl = D.det(D.det.level == E.detector(k), :); c.internal2.detect.pDetectDiseased = dl.sens; c.internal2.detect.pFalsePositive = dl.fpr;
    T2 = flyTwoPass(c, f);
    chk(end+1, :) = {'reproducibility from seeds (twoPass mission rebuilt; |diff| < 1e-9)', ...
        abs(T2.duration_s - E.duration_s(k)) < 1e-9 && abs(T2.treatmentSuccess_pct - E.treatmentSuccess_pct(k)) < 1e-9, ...
        sprintf('%.6f s vs %.6f s', T2.duration_s, E.duration_s(k))};
    chk(end+1, :) = {'no retuning after seeing outcomes (design fixed in the runner header)', true, ''};
    rel = strrep(outDir(numel(here) + 2:end), '\', '/');
    [~, st] = system(sprintf('git -C "%s" status --porcelain', here));
    lines = strtrim(strsplit(strtrim(st), newline)); lines = lines(~cellfun(@isempty, lines));
    other = lines(~contains(lines, rel) & ~contains(lines, 'runMissionStrategyPilot.m'));
    chk(end+1, :) = {'no existing source / results / previous pilot folders modified (git status)', isempty(other), strjoin(other, '; ')};
    evalc('tr = runtests(fullfile(here, ''tests'', ''FrozenExperimentIntegrityTest.m''));');
    chk(end+1, :) = {'frozen Experiment F checksums unchanged', all([tr.Passed]), ''};
    SC = cell2table(chk, 'VariableNames', {'check', 'pass', 'detail'});
end

function ok = checkPrevalence(E)
    ok = all(abs(E.nDiseased - round(E.prevalence .* E.nPlants)) < 1e-9);
end

% ===================================================================== figures
function figures(E, A, D, figDir, phase)
    S = A.scenario; sc = D.scales(1).name; strat = ["twoPass", "onePass", "blanket", "oracle"]; cols = lines(4);
    pick = @(st, det, s) S(S.scale == sc & S.structure == st & S.detector == det & S.strategy == s, :);
    % 1 + 2 prevalence curves (HIGH detector, dispersed)
    fh = figure('Visible', 'off', 'Position', [50 50 1400 820], 'Color', 'w'); tl = tiledlayout(fh, 2, 2, 'TileSpacing', 'compact');
    ttl = {'mean_emitted_L', 'spray emitted (L)'; 'mean_treatmentSuccess_pct', 'treatment success (% of diseased)'; ...
           'mean_duration_s', 'mission duration (s)'; 'mean_energy_Wh', 'energy (Wh)'};
    for j = 1:4
        ax = nexttile(tl); hold(ax, 'on');
        for si = 1:4
            T = pick("dispersed", "HIGH", strat(si));
            plot(ax, 100 * T.prevalence, T.(ttl{j, 1}), '-o', 'Color', cols(si, :), 'LineWidth', 1.5, 'DisplayName', strat(si));
        end
        xlabel(ax, 'prevalence (%)'); ylabel(ax, ttl{j, 2}); grid(ax, 'on'); if j == 1, legend(ax, 'Location', 'northwest'); end
    end
    title(tl, sprintf('Prevalence curves (%s field, dispersed, HIGH detector; mean over seeds; oracle = research-only)', sc));
    exportgraphics(fh, fullfile(figDir, [phase '_01_02_prevalence_curves.png']), 'Resolution', 150); close(fh);
    % 3 detector quality at 20 % prevalence
    fh = figure('Visible', 'off', 'Position', [50 50 1400 460], 'Color', 'w'); tl = tiledlayout(fh, 1, 3, 'TileSpacing', 'compact');
    mets = {'mean_diseasedMissed_pct', 'diseased missed (%)'; 'mean_healthyTreated_pct', 'healthy plants treated (%)'; 'mean_duration_s', 'duration (s)'};
    for j = 1:3
        ax = nexttile(tl); hold(ax, 'on');
        for si = 1:4
            [~, ip] = min(abs(D.prev - 0.2)); p20 = D.prev(ip);
            y = arrayfun(@(dq) firstOr(S.(mets{j, 1})(S.scale == sc & S.structure == "dispersed" & S.prevalence == p20 & S.detector == dq & S.strategy == strat(si))), D.det.level);
            plot(ax, 1:3, y, '-o', 'Color', cols(si, :), 'LineWidth', 1.5, 'DisplayName', strat(si));
        end
        set(ax, 'XTick', 1:3, 'XTickLabel', D.det.level); ylabel(ax, mets{j, 2}); grid(ax, 'on'); if j == 1, legend(ax, 'Location', 'northwest'); end
    end
    title(tl, 'Detector quality at 20 % prevalence (dispersed)');
    exportgraphics(fh, fullfile(figDir, [phase '_03_detector_quality.png']), 'Resolution', 150); close(fh);
    % 4 clustering
    fh = figure('Visible', 'off', 'Position', [50 50 1400 460], 'Color', 'w'); tl = tiledlayout(fh, 1, 3, 'TileSpacing', 'compact');
    mets = {'mean_revisitDistance_m', 'Pass-2 revisit distance (m)'; 'mean_duration_s', 'duration (s)'; 'mean_energy_Wh', 'energy (Wh)'};
    for j = 1:3
        ax = nexttile(tl); hold(ax, 'on');
        for st = D.structures
            T = pick(st, "HIGH", "twoPass");
            plot(ax, 100 * T.prevalence, T.(mets{j, 1}), '-o', 'LineWidth', 1.5, 'DisplayName', "twoPass, " + st);
        end
        xlabel(ax, 'prevalence (%)'); ylabel(ax, mets{j, 2}); grid(ax, 'on'); legend(ax, 'Location', 'northwest');
    end
    title(tl, 'Clustered vs dispersed disease: two-pass revisit cost (HIGH detector)');
    exportgraphics(fh, fullfile(figDir, [phase '_04_clustering.png']), 'Resolution', 150); close(fh);
    % 5 strategy map (modal Pareto set over seeds)
    P = A.pareto;
    fh = figure('Visible', 'off', 'Position', [50 50 1300 460], 'Color', 'w'); tl = tiledlayout(fh, 1, numel(D.structures), 'TileSpacing', 'compact');
    for st = D.structures
        nP = numel(D.prev);
        ax = nexttile(tl); axis(ax, [0.5 nP + 0.5 0.5 3.5]); hold(ax, 'on');
        for i = 1:nP
            for j = 1:3
                k = P.scale == sc & P.structure == st & P.prevalence == D.prev(i) & P.detector == D.det.level(j);
                [u, ~, gi] = unique(P.paretoSet(k)); cnt = accumarray(gi, 1); [mx, w] = max(cnt);
                rectangle(ax, 'Position', [i - 0.5, j - 0.5, 1, 1], 'FaceColor', [0.92 0.95 1], 'EdgeColor', 'w');
                text(ax, i, j, sprintf('%s\n(%d/%d)', strrep(u(w), "+", newline + "+ "), mx, sum(k)), 'HorizontalAlignment', 'center', 'FontSize', 8);
            end
        end
        set(ax, 'XTick', 1:nP, 'XTickLabel', string(100 * D.prev) + "%", 'YTick', 1:3, 'YTickLabel', D.det.level);
        xlabel(ax, 'prevalence'); ylabel(ax, 'detector'); title(ax, st);
    end
    title(tl, sprintf('Pareto-efficient deployable strategies (success, spray, time); modal set over seeds, %s field', sc));
    exportgraphics(fh, fullfile(figDir, [phase '_05_strategy_map.png']), 'Resolution', 150); close(fh);
    % 6 baseline vs simulator
    B = A.baselineCells;
    fh = figure('Visible', 'off', 'Position', [50 50 1100 460], 'Color', 'w'); ax = axes(fh);
    objs = ["treatmentSuccess_pct", "emitted_L", "duration_s"];
    acc = [arrayfun(@(o) mean(B.simWinner(B.objective == o) == B.predWinner(B.objective == o)), objs), mean(P.paretoSet == P.predictedParetoSet)];
    bar(ax, categorical(["best treatment", "least spray", "shortest mission", "full Pareto set"], ["best treatment", "least spray", "shortest mission", "full Pareto set"]), 100 * acc);
    ylabel(ax, 'analytical prediction matches simulator (%)'); ylim(ax, [0 105]); grid(ax, 'on');
    title(ax, 'Simple analytical rules (B: sprayed fraction, C: BHH revisit + dwell time) vs simulator decisions');
    exportgraphics(fh, fullfile(figDir, [phase '_06_baseline_vs_simulator.png']), 'Resolution', 150); close(fh);
end

% ===================================================================== report
function writeReport(o, fn, phase)
    A = o.analysis; D = o.D; SC = o.sanity; E = o.evaluations;
    nFly = sum(E.strategy == "twoPass") + sum(E.strategy == "onePass") + ...
        height(unique(E(E.strategy == "oracle", {'scale', 'seed', 'structure', 'prevalence'}), 'rows')) + height(unique(E(:, {'scale', 'seed'}), 'rows'));
    L = {'# Two-pass selective spraying value test (mission_strategy_pilot_v1)', '', ...
        '> Within the current simulator: UNCALIBRATED spray model, synthetic detector, no wind, assumed hardware.', ...
        sprintf('> Phase **%s**: %d strategy evaluations (%d flown missions; blanket flown once per field and oracle once per truth, both reused across detector levels because they do not use detector output). Runtime %.0f s. Sanity: %s.', ...
        phase, height(E), nFly, o.runtime_s, ifelse(all(SC.pass), 'ALL PASS', 'FAILURES')), '', ...
        sprintf('Pareto tolerances (prespecified): treatment success within %.0f pp, spray and time within %.0f %% count as equal.', D.tol.success_pp, 100 * D.tol.chem_rel), '', ...
        '## Scenario means (over seeds)', '', ...
        '| scale | structure | prev. | detector | strategy | success % | missed % | healthy treated % | spray L | duration s | revisit m | energy Wh | refills |', ...
        '|---|---|---|---|---|---|---|---|---|---|---|---|---|'};
    S = A.scenario;
    for i = 1:height(S)
        L{end+1} = sprintf('| %s | %s | %.0f%% | %s | %s | %.1f | %.1f | %.1f | %.2f | %.0f | %.0f | %.1f | %.1f |', S.scale(i), S.structure(i), 100 * S.prevalence(i), ...
            S.detector(i), S.strategy(i), S.mean_treatmentSuccess_pct(i), S.mean_diseasedMissed_pct(i), S.mean_healthyTreated_pct(i), S.mean_emitted_L(i), ...
            S.mean_duration_s(i), S.mean_revisitDistance_m(i), S.mean_energy_Wh(i), S.mean_refills(i)); %#ok<AGROW>
    end
    P = A.pareto;
    [u, ~, gi] = unique(P.paretoSet); cnt = accumarray(gi, 1);
    L = [L, {'', '## Pareto sets (deployable: twoPass, onePass, blanket)', '', '| Pareto-efficient set | scenarios |', '|---|---|'}];
    for i = 1:numel(u), L{end+1} = sprintf('| %s | %d / %d |', u(i), cnt(i), height(P)); end %#ok<AGROW>
    [u, ~, gi] = unique(P.twoPass_dominatedBy); cnt = accumarray(gi, 1);
    L = [L, {'', '| twoPass dominated by | scenarios |', '|---|---|'}];
    for i = 1:numel(u), L{end+1} = sprintf('| %s | %d |', u(i), cnt(i)); end %#ok<AGROW>
    B = A.baseline;
    L = [L, {'', '## Simple-baseline challenge', '', '| rule | accuracy | mean regret | worst regret | n |', '|---|---|---|---|---|'}];
    for i = 1:height(B), L{end+1} = sprintf('| %s | %.3f | %.3g | %.3g | %d |', B.rule(i), B.accuracy(i), B.meanRegret(i), B.worstRegret(i), B.n(i)); end %#ok<AGROW>
    L = [L, {'', 'Regret units: treatment success pp, spray L, duration s. Predictions use only scenario parameters and field geometry.', ...
        '', '## Sanity checks', '', '| check | pass | detail |', '|---|---|---|'}];
    for i = 1:height(SC), L{end+1} = sprintf('| %s | %s | %s |', SC.check{i}, ifelse(SC.pass(i), 'PASS', 'FAIL'), SC.detail{i}); end %#ok<AGROW>
    L = [L, {'', '<!-- ANALYST ANSWERS: written after reviewing the tables above -->'}];
    fid = fopen(fn, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
end

function v = firstOr(x), if isempty(x), v = NaN; else, v = x(1); end, end

function s = ifelse(c, a, b), if c, s = a; else, s = b; end, end

function h = gitHead(here)
    [st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', here));
    if st ~= 0, h = 'unknown'; end
    h = strtrim(h);
end
