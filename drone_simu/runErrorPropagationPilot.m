function out = runErrorPropagationPilot(outDir, opts)
%RUNERRORPROPAGATIONPILOT 16-mission error-propagation pilot (DRONE_ERROR_PROPAGATION_PILOT_EXPERIMENT).
%
%   out = runErrorPropagationPilot()                    -> results/error_propagation_pilot_v1
%   out = runErrorPropagationPilot(outDir, struct('overwrite', true))
%
%   2 x 2 x 2 x 2 paired factorial on ONE field / seed set, through the existing engine (runPipeline):
%     A wind        A0 off            | A1 2 m/s toward 90 deg + default seeded gusts (sigma 0.5 m/s, seed 7)
%     B localization B0 groundTruthOracle | B1 sensorFusion (+ geolocateTargets ON)
%     C controller  C0 pid            | C1 purePursuit
%     D spray comp. D0 none           | D1 wind
%   Fixed: parametric perception, boustrophedon, nearestNeighbour, gaussian kernel, assumedDefault
%   hardware, valve delay 0, speed 1.5 m/s, field seed 42, localization seed 3. The energy model is ON
%   for all 16 runs (bookkeeping only: it does not feed back into the flight) so energy can be reported.
%
%   INSTRUMENTATION ONLY: every stage metric below is computed AFTER the flight from the existing
%   logs (truth used for scoring only). No engine code is changed.
%     Stage 1 localization  : |est - true| over all steps of both passes (advEstErr)
%     Stage 2 tracking      : signed cross-track of the TRUE position to the reference (log.cross),
%                             travel steps (phase 1) of Pass 1 and Pass 2
%     Stage 3 release       : per target leg, actual release = mean TRUE position over the spray dwell
%                             (phase 3);  geolocation error = |recorded target - true plant|;
%                             execution error = |actual - commanded release point|;
%                             total release error = |actual - (true plant + compVec)| (ideal release of
%                             the selected strategy);  landing error = mean |release position +
%                             drift(instantaneous wind incl. gusts) - true plant| per spray step, with the
%                             engine's own advancedDrift / windVector (bias + gust scatter reported too)
%     Stage 4 outcome       : existing sprayMetrics / computeRunMetrics, mass balance from the grid
%   Writes pilot_runs.csv, stage_metrics.csv, per_target.csv, interactions.csv, associations.csv,
%   bottleneck.csv, sanity_checks.csv, report.md, manifest.json, figures/01-03. Refuses to overwrite.
    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(outDir), outDir = fullfile(here, 'results', 'error_propagation_pilot_v1'); end
    if nargin < 2, opts = struct(); end
    if isfile(fullfile(outDir, 'manifest.json')) && ~(isfield(opts, 'overwrite') && opts.overwrite)
        error('runErrorPropagationPilot:exists', 'Pilot already exists in %s (use a new folder).', outDir);
    end
    figDir = fullfile(outDir, 'figures');
    if ~isfolder(figDir), mkdir(figDir); end
    t0 = tic;
    rc = config().internal2.metrics.canopyRadius;

    % ---------------- 16 missions ----------------
    lv.wind = [false true]; lv.loc = {'groundTruthOracle', 'sensorFusion'};
    lv.ctrl = {'pid', 'purePursuit'}; lv.comp = {'none', 'wind'};
    R = table(); S = table(); PT = table(); res = cell(16, 1); n = 0;
    for a = 1:2, for b = 1:2, for c = 1:2, for d = 1:2
        n = n + 1;
        pc = pipelineDefaults();
        pc.scenario.wind = struct('enabled', lv.wind(a), 'speed', 2.0, 'dirDeg', 90);
        pc.scenario.gust_mps = 0.5 * lv.wind(a); pc.scenario.gustSeed = 7;
        pc.scenario.valveDelay_s = 0; pc.scenario.physics.energy = true;
        pc.pipeline.localization = lv.loc{b}; pc.pipeline.controller = lv.ctrl{c};
        pc.pipeline.sprayCompensation = lv.comp{d};
        pc.pipeline.geolocateTargets = b == 2;
        r = runPipeline(pc);
        res{n} = r;
        [row, srow, ptab] = instrument(r, rc);
        id = sprintf('M%02d', n);
        cond = table(string(id), a - 1, string(lv.loc{b}), string(lv.ctrl{c}), string(lv.comp{d}), b == 2, ...
            'VariableNames', {'run', 'wind', 'localization', 'controller', 'compensation', 'geolocateTargets'});
        R = [R; [cond, row]]; %#ok<AGROW>
        S = [S; [cond(:, 1:5), srow]]; %#ok<AGROW>
        ptab.run = repmat(string(id), height(ptab), 1);
        PT = [PT; ptab]; %#ok<AGROW>
        fprintf('%s wind=%d %-17s %-11s %-4s  locRMSE %.3f  cross %.3f  rel %.3f  land %.3f  dep %.1f%%\n', id, a - 1, ...
            lv.loc{b}, lv.ctrl{c}, lv.comp{d}, row.loc_rmse_m, row.track_rmse_m, row.release_total_mean_m, ...
            row.landing_mean_m, row.targetDeposition_pct);
    end, end, end, end
    writetable(R, fullfile(outDir, 'pilot_runs.csv'));
    writetable(S, fullfile(outDir, 'stage_metrics.csv'));
    writetable(PT, fullfile(outDir, 'per_target.csv'));

    % ---------------- sanity checks ----------------
    SC = sanity(R, res, here);
    writetable(SC, fullfile(outDir, 'sanity_checks.csv'));

    % ---------------- analysis ----------------
    combos = unique(R(:, {'controller', 'compensation'}), 'rows', 'stable');
    ym = {'track_rmse_m', 'release_total_mean_m', 'landing_mean_m', 'targetDeposition_pct', 'treatmentSuccess_pct'};
    IT = table(); CT = table(); BT = table();
    for i = 1:height(combos)
        k = R.controller == combos.controller(i) & R.compensation == combos.compensation(i);
        g = @(w, l) R(k & R.wind == w & R.localization == l, :);
        O0 = g(0, "groundTruthOracle"); O1 = g(1, "groundTruthOracle"); F0 = g(0, "sensorFusion"); F1 = g(1, "sensorFusion");
        for m = ym
            v = @(T) T.(m{1});
            IT = [IT; table(combos.controller(i), combos.compensation(i), string(m{1}), v(O0), v(O1), v(F0), v(F1), ...
                (v(F1) - v(F0)) - (v(O1) - v(O0)), 'VariableNames', {'controller', 'compensation', 'metric', ...
                'noWind_oracle', 'wind_oracle', 'noWind_sensorFusion', 'wind_sensorFusion', 'interaction_DiD'})]; %#ok<AGROW>
        end
        cn = {'oracle->sensorFusion | no wind', O0, F0; 'oracle->sensorFusion | wind', O1, F1; ...
              'no wind->wind | oracle', O0, O1; 'no wind->wind | sensorFusion', F0, F1};
        for j = 1:4
            A = cn{j, 2}; B = cn{j, 3};
            CT = [CT; table(combos.controller(i), combos.compensation(i), string(cn{j, 1}), ...
                B.loc_rmse_m - A.loc_rmse_m, B.track_rmse_m - A.track_rmse_m, B.release_total_mean_m - A.release_total_mean_m, ...
                B.landing_mean_m - A.landing_mean_m, B.targetDeposition_pct - A.targetDeposition_pct, B.treatmentSuccess_pct - A.treatmentSuccess_pct, ...
                'VariableNames', {'controller', 'compensation', 'contrast', 'd_loc_rmse_m', 'd_track_rmse_m', ...
                'd_release_total_mean_m', 'd_landing_mean_m', 'd_targetDeposition_pp', 'd_treatmentSuccess_pp'})]; %#ok<AGROW>
        end
        for T = {O0, O1, F0, F1}
            X = T{1};
            dl = (X.loc_rmse_m - O0.loc_rmse_m) / rc; dt_ = (X.track_rmse_m - O0.track_rmse_m) / rc;
            dr = (X.release_total_mean_m - O0.release_total_mean_m) / rc; da = (X.landing_mean_m - O0.landing_mean_m) / rc;
            dd = (O0.targetDeposition_pct - X.targetDeposition_pct) / max(O0.targetDeposition_pct, eps);
            [mx, w] = max([dl dt_ dr da]);
            st = ["localization", "tracking", "release geometry", "landing (spray transport)"];
            if mx < 0.01, w = 5; st(5) = "none (reference)"; end
            BT = [BT; table(X.run, combos.controller(i), combos.compensation(i), X.wind, X.localization, dl, dt_, dr, da, dd, st(w), ...
                'VariableNames', {'run', 'controller', 'compensation', 'wind', 'localization', 'loc_norm', 'tracking_norm', ...
                'release_norm', 'landing_norm', 'deposition_relLoss', 'largestGeometricStage'})]; %#ok<AGROW>
        end
    end
    writetable(IT, fullfile(outDir, 'interactions.csv'));
    writetable(CT, fullfile(outDir, 'contrasts.csv'));
    writetable(BT, fullfile(outDir, 'bottleneck.csv'));
    pairs = {'loc_rmse_m', 'track_rmse_m'; 'track_rmse_m', 'release_total_mean_m'; ...
             'release_total_mean_m', 'targetDeposition_pct'; 'loc_rmse_m', 'targetDeposition_pct'; ...
             'landing_mean_m', 'targetDeposition_pct'};
    AS = table();
    for i = 1:size(pairs, 1)
        x = R.(pairs{i, 1}); y = R.(pairs{i, 2});
        AS = [AS; table("16 runs", string(pairs{i, 1}), string(pairs{i, 2}), numel(x), ...
            pearson(x, y), pearson(rankavg(x), rankavg(y)), ...
            'VariableNames', {'level', 'x', 'y', 'n', 'pearson', 'spearman'})]; %#ok<AGROW>
    end
    for p = {'landing_m', 'release_total_m'}
        x = PT.(p{1}); y = PT.doseFraction;
        AS = [AS; table("per target (pooled)", string(p{1}), "doseFraction", numel(x), pearson(x, y), ...
            pearson(rankavg(x), rankavg(y)), 'VariableNames', {'level', 'x', 'y', 'n', 'pearson', 'spearman'})]; %#ok<AGROW>
    end
    writetable(AS, fullfile(outDir, 'associations.csv'));

    % ---------------- figures ----------------
    figures(R, figDir);

    % ---------------- report + manifest ----------------
    out = struct('runs', R, 'stages', S, 'perTarget', PT, 'interactions', IT, 'contrasts', CT, ...
        'bottleneck', BT, 'associations', AS, 'sanity', SC, 'outDir', outDir, 'runtime_s', toc(t0));
    writeReport(out, fullfile(outDir, 'report.md'), rc);
    man = struct('experiment', 'error_propagation_pilot_v1', 'status', 'PILOT, 1 field / 1 seed set, n = 16 paired missions', ...
        'calibration', 'UNCALIBRATED spray model; synthetic sensors; assumed hardware', ...
        'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), 'matlab', version, 'commit', gitHead(here), ...
        'fieldSeed', 42, 'gustSeed', 7, 'gustSigma_mps', 0.5, 'localizationSeed', 3, 'wind_mps', 2, 'windDirDeg', 90, ...
        'valveDelay_s', 0, 'energyModel', 'on (bookkeeping only)', 'scenarioHashes', {unique(R.scenarioHash)'}, ...
        'sanityAllPass', all(SC.pass), 'runtime_s', out.runtime_s);
    fid = fopen(fullfile(outDir, 'manifest.json'), 'w'); fprintf(fid, '%s', jsonencode(man, 'PrettyPrint', true)); fclose(fid);
end

% =====================================================================================
function [row, srow, ptab] = instrument(r, rc)
%INSTRUMENT Stage metrics of one finished run (truth used for scoring only).
    run = r.run; c = r.cfg; f = r.field; m = r.metrics;
    logs = [{run.log1}; run.legLogs(:)];
    cat = @(fn) cell2mat(cellfun(@(L) L.(fn), logs, 'UniformOutput', false));
    % Stage 1
    if isfield(run.log1, 'advEstErr'), ee = vecnorm(cat('advEstErr'), 2, 2); else, ee = zeros(numel(cat('t')), 1); end
    oracle = strcmp(r.pc.pipeline.localization, 'groundTruthOracle');
    nees = NaN; if isfield(run, 'advanced') && ~oracle, nees = run.advanced.estNEES; end
    % Stage 2 (travel steps of both passes)
    cr = []; for j = 1:numel(logs), L = logs{j}; cr = [cr; L.cross(L.phase == 1)]; end %#ok<AGROW>
    p1 = run.log1.truePos;
    allPos = cat('truePos');
    bviol = 100 * mean(~inpolygon(allPos(:, 1), allPos(:, 2), f.polygon(:, 1), f.polygon(:, 2)));
    % Stage 3 (per target leg)
    T = run.targets;
    if isfield(T, 'XYtrue'), XYt = T.XYtrue; else, XYt = T.XY; end
    nT = size(T.XY, 1);
    actual = nan(nT, 2);
    for j = 1:numel(run.legLogs)
        L = run.legLogs{j};
        if isnan(L.targetIdx(1)), continue; end
        actual(L.targetIdx(1), :) = mean(L.truePos(L.phase == 3, :), 1);
    end
    geo = vecnorm(T.XY - XYt, 2, 2);
    exe = vecnorm(actual - run.releasePts, 2, 2);
    ideal = XYt + run.compVec;
    tot = vecnorm(actual - ideal, 2, 2);
    % landing error: where each spray step's cloud centre actually lands (same functions as advDeposit:
    % advancedDrift of windVector at that time, incl. gusts), relative to the TRUE plant
    land = nan(nT, 1); bias = nan(nT, 1); scat = nan(nT, 1);
    for j = 1:numel(run.legLogs)
        L = run.legLogs{j};
        if isnan(L.targetIdx(1)), continue; end
        kk = find(L.phase == 3);
        P = zeros(numel(kk), 2);
        for q = 1:numel(kk)
            dr = advancedDrift(c, windVector(c, L.t(kk(q)) + c.dt), L.advMass(kk(q)));
            P(q, :) = L.truePos(kk(q), :) + dr;
        end
        ti = L.targetIdx(1);
        land(ti) = mean(vecnorm(P - XYt(ti, :), 2, 2));
        bias(ti) = norm(mean(P, 1) - XYt(ti, :));
        scat(ti) = sqrt(mean(sum((P - mean(P, 1)).^2, 2)));
    end
    dose = plantDose(c, f, run.grid);
    nominal = c.internal2.spray.flowRate * c.internal2.spray.duration;
    dfrac = dose(T.plantIdx) / nominal;
    isDis = f.plants.TrueDisease(T.plantIdx) == "DISEASED";
    ptab = table((1:nT)', T.plantIdx(:), isDis, geo, exe, tot, land, bias, scat, dfrac, 'VariableNames', ...
        {'target', 'plantIdx', 'trulyDiseased', 'geolocation_m', 'execution_m', 'release_total_m', 'landing_m', ...
        'landingBias_m', 'landingScatter_m', 'doseFraction'});
    % Stage 4 + resources
    s = m.spray; g = run.grid;
    ev = 0; if isfield(g, 'evaporated_mL'), ev = g.evaporated_mL; end
    dep = sum(g.mass(:));
    [XX, YY] = meshgrid(g.xv, g.yv);
    inF = inpolygon(XX, YY, f.polygon(:, 1), f.polygon(:, 2));
    en = NaN; if isfield(run, 'advanced'), en = run.advanced.energy_Wh; end
    lag = 0; if isfield(g, 'lagDisplacement_m'), lag = g.lagDisplacement_m; end
    q = @(x, p) prctile(x, p);
    row = table(string(r.scenarioHash(1:12)), string(r.pipelineHash(1:12)), ...
        sqrt(mean(ee.^2)), median(ee), q(ee, 95), max(ee), nees, ...
        sqrt(mean(cr.^2)), q(abs(cr), 95), max(abs(cr)), m.survey.crossRMSE, m.transit.crossRMSE, bviol, 0, ...
        mean(geo), q(geo, 95), mean(exe), q(exe, 95), mean(tot), q(tot, 95), mean(land), q(land, 95), mean(bias), mean(scat), lag, norm(run.compVec), ...
        s.targetDepositionPct, 100 * s.treatmentSuccess, s.offTargetPct, 100 * safeDiv(sum(g.mass(~inF)), g.emitted), ...
        g.emitted, dep, ev, g.emitted - dep - ev, 100 * (g.emitted - dep - ev) / g.emitted, ...
        run.finalWorld.time, run.finalWorld.distance, en, r.wallTime_s, numel(T.plantIdx), sum(isDis), ...
        'VariableNames', {'scenarioHash', 'pipelineHash', ...
        'loc_rmse_m', 'loc_median_m', 'loc_p95_m', 'loc_max_m', 'loc_NEES', ...
        'track_rmse_m', 'track_p95_m', 'track_max_m', 'track_survey_rmse_m', 'track_transit_rmse_m', 'boundaryViolation_pct', 'obstacleViolation_pct', ...
        'geoloc_mean_m', 'geoloc_p95_m', 'release_exec_mean_m', 'release_exec_p95_m', 'release_total_mean_m', 'release_total_p95_m', ...
        'landing_mean_m', 'landing_p95_m', 'landingBias_mean_m', 'landingScatter_mean_m', 'actuatorTiming_m', 'compOffset_m', ...
        'targetDeposition_pct', 'treatmentSuccess_pct', 'offTarget_pct', 'offField_pct', ...
        'emitted_mL', 'deposited_mL', 'evaporated_mL', 'massResidual_mL', 'massResidual_pct', ...
        'missionTime_s', 'flownDistance_m', 'energy_Wh', 'wallTime_s', 'nTargets', 'nTrueTargets'});
    srow = table(row.loc_rmse_m, row.track_rmse_m, row.release_total_mean_m, row.landing_mean_m, row.targetDeposition_pct, ...
        row.loc_rmse_m / rc, row.track_rmse_m / rc, row.release_total_mean_m / rc, row.landing_mean_m / rc, ...
        'VariableNames', {'S1_loc_rmse_m', 'S2_track_rmse_m', 'S3_release_total_mean_m', 'S3b_landing_mean_m', 'S4_targetDeposition_pct', ...
        'S1_per_canopyRadius', 'S2_per_canopyRadius', 'S3_per_canopyRadius', 'S3b_per_canopyRadius'});
