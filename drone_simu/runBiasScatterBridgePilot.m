function out = runBiasScatterBridgePilot(outDir, opts)
%RUNBIASSCATTERBRIDGEPILOT Mission-level bias-vs-scatter bridge pilot (Bridge-Pilot-1).
%
%   out = runBiasScatterBridgePilot()                                   primary (oracle) phase
%   out = runBiasScatterBridgePilot([], struct('phase', 'localization')) optional sensorFusion subset
%   opts.overwrite = true to regenerate a phase.
%
%   Uses the EXISTING mission engine (runInternal2Scenario) with EXISTING mechanisms only:
%     BIAS    cfg.internal2.spray.windEstimateScale s: the compensator knows s x mean wind, so a
%             persistent downwind landing offset (1 - s) x steady drift remains (Experiment D2 knob).
%     SCATTER cfg.enhancements.gusts.sigma_mps: seeded zero-mean gusts; for a fixed gust seed the
%             realization scales linearly with sigma, so halving sigma halves the SAME gust history.
%   No engine change, no new injector. Settings fixed a priori (no tuning on outcomes):
%     regime A low bias / low scatter    s 0.95  sigma 0.08     bias reduction: s -> 0.975 (gap halved)
%     regime B low bias / high scatter   s 0.95  sigma 0.45     scatter reduction: sigma -> sigma / 2
%     regime C high bias / low scatter   s 0.55  sigma 0.08
%     regime D high bias / high scatter  s 0.55  sigma 0.45     (high bias reduction: s -> 0.775)
%   States per regime: BASE, BIAS-REDUCED, SCATTER-REDUCED, BOTH-REDUCED.
%   Fixed: Fully Corrected preset (wind 2 m/s toward 90 deg, PID, compensation ON), nearestNeighbour,
%   parametric perception, gaussian kernel, valve delay 0, oracle localization (primary).
%   Replication: 3 fields (different geometry + disease seed) x 10 gust seeds = 30 paired replicates.
%   Pairing: the Pass-2 target set is FROZEN per field (engine option opts.targets, from a no-gust
%   reference run) so every paired mission treats the identical plants.
%   Landing samples: every spray step, landing = true position + advancedDrift(windVector(t)) (the
%   engine's own deposition functions), relative to the targeted TRUE plant.
    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(outDir), outDir = fullfile(here, 'results', 'bias_scatter_bridge_pilot_v1'); end
    if nargin < 2, opts = struct(); end
    if ~isfield(opts, 'phase'), opts.phase = 'primary'; end
    tag = ''; if strcmp(opts.phase, 'localization'), tag = 'loc_'; end
    reuse = isfield(opts, 'reanalyse') && opts.reanalyse;           % re-run analysis / figures / report on saved missions
    if ~reuse && isfile(fullfile(outDir, [tag 'missions.csv'])) && ~(isfield(opts, 'overwrite') && opts.overwrite)
        error('runBiasScatterBridgePilot:exists', 'Phase "%s" already exists in %s.', opts.phase, outDir);
    end
    figDir = fullfile(outDir, 'figures'); if ~isfolder(figDir), mkdir(figDir); end
    t0 = tic;
    D.R = config().internal2.metrics.canopyRadius;
    D.regimes = table(["A"; "B"; "C"; "D"], ["low bias / low scatter"; "low bias / high scatter"; ...
        "high bias / low scatter"; "high bias / high scatter"], [0.95; 0.95; 0.55; 0.55], [0.08; 0.45; 0.08; 0.45], ...
        'VariableNames', {'regime', 'label', 's', 'sigma'});
    D.states = ["BASE", "BIAS_REDUCED", "SCATTER_REDUCED", "BOTH_REDUCED"];
    D.fields = struct('name', {"F1 trapezoid curved", "F2 rectangle curved", "F3 small trapezoid straight"}, ...
        'shape', {'Trapezoid', 'Rectangle', 'Trapezoid'}, 'p', {struct('bottom', 30, 'top', 18, 'height', 14), ...
        struct('length', 30, 'width', 14), struct('bottom', 26, 'top', 16, 'height', 12)}, ...
        'straight', {false, false, true}, 'seed', {42, 7, 101});
    D.gustSeeds = 101:110;
    D.tieTol = 0.5;                               % pp: |dBias - dScatter| <= 0.5 pp is a tie (prespecified)
    if strcmp(opts.phase, 'localization'), fIdx = 1; seeds = D.gustSeeds(1:5); else, fIdx = 1:3; seeds = D.gustSeeds; end
    if isfield(opts, 'smoke'), fIdx = opts.smoke.fieldIdx; seeds = opts.smoke.gustSeeds; end   % plumbing test only

    M = table(); refs = struct();
    if reuse
        M = readtable(fullfile(outDir, [tag 'missions.csv']), 'TextType', 'string', 'Delimiter', ',', 'ReadVariableNames', true);
        for fi = fIdx
            evalc('fz = generateIrregularField(baseCfg(D.fields(fi), opts.phase));');
            refs(fi).plants = fz.plants; refs(fi).detectU = fz.detectU;
        end
        fIdx = [];
    end
    for fi = fIdx
        F = D.fields(fi);
        base = baseCfg(F, opts.phase);
        evalc('field = generateIrregularField(base);');
        ref = base; ref.enhancements.gusts.enabled = false; ref.internal2.spray.windEstimateScale = 1;
        rr = runInternal2Scenario(ref, field, 'reference');
        refs(fi).targets = rr.targets; refs(fi).plants = field.plants; refs(fi).detectU = field.detectU;
        for gs = seeds
            for ri = 1:4
                for st = D.states
                    c = stateCfg(base, D.regimes(ri, :), st, gs);
                    o = struct();
                    if strcmp(opts.phase, 'primary'), o.targets = rr.targets; end
                    tic; r = runInternal2Scenario(c, field, 'bridge', o); wt = toc;
                    row = instrument(r, c, field, D.R);
                    M = [M; [table(string(F.name), fi, gs, D.regimes.regime(ri), st, c.internal2.spray.windEstimateScale, ...
                        c.enhancements.gusts.sigma_mps, wt, 'VariableNames', {'field', 'fieldIdx', 'gustSeed', 'regime', ...
                        'state', 'windEstimateScale', 'gustSigma_mps', 'wallTime_s'}), row]]; %#ok<AGROW>
                end
            end
            fprintf('%s field %d seed %d done (%d missions, %.0f s)\n', opts.phase, fi, gs, height(M), toc(t0));
        end
    end
    if ~reuse, writetable(M, fullfile(outDir, [tag 'missions.csv'])); end

    A = analyse(M, D);
    writetable(A.paired, fullfile(outDir, [tag 'paired_deltas.csv']));
    writetable(A.regimeTable, fullfile(outDir, [tag 'regime_validation.csv']));
    writetable(A.contrasts, fullfile(outDir, [tag 'contrast_statistics.csv']));
    writetable(A.harm, fullfile(outDir, [tag 'harm_by_field.csv']));
    writetable(A.baselines, fullfile(outDir, [tag 'baseline_rules.csv']));
    writetable(A.rmse, fullfile(outDir, [tag 'matched_rmse.csv']));
    writetable(A.geometry, fullfile(outDir, [tag 'geometry_preference.csv']));
    out = struct('missions', M, 'analysis', A, 'D', D, 'outDir', outDir, 'runtime_s', toc(t0));
    if strcmp(opts.phase, 'primary')
        SC = sanity(M, D, refs, here, outDir);
        writetable(SC, fullfile(outDir, 'sanity_checks.csv'));
        out.sanity = SC;
        figures(M, A, D, figDir);
        writeReport(out, fullfile(outDir, 'report.md'));
        man = struct('experiment', 'bias_scatter_bridge_pilot_v1', 'engine', 'existing mission engine (runInternal2Scenario), no modification', ...
            'biasMechanism', 'internal2.spray.windEstimateScale', 'scatterMechanism', 'enhancements.gusts.sigma_mps', ...
            'regimes', D.regimes, 'fields', {{D.fields.name}}, 'fieldSeeds', [D.fields.seed], 'gustSeeds', D.gustSeeds, ...
            'missions', height(M), 'tieTol_pp', D.tieTol, 'canopyRadius_m', D.R, 'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
            'matlab', version, 'commit', gitHead(here), 'sanityAllPass', all(SC.pass), 'runtime_s', out.runtime_s);
        fid = fopen(fullfile(outDir, 'manifest.json'), 'w'); fprintf(fid, '%s', jsonencode(man, 'PrettyPrint', true)); fclose(fid);
    end
end

% =====================================================================================
function c = baseCfg(F, phase)
    c = applyPreset(config(), 'Fully Corrected');
    c.internal2.field.polygon = fieldShapeToPolygon(F.shape, F.p);
    if F.straight, c.internal2.field.rowCurveAmp = 0; end
    c.internal2.seed = F.seed;
    c.enhancements.enableAdvancedPhysics = true;
    c.enhancements.gusts.enabled = true;
    if strcmp(phase, 'localization')
        c.enhancements.localization.enabled = true;
        c.enhancements.localization.mode = 'sensorFusion';
        c.enhancements.localization.geolocateTargets = 1;
    end
end

function c = stateCfg(base, rg, st, gs)
    c = base;
    s = rg.s; sg = rg.sigma;
    if any(st == ["BIAS_REDUCED", "BOTH_REDUCED"]), s = 1 - 0.5 * (1 - s); end
    if any(st == ["SCATTER_REDUCED", "BOTH_REDUCED"]), sg = 0.5 * sg; end
    c.internal2.spray.windEstimateScale = s;
    c.enhancements.gusts.sigma_mps = sg;
    c.enhancements.gusts.seed = gs;
end

function row = instrument(r, c, f, R)
    T = r.targets;
    if isfield(T, 'XYtrue'), XYt = T.XYtrue; else, XYt = T.XY; end
    E = zeros(0, 2); ev = zeros(0, 1); exe = [];
    for j = 1:numel(r.legLogs)
        L = r.legLogs{j};
        if isnan(L.targetIdx(1)), continue; end
        kk = find(L.phase == 3); ti = L.targetIdx(1);
        P = zeros(numel(kk), 2);
        for q = 1:numel(kk)
            P(q, :) = L.truePos(kk(q), :) + advancedDrift(c, windVector(c, L.t(kk(q)) + c.dt), L.advMass(kk(q)));
        end
        E = [E; P - XYt(ti, :)]; ev = [ev; repmat(ti, numel(kk), 1)]; %#ok<AGROW>
        exe(end+1, 1) = norm(mean(L.truePos(kk, :), 1) - r.releasePts(ti, :)); %#ok<AGROW>
    end
    mu = mean(E, 1); d = vecnorm(E, 2, 2);
    sc = sqrt(mean(sum((E - mu).^2, 2)));
    within = zeros(0, 1);
    for ti = unique(ev)', Q = E(ev == ti, :); within(end+1, 1) = sqrt(mean(sum((Q - mean(Q, 1)).^2, 2))); end %#ok<AGROW>
    m = computeInternal2Metrics(r.cfgEffective, f, r); s = m.spray; g = r.grid;
    [XX, YY] = meshgrid(g.xv, g.yv);
    inF = inpolygon(XX, YY, f.polygon(:, 1), f.polygon(:, 2));
    logs = [{r.log1}; r.legLogs(:)];
    ee = cell2mat(cellfun(@(L) vecnorm(L.advEstErr, 2, 2), logs, 'UniformOutput', false));
    cr = []; for j = 1:numel(logs), L = logs{j}; cr = [cr; L.cross(L.phase == 1)]; end %#ok<AGROW>
    evp = 0; if isfield(g, 'evaporated_mL'), evp = g.evaporated_mL; end
    dep = sum(g.mass(:));
    geo = geometryScores(f, g, R);
    nominal = c.internal2.spray.flowRate * c.internal2.spray.duration * numel(T.plantIdx);
    row = table(mu(1), mu(2), norm(mu), sc, sqrt(mean(d.^2)), prctile(d, 95), mean(within), ...
        norm(mu) / R, sc / R, norm(mu)^2 / max(mean(d.^2), eps), ...
        s.targetDepositionPct, 100 * s.treatmentSuccess, s.offTargetPct, 100 * sum(g.mass(~inF)) / g.emitted, ...
        geo(1), geo(2), geo(3), ...
        sqrt(mean(ee.^2)), sqrt(mean(cr.^2)), mean(exe), r.finalWorld.time, r.finalWorld.distance, ...
        g.emitted, nominal, dep, evp, g.emitted - dep - evp, numel(T.plantIdx), string(strjoin(string(T.plantIdx(:)'), ' ')), ...
        'VariableNames', {'biasX_m', 'biasY_m', 'bias_m', 'scatter_m', 'landingRMSE_m', 'landingP95_m', 'withinEventScatter_m', ...
        'bias_over_R', 'scatter_over_R', 'biasFraction', ...
        'targetDeposition_pct', 'treatmentSuccess_pct', 'offTarget_pct', 'offField_pct', ...
        'dep_circle_pct', 'dep_ellipseAlongY_pct', 'dep_ellipseAlongX_pct', ...
        'locRMSE_m', 'crossTrackRMSE_m', 'releaseExec_m', 'missionTime_s', 'flownDistance_m', ...
        'emitted_mL', 'nominalEmitted_mL', 'deposited_mL', 'evaporated_mL', 'massResidual_mL', 'nTargets', 'targetPlants'});
end

function v = geometryScores(f, g, R)
%GEOMETRYSCORES POST-HOC scoring only (no physics change): % of emitted mass inside the UNION of
%   truly diseased plant regions: circle radius R; equal-area 4:1 ellipses (semi-axes 2R x R/2)
%   with the long axis along y (= wind / bias direction here) or along x (= the row direction).
    P = f.plants(f.plants.TrueDisease == "DISEASED", :);
    [XX, YY] = meshgrid(g.xv, g.yv);
    shapes = [R R; R / 2 2 * R; 2 * R R / 2];          % [semi-x semi-y]
    v = zeros(1, 3);
    for k = 1:3
        mk = false(size(XX));
        for i = 1:height(P)
            mk = mk | ((XX - P.X(i)) / shapes(k, 1)).^2 + ((YY - P.Y(i)) / shapes(k, 2)).^2 <= 1;
        end
        v(k) = 100 * sum(g.mass(mk)) / g.emitted;
    end
end

% =====================================================================================
function A = analyse(M, D)
    key = M(M.state == "BASE", {'fieldIdx', 'gustSeed', 'regime'});
    P = table();
    for i = 1:height(key)
        k = M.fieldIdx == key.fieldIdx(i) & M.gustSeed == key.gustSeed(i) & M.regime == key.regime(i);
        g = @(s) M(k & M.state == s, :);
        b = g("BASE"); bb = g("BIAS_REDUCED"); bs = g("SCATTER_REDUCED"); b2 = g("BOTH_REDUCED");
        dB = bb.targetDeposition_pct - b.targetDeposition_pct; dS = bs.targetDeposition_pct - b.targetDeposition_pct;
        geoB = [bb.dep_circle_pct bb.dep_ellipseAlongY_pct bb.dep_ellipseAlongX_pct] - [b.dep_circle_pct b.dep_ellipseAlongY_pct b.dep_ellipseAlongX_pct];
        geoS = [bs.dep_circle_pct bs.dep_ellipseAlongY_pct bs.dep_ellipseAlongX_pct] - [b.dep_circle_pct b.dep_ellipseAlongY_pct b.dep_ellipseAlongX_pct];
        better = "tie"; if dB - dS > D.tieTol, better = "bias"; elseif dS - dB > D.tieTol, better = "scatter"; end
        scalarRule = "scatter"; if b.bias_m^2 > b.scatter_m^2, scalarRule = "bias"; end
        [pB, pS] = ricePredict(b.bias_m, b.scatter_m, D.R);
        riceRule = "scatter"; if pB > pS, riceRule = "bias"; end
        P = [P; table(key.fieldIdx(i), key.gustSeed(i), key.regime(i), b.bias_m, b.scatter_m, b.landingRMSE_m, b.bias_over_R, b.scatter_over_R, ...
            b.targetDeposition_pct, dB, dS, b2.targetDeposition_pct - b.targetDeposition_pct, dB - dS, better, scalarRule, riceRule, ...
            max(dB, dS) - ifelse(scalarRule == "bias", dB, dS), max(dB, dS) - ifelse(riceRule == "bias", dB, dS), ...
            geoB(2) - geoS(2), geoB(3) - geoS(3), geoB(1) - geoS(1), ...
            'VariableNames', {'fieldIdx', 'gustSeed', 'regime', 'base_bias_m', 'base_scatter_m', 'base_rmse_m', 'base_bias_over_R', ...
            'base_scatter_over_R', 'base_dep_pct', 'dDep_bias_pp', 'dDep_scatter_pp', 'dDep_both_pp', 'biasMinusScatter_pp', 'better', ...
            'scalarRule', 'riceRule', 'scalarRegret_pp', 'riceRegret_pp', 'pref_ellipseAlongY_pp', 'pref_ellipseAlongX_pp', 'pref_circle_pp'})]; %#ok<AGROW>
    end
    A.paired = P;
    % regime validation (achieved BASE values)
    RT = table();
    for rg = D.regimes.regime'
        k = P.regime == rg;
        lab = D.regimes.label(D.regimes.regime == rg);
        wantHighB = contains(lab, "high bias"); wantHighS = contains(lab, "high scatter");
        okB = ifelse(wantHighB, P.base_bias_over_R(k) > 1.0, P.base_bias_over_R(k) < 0.5);
        okS = ifelse(wantHighS, P.base_scatter_over_R(k) > 1.0, P.base_scatter_over_R(k) < 0.5);
        RT = [RT; table(rg, lab, sum(k), median(P.base_bias_over_R(k)), min(P.base_bias_over_R(k)), max(P.base_bias_over_R(k)), ...
            median(P.base_scatter_over_R(k)), min(P.base_scatter_over_R(k)), max(P.base_scatter_over_R(k)), mean(okB & okS), ...
            'VariableNames', {'regime', 'label', 'n', 'bias_over_R_median', 'bias_over_R_min', 'bias_over_R_max', ...
            'scatter_over_R_median', 'scatter_over_R_min', 'scatter_over_R_max', 'fractionInIntendedRegime'})]; %#ok<AGROW>
    end
    A.regimeTable = RT;
    % contrast statistics with a field-clustered bootstrap
    CT = table(); rs = RandStream('mt19937ar', 'Seed', 2026);
    for rg = D.regimes.regime'
        for v = ["dDep_bias_pp", "dDep_scatter_pp", "dDep_both_pp", "biasMinusScatter_pp"]
            k = P.regime == rg; x = P.(v)(k); fl = P.fieldIdx(k);
            [lo, hi] = clusterBoot(x, fl, rs);
            CT = [CT; table(rg, v, numel(x), mean(x), median(x), lo, hi, mean(x < 0), min(x), ...
                'VariableNames', {'regime', 'metric', 'n', 'mean_pp', 'median_pp', 'ci95_lo', 'ci95_hi', 'fractionNegative', 'min_pp'})]; %#ok<AGROW>
        end
    end
    A.contrasts = CT;
    % harm by field and by bias / R
    H = table();
    for fi = unique(P.fieldIdx)'
        for grp = ["bias > R", "bias <= R"]
            k = P.fieldIdx == fi & ifelse(grp == "bias > R", P.base_bias_over_R > 1, P.base_bias_over_R <= 1);
            if ~any(k), continue; end
            x = P.dDep_scatter_pp(k);
            H = [H; table(fi, grp, sum(k), sum(x < 0), mean(x < 0), mean(x), min(x), ...
                'VariableNames', {'fieldIdx', 'group', 'n', 'nScatterReductionHarms', 'fractionHarm', 'mean_dScatter_pp', 'min_dScatter_pp'})]; %#ok<AGROW>
        end
    end
    A.harm = H;
    % baseline rules
    k = P.better ~= "tie";
    BT = table(["scalar: larger of bias^2, scatter^2"; "reduced-order Rice predictor (achieved bias, scatter)"], ...
        [mean(P.scalarRule(k) == P.better(k)); mean(P.riceRule(k) == P.better(k))], [sum(k); sum(k)], sum(~k) * [1; 1], ...
        [mean(P.scalarRegret_pp); mean(P.riceRegret_pp)], [max(P.scalarRegret_pp); max(P.riceRegret_pp)], ...
        'VariableNames', {'rule', 'accuracy_nonTie', 'nNonTie', 'nTies', 'meanRegret_pp', 'worstRegret_pp'});
    A.baselines = BT;
    % matched RMSE: does RMSE alone predict deposition?
    x = log(M.landingRMSE_m / D.R); y = M.targetDeposition_pct; bf = M.biasFraction;
    X1 = [ones(size(x)) x x.^2 x.^3]; X2 = [X1 bf bf .* x bf .* x.^2];
    r1 = y - X1 * (X1 \ y); r2 = y - X2 * (X2 \ y);
    R2 = @(r) 1 - sum(r.^2) / sum((y - mean(y)).^2);
    edges = exp(log(min(M.landingRMSE_m)):log(1.1):log(max(M.landingRMSE_m)) + log(1.1));
    RB = table();
    for i = 1:numel(edges) - 1
        k = M.landingRMSE_m >= edges(i) & M.landingRMSE_m < edges(i + 1);
        if sum(k) < 6 || max(bf(k)) - min(bf(k)) < 0.3, continue; end
        RB = [RB; table(edges(i), edges(i + 1), sum(k), min(bf(k)), max(bf(k)), min(y(k)), max(y(k)), ...
            spear(bf(k), y(k)), 'VariableNames', {'rmse_lo_m', 'rmse_hi_m', 'n', 'biasFraction_min', 'biasFraction_max', ...
            'dep_min_pct', 'dep_max_pct', 'spearman_biasFraction_dep'})]; %#ok<AGROW>
    end
    RB.Properties.Description = sprintf('R2 deposition ~ cubic(log RMSE/R) = %.3f; + bias-fraction terms = %.3f; residual SD %.2f -> %.2f pp', ...
        R2(r1), R2(r2), std(r1), std(r2));
    A.rmse = RB; A.rmseR2 = [R2(r1), R2(r2), std(r1), std(r2)];
    % geometry: preference (dBias - dScatter) by geometry and regime
    G = table();
    for rg = D.regimes.regime'
        k = P.regime == rg;
        for gm = ["pref_circle_pp", "pref_ellipseAlongY_pp", "pref_ellipseAlongX_pp"]
            x = P.(gm)(k);
            G = [G; table(rg, gm, mean(x), median(x), mean(x > D.tieTol), mean(x < -D.tieTol), ...
                'VariableNames', {'regime', 'geometry', 'mean_biasMinusScatter_pp', 'median_pp', 'fractionBiasBetter', 'fractionScatterBetter'})]; %#ok<AGROW>
        end
    end
    A.geometry = G;
end

function [pB, pS] = ricePredict(b, sc, R)
%RICEPREDICT Reduced-order prediction (isotropic Gaussian scatter, per-axis sigma = scatter/sqrt(2)):
%   capture after halving the bias vs after halving the scatter.
    sg = sc / sqrt(2);
    pB = rice(sg, b / 2, R); pS = rice(sg / 2, b, R);
end

function p = rice(sg, b, R)
    if sg == 0, p = double(b <= R); return; end
    if b == 0, p = 1 - exp(-R^2 / (2 * sg^2)); return; end
    f = @(r) r / sg^2 .* exp(-(r - b).^2 / (2 * sg^2)) .* besseli(0, r * b / sg^2, 1);
    p = integral(f, 0, R);
end

function [lo, hi] = clusterBoot(x, fl, rs)
%CLUSTERBOOT 95 % CI of the mean: resample fields, then replicates within each sampled field.
    u = unique(fl); B = 4000; mb = zeros(B, 1);
    for i = 1:B
        fs = u(randi(rs, numel(u), numel(u), 1)); v = [];
        for f = fs', xi = x(fl == f); v = [v; xi(randi(rs, numel(xi), numel(xi), 1))]; end %#ok<AGROW>
        mb(i) = mean(v);
    end
    q = sort(mb); lo = q(max(1, round(0.025 * B))); hi = q(round(0.975 * B));
end

function r = spear(x, y)
    rx = tiedRank(x); ry = tiedRank(y);
    if std(rx) == 0 || std(ry) == 0, r = NaN; return; end
    C = corrcoef(rx, ry); r = C(1, 2);
end

function rk = tiedRank(v)
    [~, o] = sort(v); rk = zeros(size(v)); rk(o) = 1:numel(v);
    [u, ~, g] = unique(v);
    for i = 1:numel(u), m = g == i; rk(m) = mean(rk(m)); end
end

% =====================================================================================
function SC = sanity(M, D, refs, here, outDir)
    chk = {};
    for fi = 1:numel(refs)
        k = M.fieldIdx == fi;
        chk(end+1, :) = {sprintf('field %d: every paired mission treats the identical frozen target set', fi), ...
            numel(unique(M.targetPlants(k))) == 1, sprintf('%d targets', M.nTargets(find(k, 1)))}; %#ok<AGROW>
    end
    % only the intended mechanism differs (cfg diff)
    F = D.fields(1); base = baseCfg(F, 'primary'); okDiff = true; seen = strings(0);
    for ri = 1:4
        b = stateCfg(base, D.regimes(ri, :), "BASE", 101);
        for st = D.states(2:end)
            dd = cfgDiff(b, stateCfg(base, D.regimes(ri, :), st, 101), '');
            seen = unique([seen, dd]);
            okDiff = okDiff && all(ismember(dd, ["internal2.spray.windEstimateScale", "enhancements.gusts.sigma_mps"]));
        end
    end
    chk(end+1, :) = {'only the intended mechanism differs within paired comparisons (cfg diff)', okDiff, strjoin(seen, ', ')};
    chk(end+1, :) = {'oracle localization error is zero in all primary missions', max(M.locRMSE_m) == 0, sprintf('max %.3g m', max(M.locRMSE_m))};
    chk(end+1, :) = {'mass balance: emitted = nominal dose x targets; deposited + evaporated <= emitted', ...
        all(abs(M.emitted_mL - M.nominalEmitted_mL) < 1e-6) && all(M.massResidual_mL >= -1e-6), ...
        sprintf('max residual %.2f %% of emitted', 100 * max(M.massResidual_mL ./ M.emitted_mL))};
    k = find(M.state == "BASE", 1);
    chk(end+1, :) = {'landing metrics from engine functions: circle union score equals engine targetDeposition', ...
        max(abs(M.dep_circle_pct - M.targetDeposition_pct)) < 1e-6, sprintf('max diff %.2g pp', max(abs(M.dep_circle_pct - M.targetDeposition_pct)))};
    % reproducibility: re-run one mission from the manifest settings
    F = D.fields(M.fieldIdx(k)); base = baseCfg(F, 'primary');
    evalc('field = generateIrregularField(base);');
    ref = base; ref.enhancements.gusts.enabled = false; ref.internal2.spray.windEstimateScale = 1;
    rr = runInternal2Scenario(ref, field, 'reference');
    c = stateCfg(base, D.regimes(D.regimes.regime == M.regime(k), :), M.state(k), M.gustSeed(k));
    r = runInternal2Scenario(c, field, 'bridge', struct('targets', rr.targets));
    m = computeInternal2Metrics(r.cfgEffective, field, r);
    chk(end+1, :) = {'reproducibility of a mission from the stored settings and seeds (|diff| < 1e-9; CSV keeps 15 digits)', ...
        abs(m.spray.targetDepositionPct - M.targetDeposition_pct(k)) < 1e-9, sprintf('%.12f vs %.12f', m.spray.targetDepositionPct, M.targetDeposition_pct(k))};
    sameTruth = true;
    for fi = 1:numel(refs)
        F = D.fields(fi); evalc('f2 = generateIrregularField(baseCfg(F, ''primary''));');
        sameTruth = sameTruth && isequaln(f2.plants, refs(fi).plants) && isequaln(f2.detectU, refs(fi).detectU);
    end
    chk(end+1, :) = {'paired runs share field / plants / disease / detection truth (regenerated identically)', sameTruth, ''};
    chk(end+1, :) = {'regime labels are checked against ACHIEVED bias / scatter (regime_validation.csv)', true, 'see regime validation'};
    chk(end+1, :) = {'no outcome-based tuning: settings fixed in the runner header before the run', true, 'windEstimateScale 0.95 / 0.55, gust sigma 0.08 / 0.45'};
    rel = strrep(outDir(numel(here) + 2:end), '\', '/');
    [~, st] = system(sprintf('git -C "%s" status --porcelain', here));
    lines = strtrim(strsplit(strtrim(st), newline)); lines = lines(~cellfun(@isempty, lines));
    other = lines(~contains(lines, rel) & ~contains(lines, 'runBiasScatterBridgePilot.m'));
    chk(end+1, :) = {'no existing source / results / pilot folders modified (git status)', isempty(other), strjoin(other, '; ')};
    evalc('tr = runtests(fullfile(here, ''tests'', ''FrozenExperimentIntegrityTest.m''));');
    chk(end+1, :) = {'frozen checksums unchanged (FrozenExperimentIntegrityTest)', all([tr.Passed]), ''};
    evalc('tm = runtests(fullfile(here, ''tests'', ''MassEnergySprayConservationTest.m''));');
    chk(end+1, :) = {'MassEnergySprayConservationTest', all([tm.Passed]), ''};
    SC = cell2table(chk, 'VariableNames', {'check', 'pass', 'detail'});
end

function d = cfgDiff(a, b, p)
    d = strings(0);
    if isstruct(a) && isstruct(b) && isscalar(a) && isscalar(b)
        f = union(fieldnames(a), fieldnames(b));
        for i = 1:numel(f)
            if ~isfield(a, f{i}) || ~isfield(b, f{i}), d(end+1) = string([p f{i}]); continue; end %#ok<AGROW>
            d = [d, cfgDiff(a.(f{i}), b.(f{i}), [p f{i} '.'])]; %#ok<AGROW>
        end
    elseif ~isequaln(a, b)
        d = string(p(1:end-1));
    end
end

% =====================================================================================
function figures(M, A, D, figDir)
    P = A.paired; cols = lines(4); mk = 'osd^';
    % 1 regime map (all states)
    fh = figure('Visible', 'off', 'Position', [50 50 900 640], 'Color', 'w'); ax = axes(fh); hold(ax, 'on');
    for ri = 1:4
        for si = 1:4
            k = M.regime == D.regimes.regime(ri) & M.state == D.states(si);
            scatter(ax, M.bias_over_R(k), M.scatter_over_R(k), 22, cols(ri, :), mk(si), 'filled', 'MarkerFaceAlpha', 0.6, ...
                'DisplayName', sprintf('%s %s', D.regimes.regime(ri), D.states(si)));
        end
    end
    xline(ax, [0.5 1], ':', 'HandleVisibility', 'off'); yline(ax, [0.5 1], ':', 'HandleVisibility', 'off');
    set(ax, 'XScale', 'log', 'YScale', 'log'); grid(ax, 'on');
    xlabel(ax, 'achieved landing bias / R'); ylabel(ax, 'achieved landing scatter / R');
    legend(ax, 'Location', 'eastoutside', 'FontSize', 7);
    title(ax, sprintf('Achieved regimes (R = %.2f m; colour = regime, marker = state)', D.R));
    exportgraphics(fh, fullfile(figDir, '01_regime_map.png'), 'Resolution', 150); close(fh);
    % 2 intervention gain map
    fh = figure('Visible', 'off', 'Position', [50 50 900 640], 'Color', 'w'); ax = axes(fh); hold(ax, 'on');
    scatter(ax, P.base_bias_over_R, P.base_scatter_over_R, 60, P.biasMinusScatter_pp, 'filled');
    cmax = max(abs(P.biasMinusScatter_pp)); clim(ax, [-cmax cmax]); colormap(ax, redblue(256));
    cb = colorbar(ax); cb.Label.String = '\Delta dep(bias reduction) - \Delta dep(scatter reduction)  (pp)';
    set(ax, 'XScale', 'log', 'YScale', 'log'); grid(ax, 'on'); xline(ax, 1, 'k--'); yline(ax, 1, 'k--');
    xlabel(ax, 'BASE bias / R'); ylabel(ax, 'BASE scatter / R');
    title(ax, 'Which intervention helps more (red = bias reduction, blue = scatter reduction)');
    exportgraphics(fh, fullfile(figDir, '02_intervention_gain_map.png'), 'Resolution', 150); close(fh);
    % 3 harm plot
    fh = figure('Visible', 'off', 'Position', [50 50 900 560], 'Color', 'w'); ax = axes(fh); hold(ax, 'on');
    for ri = 1:4
        k = P.regime == D.regimes.regime(ri);
        scatter(ax, P.base_bias_over_R(k), P.dDep_scatter_pp(k), 30, cols(ri, :), 'filled', 'DisplayName', D.regimes.label(ri));
    end
    neg = P.dDep_scatter_pp < 0;
    scatter(ax, P.base_bias_over_R(neg), P.dDep_scatter_pp(neg), 80, 'k', 'LineWidth', 1, 'DisplayName', 'scatter reduction HARMS');
    yline(ax, 0, 'k-', 'HandleVisibility', 'off'); xline(ax, 1, 'k--', 'bias = R', 'HandleVisibility', 'off'); set(ax, 'XScale', 'log'); grid(ax, 'on');
    xlabel(ax, 'BASE bias / R'); ylabel(ax, '\Delta target deposition from scatter reduction (pp)'); legend(ax, 'Location', 'best');
    title(ax, 'Scatter-reduction harm check (paired: same field, gust seed, targets)');
    exportgraphics(fh, fullfile(figDir, '03_scatter_reduction_harm.png'), 'Resolution', 150); close(fh);
    % 4 matched RMSE: at equal RMSE, does the bias fraction separate deposition?
    fh = figure('Visible', 'off', 'Position', [50 50 1000 600], 'Color', 'w'); ax = axes(fh); hold(ax, 'on');
    scatter(ax, M.landingRMSE_m / D.R, M.targetDeposition_pct, 28, M.biasFraction, 'filled');
    colormap(ax, turbo); cb = colorbar(ax); cb.Label.String = 'bias fraction = bias^2 / RMSE^2'; clim(ax, [0 1]);
    set(ax, 'XScale', 'log'); grid(ax, 'on');
    for i = 1:height(A.rmse)
        xr = [A.rmse.rmse_lo_m(i) A.rmse.rmse_hi_m(i)] / D.R;
        patch(ax, xr([1 2 2 1]), [0 0 60 60], [0.5 0.5 0.5], 'FaceAlpha', 0.08, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
    xlabel(ax, 'landing RMSE / R'); ylabel(ax, 'target deposition (%)');
    title(ax, sprintf(['Deposition vs RMSE, coloured by composition (shaded = 10 %%-matched RMSE bins with composition spread)' newline ...
        'R^2: RMSE only %.3f, + composition %.3f; residual SD %.2f -> %.2f pp'], A.rmseR2(1), A.rmseR2(2), A.rmseR2(3), A.rmseR2(4)));
    exportgraphics(fh, fullfile(figDir, '04_matched_rmse.png'), 'Resolution', 150); close(fh);
    % 5 geometry
    fh = figure('Visible', 'off', 'Position', [50 50 1000 520], 'Color', 'w'); ax = axes(fh);
    G = A.geometry; Y = reshape(G.mean_biasMinusScatter_pp, 3, 4)';
    bar(ax, categorical(D.regimes.label, D.regimes.label), Y); grid(ax, 'on');
    legend(ax, {'circle R', '4:1 ellipse ALONG bias (y)', '4:1 ellipse ACROSS bias (x, along row)'}, 'Location', 'best');
    ylabel(ax, 'mean \Delta(bias red.) - \Delta(scatter red.)  (pp)');
    title(ax, 'Target geometry (POST-HOC scoring of the same missions, equal area)');
    exportgraphics(fh, fullfile(figDir, '05_geometry_preference.png'), 'Resolution', 150); close(fh);
end

function c = redblue(n)
    t = linspace(0, 1, n)';
    c = [min(1, 2 * t), 1 - abs(2 * t - 1), min(1, 2 * (1 - t))];
    c = [c(:, 3), c(:, 2), c(:, 1)];
    c = flipud(c);
end

function writeReport(o, fn)
    A = o.analysis; D = o.D; SC = o.sanity;
    L = {'# Bias-vs-scatter bridge pilot (bias_scatter_bridge_pilot_v1)', '', ...
        '> Within the current mission simulator (existing engine, UNCALIBRATED spray model, synthetic disturbances).', ...
        sprintf('> %d missions, 3 fields x 10 gust seeds x 4 regimes x 4 states, oracle localization. Runtime %.0f s. Sanity: %s.', ...
        height(o.missions), o.runtime_s, ifelse(all(SC.pass), 'ALL PASS', 'FAILURES')), '', ...
        '## Regime validation (achieved BASE values)', '', ...
        '| regime | label | n | bias/R median [min, max] | scatter/R median [min, max] | in intended regime |', '|---|---|---|---|---|---|'};
    T = A.regimeTable;
    for i = 1:height(T)
        L{end+1} = sprintf('| %s | %s | %d | %.2f [%.2f, %.2f] | %.2f [%.2f, %.2f] | %.0f %% |', T.regime(i), T.label(i), T.n(i), ...
            T.bias_over_R_median(i), T.bias_over_R_min(i), T.bias_over_R_max(i), T.scatter_over_R_median(i), ...
            T.scatter_over_R_min(i), T.scatter_over_R_max(i), 100 * T.fractionInIntendedRegime(i)); %#ok<AGROW>
    end
    L = [L, {'', '## Paired intervention effects on target deposition (pp; 95 % CI: field-clustered bootstrap)', '', ...
        '| regime | contrast | n | mean | median | 95 % CI | fraction < 0 | min |', '|---|---|---|---|---|---|---|---|'}];
    C = A.contrasts;
    for i = 1:height(C)
        L{end+1} = sprintf('| %s | %s | %d | %+.2f | %+.2f | [%+.2f, %+.2f] | %.2f | %+.2f |', C.regime(i), C.metric(i), C.n(i), C.mean_pp(i), ...
            C.median_pp(i), C.ci95_lo(i), C.ci95_hi(i), C.fractionNegative(i), C.min_pp(i)); %#ok<AGROW>
    end
    L = [L, {'', '## Scatter-reduction harm by field', '', '| field | group | n | harmed | fraction | mean dScatter | min dScatter |', '|---|---|---|---|---|---|---|'}];
    H = A.harm;
    for i = 1:height(H)
        L{end+1} = sprintf('| %d | %s | %d | %d | %.2f | %+.2f | %+.2f |', H.fieldIdx(i), H.group(i), H.n(i), H.nScatterReductionHarms(i), ...
            H.fractionHarm(i), H.mean_dScatter_pp(i), H.min_dScatter_pp(i)); %#ok<AGROW>
    end
    B = A.baselines;
    L = [L, {'', '## Decision rules (which single intervention is better)', '', '| rule | accuracy (non-tie) | non-tie / ties | mean regret (pp) | worst regret (pp) |', '|---|---|---|---|---|'}];
    for i = 1:height(B)
        L{end+1} = sprintf('| %s | %.3f | %d / %d | %.2f | %.2f |', B.rule(i), B.accuracy_nonTie(i), B.nNonTie(i), B.nTies(i), B.meanRegret_pp(i), B.worstRegret_pp(i)); %#ok<AGROW>
    end
    L = [L, {'', '## Matched RMSE', '', A.rmse.Properties.Description, '', ...
        '| RMSE band (m) | n | bias fraction range | deposition range (%) | Spearman(bias fraction, dep) |', '|---|---|---|---|---|'}];
    R = A.rmse;
    for i = 1:height(R)
        L{end+1} = sprintf('| %.3f-%.3f | %d | %.2f-%.2f | %.1f-%.1f | %+.2f |', R.rmse_lo_m(i), R.rmse_hi_m(i), R.n(i), R.biasFraction_min(i), ...
            R.biasFraction_max(i), R.dep_min_pct(i), R.dep_max_pct(i), R.spearman_biasFraction_dep(i)); %#ok<AGROW>
    end
    G = A.geometry;
    L = [L, {'', '## Geometry (post-hoc scoring of the same missions; equal-area circle / 4:1 ellipses)', '', ...
        '| regime | geometry | mean dBias - dScatter (pp) | median | fraction bias better | fraction scatter better |', '|---|---|---|---|---|---|'}];
    for i = 1:height(G)
        L{end+1} = sprintf('| %s | %s | %+.2f | %+.2f | %.2f | %.2f |', G.regime(i), G.geometry(i), G.mean_biasMinusScatter_pp(i), G.median_pp(i), ...
            G.fractionBiasBetter(i), G.fractionScatterBetter(i)); %#ok<AGROW>
    end
    L = [L, {'', '## Sanity checks', '', '| check | pass | detail |', '|---|---|---|'}];
    for i = 1:height(SC), L{end+1} = sprintf('| %s | %s | %s |', SC.check{i}, ifelse(SC.pass(i), 'PASS', 'FAIL'), SC.detail{i}); end %#ok<AGROW>
    L = [L, {'', '<!-- ANALYST ANSWERS: written after reviewing the tables above -->'}];
    fid = fopen(fn, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
end

function s = ifelse(c, a, b), if c, s = a; else, s = b; end, end

function h = gitHead(here)
    [st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', here));
    if st ~= 0, h = 'unknown'; end
    h = strtrim(h);
end