end

function SC = sanity(R, res, here)
    chk = {};
    for w = [0 1]
        h = unique(R.scenarioHash(R.wind == w));
        chk(end+1, :) = {sprintf('scenario pairing: wind=%d runs share one scenario hash', w), numel(h) == 1, strjoin(h, ',')}; %#ok<AGROW>
    end
    same = all(cellfun(@(r) isequaln(r.field.plants, res{1}.field.plants) && isequaln(r.field.detectU, res{1}.field.detectU), res));
    chk(end+1, :) = {'identical field / plants / disease truth / detection draws in all 16 runs', same, ''};
    o = R.localization == "groundTruthOracle";
    chk(end+1, :) = {'oracle localization error is zero (ORACLE)', max(R.loc_max_m(o)) < 1e-12, sprintf('max %.3g m', max(R.loc_max_m(o)))};
    chk(end+1, :) = {'no-wind sanity: wind compensation offset is zero when wind = 0', ...
        max(R.compOffset_m(R.wind == 0)) < 1e-12, sprintf('max %.3g m', max(R.compOffset_m(R.wind == 0)))};
    chk(end+1, :) = {'actuator timing error is zero (valve delay 0)', max(R.actuatorTiming_m) == 0, ''};
    sf = R.localization == "sensorFusion";
    chk(end+1, :) = {'sensorFusion runs geolocate targets from the estimate (geolocation error > 0)', all(R.geoloc_mean_m(sf) > 0), ''};
    chk(end+1, :) = {'oracle runs: targets at true plant positions (geolocation error 0)', max(R.geoloc_mean_m(o)) == 0, ''};
    for t = {'TruthFirewallTest', 'MassEnergySprayConservationTest', 'FrozenExperimentIntegrityTest'}
        evalc('tr = runtests(fullfile(here, ''tests'', [t{1} ''.m'']));');
        chk(end+1, :) = {['test suite ' t{1}], all([tr.Passed]), sprintf('%d/%d passed', sum([tr.Passed]), numel(tr))}; %#ok<AGROW>
    end
    SC = cell2table(chk, 'VariableNames', {'check', 'pass', 'detail'});
end

function figures(R, figDir)
    cfgs = unique(R(:, {'controller', 'compensation'}), 'rows', 'stable');
    lab = cfgs.controller + " + " + cfgs.compensation;
    % 1 error chain: wind + sensorFusion vs its clean oracle reference
    fh = figure('Visible', 'off', 'Position', [50 50 1300 480], 'Color', 'w');
    tl = tiledlayout(fh, 1, 2, 'TileSpacing', 'compact');
    ax = nexttile(tl); hold(ax, 'on');
    st = {'loc_rmse_m', 'track_rmse_m', 'release_total_mean_m', 'landing_mean_m'};
    stl = {'localization RMSE', 'cross-track RMSE', 'release error (mean)', 'landing error (mean)'};
    D = zeros(height(cfgs), 4, 2);
    for i = 1:height(cfgs)
        k = R.controller == cfgs.controller(i) & R.compensation == cfgs.compensation(i);
        ref = R(k & R.wind == 0 & R.localization == "groundTruthOracle", :);
        dis = R(k & R.wind == 1 & R.localization == "sensorFusion", :);
        for j = 1:4, D(i, j, 1) = ref.(st{j}); D(i, j, 2) = dis.(st{j}); end
    end
    b = bar(ax, 1:4, [reshape(D(:, :, 1)', 4, []), reshape(D(:, :, 2)', 4, [])]);
    cm = [lines(4) * 0.5 + 0.5; lines(4)];
    for q = 1:numel(b), b(q).FaceColor = cm(q, :); end
    set(ax, 'XTick', 1:4, 'XTickLabel', stl, 'XTickLabelRotation', 15);
    ylabel(ax, 'error (m, absolute - not normalized)'); grid(ax, 'on');
    yline(ax, 0.2, 'k--', 'canopy radius 0.2 m');
    legend(ax, [strcat("clean (no wind, oracle): ", lab); strcat("wind + sensorFusion: ", lab)], 'Location', 'northwest', 'FontSize', 7);
    title(ax, 'Error chain: geometric stages');
    ax2 = nexttile(tl);
    dl = zeros(height(cfgs), 1);
    for i = 1:height(cfgs)
        k = R.controller == cfgs.controller(i) & R.compensation == cfgs.compensation(i);
        dl(i) = R.targetDeposition_pct(k & R.wind == 0 & R.localization == "groundTruthOracle") - ...
                R.targetDeposition_pct(k & R.wind == 1 & R.localization == "sensorFusion");
    end
    bar(ax2, categorical(lab, lab), dl, 'FaceColor', [0.85 0.33 0.1]);
    ylabel(ax2, 'target deposition loss (percentage points)'); grid(ax2, 'on');
    title(ax2, 'Outcome: clean minus wind + sensorFusion');
    title(tl, 'Error-propagation pilot (1 field, 1 seed set; simulated, UNCALIBRATED spray model)');
    exportgraphics(fh, fullfile(figDir, '01_error_chain.png'), 'Resolution', 150); close(fh);
    % 2 interaction plot per configuration
    fh = figure('Visible', 'off', 'Position', [50 50 1100 760], 'Color', 'w');
    tl = tiledlayout(fh, 2, 2, 'TileSpacing', 'compact');
    for i = 1:height(cfgs)
        ax = nexttile(tl); hold(ax, 'on');
        k = R.controller == cfgs.controller(i) & R.compensation == cfgs.compensation(i);
        for l = ["groundTruthOracle", "sensorFusion"]
            y = [R.targetDeposition_pct(k & R.wind == 0 & R.localization == l), R.targetDeposition_pct(k & R.wind == 1 & R.localization == l)];
            plot(ax, [0 1], y, '-o', 'LineWidth', 1.6, 'DisplayName', l);
        end
        set(ax, 'XTick', [0 1], 'XTickLabel', {'no wind', 'wind 2 m/s + gusts'}); xlim(ax, [-0.2 1.2]);
        ylabel(ax, 'target deposition (%)'); grid(ax, 'on'); title(ax, lab(i)); legend(ax, 'Location', 'best');
    end
    title(tl, 'Wind x localization (non-parallel lines = CANDIDATE interaction; 1 seed, no inference)');
    exportgraphics(fh, fullfile(figDir, '02_interaction.png'), 'Resolution', 150); close(fh);
    % 3 outcome by pipeline
    conds = ["no wind | oracle", "no wind | sensorFusion", "wind | oracle", "wind | sensorFusion"];
    Y = zeros(height(cfgs), 4);
    for i = 1:height(cfgs)
        k = R.controller == cfgs.controller(i) & R.compensation == cfgs.compensation(i);
        Y(i, :) = [R.targetDeposition_pct(k & R.wind == 0 & R.localization == "groundTruthOracle"), ...
                   R.targetDeposition_pct(k & R.wind == 0 & R.localization == "sensorFusion"), ...
                   R.targetDeposition_pct(k & R.wind == 1 & R.localization == "groundTruthOracle"), ...
                   R.targetDeposition_pct(k & R.wind == 1 & R.localization == "sensorFusion")];
    end
    fh = figure('Visible', 'off', 'Position', [50 50 1100 480], 'Color', 'w');
    ax = axes(fh); bar(ax, categorical(lab, lab), Y); grid(ax, 'on');
    ylabel(ax, 'target deposition (% of emitted)'); legend(ax, conds, 'Location', 'northeastoutside');
    title(ax, 'Target deposition by configuration and condition (simulated, UNCALIBRATED)');
    exportgraphics(fh, fullfile(figDir, '03_outcome_by_pipeline.png'), 'Resolution', 150); close(fh);
end

function writeReport(o, fn, rc)
    R = o.runs; IT = o.interactions; CT = o.contrasts; AS = o.associations; SC = o.sanity; BT = o.bottleneck;
    L = {'# Error-propagation pilot (error_propagation_pilot_v1)', '', ...
        '> PILOT: one field, one seed set, 16 paired missions. Simulated, currently UNCALIBRATED spray model, synthetic', ...
        '> sensors, assumed hardware. Descriptive only - no significance, no real-world claim.', '', ...
        sprintf('Runtime %.0f s. Sanity checks: %s (sanity_checks.csv).', o.runtime_s, ifelse(all(SC.pass), 'ALL PASS', 'FAILURES - results invalid')), '', ...
        '## Runs', '', ...
        '| run | wind | localization | controller | comp. | loc RMSE (m) | cross-track RMSE (m) | geoloc (m) | exec (m) | release total (m) | landing (m) | bias (m) | scatter (m) | deposition (%) | treated (%) |', ...
        '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'};
    for i = 1:height(R)
        L{end+1} = sprintf('| %s | %d | %s | %s | %s | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.1f | %.1f |', R.run(i), R.wind(i), ...
            R.localization(i), R.controller(i), R.compensation(i), R.loc_rmse_m(i), R.track_rmse_m(i), R.geoloc_mean_m(i), ...
            R.release_exec_mean_m(i), R.release_total_mean_m(i), R.landing_mean_m(i), R.landingBias_mean_m(i), R.landingScatter_mean_m(i), ...
            R.targetDeposition_pct(i), R.treatmentSuccess_pct(i)); %#ok<AGROW>
    end
    L = [L, {'', 'geoloc = |recorded - true plant|; exec = |actual release - commanded release|; release total = |actual - (true plant + compensation offset)|;', ...
        sprintf(['landing = mean over spray steps of |release position + drift(instantaneous wind incl. gusts) - true plant| ' ...
        '(same functions as the engine deposition: advancedDrift, windVector); bias = |mean landing point - plant|; ' ...
        'scatter = RMS spread of landing points (gust-driven). Canopy radius = %.1f m.'], rc), '', ...
        '## A. Contrasts (Y_after - Y_before)', '', ...
        '| controller | comp. | contrast | d loc RMSE (m) | d cross RMSE (m) | d release (m) | d landing (m) | d deposition (pp) | d treated (pp) |', '|---|---|---|---|---|---|---|---|---|'}];
    for i = 1:height(CT)
        L{end+1} = sprintf('| %s | %s | %s | %+.3f | %+.3f | %+.3f | %+.3f | %+.1f | %+.1f |', CT.controller(i), CT.compensation(i), CT.contrast(i), ...
            CT.d_loc_rmse_m(i), CT.d_track_rmse_m(i), CT.d_release_total_mean_m(i), CT.d_landing_mean_m(i), CT.d_targetDeposition_pp(i), CT.d_treatmentSuccess_pp(i)); %#ok<AGROW>
    end
    L = [L, {'', '## B. Wind x localization difference-in-differences (CANDIDATE interactions only)', '', ...
        '| controller | comp. | metric | noWind oracle | wind oracle | noWind SF | wind SF | DiD |', '|---|---|---|---|---|---|---|---|'}];
    for i = 1:height(IT)
        L{end+1} = sprintf('| %s | %s | %s | %.3f | %.3f | %.3f | %.3f | %+.3f |', IT.controller(i), IT.compensation(i), IT.metric(i), ...
            IT.noWind_oracle(i), IT.wind_oracle(i), IT.noWind_sensorFusion(i), IT.wind_sensorFusion(i), IT.interaction_DiD(i)); %#ok<AGROW>
    end
    L = [L, {'', '## C. Descriptive associations (no inference)', '', '| level | x | y | n | Pearson | Spearman |', '|---|---|---|---|---|---|'}];
    for i = 1:height(AS)
        L{end+1} = sprintf('| %s | %s | %s | %d | %.2f | %.2f |', AS.level(i), AS.x(i), AS.y(i), AS.n(i), AS.pearson(i), AS.spearman(i)); %#ok<AGROW>
    end
    L = [L, {'', '## D. Bottleneck diagnostic', '', ...
        sprintf(['Normalization (explicit): geometric stages = increase over the clean reference (no wind + oracle, same controller / ' ...
        'compensation) divided by the canopy radius %.1f m; deposition = relative loss (ref - run) / ref. The largest geometric ' ...
        'stage is reported; deposition is reported separately (different unit, not combined into one score).'], rc), '', ...
        '| run | ctrl | comp. | wind | localization | loc | tracking | release | landing | deposition rel. loss | largest geometric stage |', '|---|---|---|---|---|---|---|---|---|---|---|'}];
    for i = 1:height(BT)
        L{end+1} = sprintf('| %s | %s | %s | %d | %s | %+.2f | %+.2f | %+.2f | %+.2f | %+.2f | %s |', BT.run(i), BT.controller(i), BT.compensation(i), ...
            BT.wind(i), BT.localization(i), BT.loc_norm(i), BT.tracking_norm(i), BT.release_norm(i), BT.landing_norm(i), BT.deposition_relLoss(i), BT.largestGeometricStage(i)); %#ok<AGROW>
    end
    L = [L, {'', '## Sanity checks', '', '| check | pass | detail |', '|---|---|---|'}];
    for i = 1:height(SC), L{end+1} = sprintf('| %s | %s | %s |', SC.check{i}, ifelse(SC.pass(i), 'PASS', 'FAIL'), SC.detail{i}); end %#ok<AGROW>
    L = [L, {'', '## Metrics NOT available / caveats', '', ...
        '- Obstacle violation: no obstacles in this pilot field (reported as 0 by construction).', ...
        '- Actuator timing error: valve delay 0 and the actuation model is off, so it is 0 by construction (sanity check only).', ...
        '- Landing error is reconstructed from the logged dwell states with the engine''s own drift functions (evaluated at the logged step, i.e. within one 0.1 s step of the deposit call); the deposition grid itself is not decomposed per target because sprays overlap.', ...
        '- Mass residual = emitted - deposited on grid - evaporated: mass beyond the 4-sigma kernel window / grid edge (by design of depositSpray), not a conservation failure; conservation itself is checked by MassEnergySprayConservationTest.', ...
        '- NEES uses the synthetic sensor model; oracle runs have no NEES.', '', ...
        '<!-- ANALYST ANSWERS: written after reviewing the tables above -->'}];
    fid = fopen(fn, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
end

function r = pearson(x, y)
    ok = ~isnan(x) & ~isnan(y); x = x(ok); y = y(ok);
    if numel(x) < 3 || std(x) == 0 || std(y) == 0, r = NaN; return; end
    C = corrcoef(x, y); r = C(1, 2);
end

function rk = rankavg(x)
%RANKAVG Ranks with ties averaged (Spearman = Pearson of these ranks).
    rk = nan(size(x)); ok = ~isnan(x); v = x(ok);
    [~, o] = sort(v); r = zeros(size(v)); r(o) = 1:numel(v);
    [u, ~, g] = unique(v);
    for i = 1:numel(u), m = g == i; r(m) = mean(r(m)); end
    rk(ok) = r;
end

function s = ifelse(c, a, b), if c, s = a; else, s = b; end, end

function h = gitHead(here)
    [st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', here));
    if st ~= 0, h = 'unknown'; end
    h = strtrim(h);
end
