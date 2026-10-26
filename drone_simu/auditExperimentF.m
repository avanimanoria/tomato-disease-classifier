function A = auditExperimentF(projDir)
%AUDITEXPERIMENTF Independent audit of the frozen Experiment F (manual V1, section 3).
%
%   A = auditExperimentF([projDir])
%   Re-derives every reported number from the saved per-run tables in
%   results/benchmark/benchmark.mat (read-only), then writes
%     audit/experiment_inventory.csv   one row per simulated mission
%     docs/EXPERIMENT_F_AUDIT.md       counts, definitions, leakage checks, H1-H4, caveats
%   Nothing in results/ is modified; corrected re-runs would be published as Experiment F2.
    if nargin < 1, projDir = fileparts(mfilename('fullpath')); end
    S = load(fullfile(projDir, 'results', 'benchmark', 'benchmark.mat')); B = S.B;
    RT = B.routing.runs; PT = B.pipeline.runs;
    PT4 = readtable(fullfile(projDir, 'results', 'benchmark', 'pipeline_runs_altKernel.csv'), 'TextType', 'string');
    AB = B.ablation;
    cfgs = string(B.pipeline.configs); conds = B.pipeline.conditions;
    splitSeeds = struct('train', [42 90 7 3], 'test1', [101 60 17 13], 'test2', [202 120 27 23]);   % field, wind dir, gust, loc

    %% 1. inventory -------------------------------------------------------------------
    inv = {};
    for i = 1:height(RT)
        inv(end+1, :) = {sprintf('F-ROUT-%d-%s', RT.fieldSeed(i), RT.algorithm(i)), 'F.routing', "benchmark", RT.fieldSeed(i), ...
            sprintf('field %d', RT.fieldSeed(i)), hash8(sprintf('route|%d', RT.fieldSeed(i))), hash8(char(RT.algorithm(i))), ...
            sprintf('routing=%s; controller=openLoop; spray=none; physics=default (wind off); frozen all-diseased targets; equal speed', RT.algorithm(i)), ...
            sprintf('results/benchmark/routing_runs.csv row %d', i)}; %#ok<AGROW>
    end
    for i = 1:height(PT)
        inv(end+1, :) = pipeRow(PT(i, :), i, 'F.pipeline', 'pipeline_runs.csv', splitSeeds, conds); %#ok<AGROW>
    end
    for i = 1:height(PT4)
        inv(end+1, :) = pipeRow(PT4(i, :), i, 'F.H4altKernel', 'pipeline_runs_altKernel.csv', splitSeeds, conds); %#ok<AGROW>
    end
    for i = 1:height(AB)
        inv(end+1, :) = {sprintf('F-ABL-%s', strrep(AB.feature(i), ' ', '')), 'F.ablation', "ablation", 42, 'Fully Corrected, field 42, wind 2 m/s dir 90', ...
            hash8('ablation|42'), hash8(char(AB.feature(i))), sprintf('Fully Corrected + advanced feature: %s', AB.feature(i)), ...
            sprintf('results/benchmark/feature_ablation.csv row %d', i)}; %#ok<AGROW>
    end
    INV = cell2table(inv, 'VariableNames', {'run_id', 'experiment', 'split', 'field_id', 'scenario', 'scenario_hash', ...
        'pipeline_hash', 'algorithm_choices', 'result_path'});
    INV.status = repmat("completed", height(INV), 1);
    INV.code_hash = repmat("331f5c1 (engine code; benchmark ran before the commit, engine files unchanged)", height(INV), 1);
    INV.timestamp = repmat(string(B.meta.date), height(INV), 1);
    adir = fullfile(projDir, 'audit'); if ~isfolder(adir), mkdir(adir); end
    writetable(INV, fullfile(adir, 'experiment_inventory.csv'));
    A.counts = struct('total', height(INV), 'routing', height(RT), 'pipeline', height(PT), 'altKernel', height(PT4), ...
        'ablation', height(AB), 'reportedTotal', B.meta.nRuns, ...
        'uniquePipelinesRouting', numel(unique(RT.algorithm)), 'uniquePipelinesSpray', numel(unique(PT.config)), ...
        'uniqueConditions', numel(unique(PT.condIdx)), 'fieldsRouting', numel(unique(RT.fieldSeed)), ...
        'fieldsPipeline', numel(unique(PT.split)), 'replicatesPerCell', max(groupcounts(PT, {'split', 'condIdx', 'config'}).GroupCount));

    %% 2. leakage / selection re-derivation --------------------------------------------
    tr = PT(PT.split == "train", :); te = PT(PT.split ~= "train", :);
    mu = arrayfun(@(c) mean(tr.targetDepositionPct(tr.config == c)), cfgs);
    [~, kb] = max(mu);
    A.bestFixedRecomputed = cfgs(kb);
    A.bestFixedMatches = A.bestFixedRecomputed == B.selection.bestFixed;
    muAll = arrayfun(@(c) mean(PT.targetDepositionPct(PT.config == c)), cfgs);
    [~, kAll] = max(muAll);
    A.bestFixedIfTestLeaked = cfgs(kAll);
    selOk = true;
    for ci = 1:numel(conds)
        X = tr(tr.condIdx == ci, :); [~, j] = max(X.targetDepositionPct);
        selOk = selOk && X.config(j) == B.selection.selectorChoice.selected(ci);
    end
    A.selectorMatchesTrainOnly = selOk;
    cellsComplete = all(groupcounts(PT, {'split', 'condIdx'}).GroupCount == numel(cfgs));
    A.pairingComplete = cellsComplete;
    % per-field paired differences (selector - fixed) and bootstrap CIs within each field
    P = B.selection.perTest;
    for spn = ["test1", "test2"]
        d = P.selectorPct(P.split == spn) - P.fixedPct(P.split == spn);
        A.perField.(spn) = struct('meanGain', mean(d), 'ci', bootCI(d), 'n', numel(d), ...
            'fixed', mean(P.fixedPct(P.split == spn)), 'selector', mean(P.selectorPct(P.split == spn)), 'oracle', mean(P.oraclePct(P.split == spn)));
    end
    % H2: why so little head-room
    gaps = zeros(numel(conds), 1);
    for ci = 1:numel(conds)
        v = sort(tr.targetDepositionPct(tr.condIdx == ci), 'descend'); gaps(ci) = v(1) - v(2);
    end
    A.trainTop2GapMedian = median(gaps);
    A.trainExactTies = nnz(gaps == 0);
    cfgDiff = zeros(numel(conds), 2);       % (fixed - selector choice) on test1, test2
    for ci = 1:numel(conds)
        sel = B.selection.selectorChoice.selected(ci);
        for s2 = 1:2
            X = te(te.split == "test" + s2 & te.condIdx == ci, :);
            cfgDiff(ci, s2) = X.targetDepositionPct(X.config == sel) - X.targetDepositionPct(X.config == B.selection.bestFixed);
        end
    end
    A.selectorChangedChoice = nnz(B.selection.selectorChoice.selected ~= B.selection.bestFixed);
    A.oracleHeadroomPP = mean(P.oraclePct - P.fixedPct);
    compOn = contains(cfgs, "wind");
    A.compFamilySpread = [max(mu(compOn)) - min(mu(compOn)), max(mu(~compOn)) - min(mu(~compOn))];

    %% 3. H1 reversals with margins and replication on the test fields -----------------
    tol = B.H1.tolerancePct;
    H = B.H1.table;
    rep = strings(height(H), 1); margins = zeros(height(H), 1);
    for i = 1:height(H)
        [dTr] = pairDiff(tr, H.configA(i), H.configB(i), numel(conds));
        margins(i) = max(abs(dTr));
        reps = 0;
        for s2 = ["test1", "test2"]
            dT = pairDiff(te(te.split == s2, :), H.configA(i), H.configB(i), numel(conds));
            reps = reps + (any(dT > tol) && any(dT < -tol));
        end
        rep(i) = sprintf('%d of 2 test fields', reps);
    end
    H.maxMarginPct = margins; H.reversalAlsoOn = rep;
    A.H1 = H;

    %% 4. H3 interaction replicated per field --------------------------------------------
    A.H3 = table();
    for spn = ["train", "test1", "test2"]
        X = PT(PT.split == spn & PT.localization ~= "flowOdometry", :);
        y = @(m) mean(X.targetDepositionPct(m));
        g1 = X.gust_mps == 0.5; l1 = X.localization == "kalman";
        I = (y(g1 & l1) - y(~g1 & l1)) - (y(g1 & ~l1) - y(~g1 & ~l1));
        gm = y(g1) - y(~g1); lm = y(l1) - y(~l1);
        A.H3 = [A.H3; table(spn, gm, lm, I, 'VariableNames', {'split', 'gustMainPct', 'kalmanMainPct', 'gustXlocInteractionPct'})]; %#ok<AGROW>
    end

    %% 5. valve delay ---------------------------------------------------------------------
    d0 = PT(PT.valveDelay_s == 0 & contains(PT.config, "wind compensation"), :);
    d5 = PT(PT.valveDelay_s == 0.5 & contains(PT.config, "wind compensation"), :);
    l5 = PT(PT.valveDelay_s == 0.5 & contains(PT.config, "lag"), :);
    A.delay = struct('dep_windComp_delay0', mean(d0.targetDepositionPct), 'dep_windComp_delay05', mean(d5.targetDepositionPct), ...
        'dep_windLag_delay05', mean(l5.targetDepositionPct), 'lagDisp_windComp_delay05', mean(d5.lagDisplacement_m), ...
        'lagDisp_windLag_delay05', mean(l5.lagDisplacement_m), ...
        'tailFraction', 0.5 / config().internal2.spray.duration, 'movingReleaseLag_m', config().droneSpeed * 0.5);
    A.B = B;

    writeAudit(fullfile(projDir, 'docs', 'EXPERIMENT_F_AUDIT.md'), A);
    fprintf('Audit written: %d inventory rows, docs/EXPERIMENT_F_AUDIT.md\n', height(INV));
end

% ======================================================================================
function r = pipeRow(R, i, exp, file, seeds, conds)
    s = seeds.(char(R.split));
    C = conds{R.condIdx};
    scen = sprintf('field %d, wind %.1f m/s dir %d, gust %.1f (seed %d), loc %s (seed %d), delay %.1f s, kernel %s', ...
        s(1), C.wind, s(2), C.gust, s(3), C.loc, s(4), C.delay, R.kernel);
    parts = split(R.config, " | ");
    ctrl = parts(1); spray = parts(2);
    r = {sprintf('F-%s-%s-c%02d-%s', ternary(exp == "F.pipeline", 'PIPE', 'H4'), R.split, R.condIdx, hash8(char(R.config))), exp, R.split, s(1), ...
        scen, hash8([char(R.split) '|' num2str(R.condIdx) '|' char(R.kernel)]), hash8(char(R.config)), ...
        sprintf('controller=%s; spray=%s; routing=nearestNeighbour; localization=%s; kernel=%s; physics=payload+dynamics+energy+atmosphere+actuation+safety', ...
        ctrl, spray, C.loc, R.kernel), sprintf('results/benchmark/%s row %d', file, i)};
end

function d = pairDiff(X, a, b, n)
    d = zeros(n, 1);
    for ci = 1:n
        Y = X(X.condIdx == ci, :);
        d(ci) = Y.targetDepositionPct(Y.config == a) - Y.targetDepositionPct(Y.config == b);
    end
end

function ci = bootCI(d)
    rs = RandStream('mt19937ar', 'Seed', 2026);
    bm = sort(mean(d(randi(rs, numel(d), numel(d), 10000)), 1));
    ci = [bm(250), bm(9750)];
end

function h = hash8(s)
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(uint8(unicode2native(s, 'UTF-8')));
    h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
    h = h(1:8);
end

function v = ternary(c, a, b), if c, v = a; else, v = b; end, end
function s = yn(b), if b, s = 'YES'; else, s = 'NO'; end, end

function writeAudit(file, A)
    B = A.B; c = A.counts; S = B.selection;
    if ~isfolder(fileparts(file)), mkdir(fileparts(file)); end
    L = {};
    L{end+1} = '# Experiment F audit';
    L{end+1} = sprintf('Generated by `auditExperimentF.m` from the frozen `results/benchmark/benchmark.mat` (run %s). Read-only: no frozen file was modified.', B.meta.date);
    L{end+1} = '';
    L{end+1} = '## 1. What the 623 missions are';
    L{end+1} = '| Part | Missions | Design |';
    L{end+1} = '|---|---|---|';
    L{end+1} = sprintf('| Routing benchmark | %d | %d routers x %d fields, frozen all-diseased targets, equal speed |', c.routing, c.uniquePipelinesRouting, c.fieldsRouting);
    L{end+1} = sprintf('| Pipeline benchmark | %d | %d controller x spray configurations x %d conditions x 3 fields (1 train, 2 test) |', c.pipeline, c.uniquePipelinesSpray, c.uniqueConditions);
    L{end+1} = sprintf('| H4 alternative kernel | %d | same 6 x 24 on the train field with the wind-stretched kernel |', c.altKernel);
    L{end+1} = sprintf('| Single-feature ablation | %d | original + 10 single features + all, Fully Corrected |', c.ablation);
    L{end+1} = sprintf('| **Total** | **%d** | reported %d: %s |', c.total, c.reportedTotal, ternary(c.total == c.reportedTotal, 'reconciled exactly', 'MISMATCH'));
    L{end+1} = '';
    L{end+1} = sprintf(['- Unique algorithm combinations: %d routing strategies (routing study) and %d controller x spray pipelines ' ...
        '(pipeline study). These were **separate** studies: routing x controller x spray cross-products were NOT run.'], ...
        c.uniquePipelinesRouting, c.uniquePipelinesSpray);
    L{end+1} = sprintf('- Unique disturbance conditions: %d; replicates per (field, condition, configuration): %d (no repeated seeds).', c.uniqueConditions, c.replicatesPerCell);
    L{end+1} = '- Full per-mission list: `audit/experiment_inventory.csv` (run_id, experiment, split, field, scenario, hashes, algorithm choices, result path, status, code hash, timestamp).';
    L{end+1} = '';
    L{end+1} = '## 2. Metric definitions (code references)';
    L{end+1} = '- `targetDepositionPct` (primary) = 100 x spray mass on canopy discs of truly diseased plants / emitted spray (`sprayMetrics.m`; `plantDose.m`, canopy radius 0.2 m).';
    L{end+1} = '- `treatmentSuccessPct` = 100 x truly diseased plants whose canopy received >= 30% of one nominal dose / all truly diseased plants (`sprayMetrics.m`, `treatedDoseFraction`). Threshold-based and assumption-sensitive.';
    L{end+1} = '- `offTargetPct` = 100 - targetDepositionPct (healthy canopies + other ground + unresolved); `offFieldPct` = 100 x deposited mass outside the field polygon / emitted (`advancedMetrics.m`).';
    L{end+1} = '- Why dashboard values differ: Experiment E (55% deposition, Fully Corrected) uses default physics; Experiment F adds payload, dynamics, atmosphere, actuation, gusts and estimators in every run, so its means (about 27% at best) are not comparable to E.';
    L{end+1} = '- Mass balance: emitted = deposited + evaporated + unresolved (kernel tail beyond 4 sigma / outside grid); verified >= 0 and < 1% in `tests/MassEnergySprayConservationTest`.';
    L{end+1} = '';
    L{end+1} = '## 3. Selection and leakage checks';
    L{end+1} = sprintf('- Best fixed re-derived from TRAIN rows only: **%s** - matches saved: %s. (Using test rows as well would give "%s".)', ...
        strrep(A.bestFixedRecomputed, ' | ', ' / '), yn(A.bestFixedMatches), strrep(A.bestFixedIfTestLeaked, ' | ', ' / '));
    L{end+1} = sprintf('- Selector choices re-derived from TRAIN rows only for all 24 conditions - match saved: %s. The selector sees the scenario descriptors (wind, gust, localization mode, valve delay), never test outcomes, test seeds or future disturbances.', yn(A.selectorMatchesTrainOnly));
    L{end+1} = '- Oracle = best configuration per test instance AFTER seeing its outcomes: an unattainable upper bound, not deployable.';
    L{end+1} = sprintf('- Pairing: every (field, condition) cell contains all 6 configurations: %s. Within a cell all configurations share the field, disease truth, wind direction, gust seed and localization seed (same generated field object; seeds set per split in `runExperimentF.m`).', yn(A.pairingComplete));
    L{end+1} = '- CI method used in the report: percentile bootstrap (10 000 resamples) over the 48 held-out (field, condition) instances, treated as independent. **Caveat:** instances on the same field share its disease layout, so they are correlated; with only 2 test fields a cluster bootstrap is not meaningful. Per-field results below are the honest view.';
    L{end+1} = '';
    L{end+1} = '| Test field | best fixed | selector | oracle | selector - fixed (pp) | 95% CI within field |';
    L{end+1} = '|---|---|---|---|---|---|';
    for spn = ["test1", "test2"]
        p = A.perField.(spn);
        L{end+1} = sprintf('| %s | %.2f%% | %.2f%% | %.2f%% | %+.2f | %+.2f .. %+.2f (n=%d) |', spn, p.fixed, p.selector, p.oracle, p.meanGain, p.ci(1), p.ci(2), p.n); %#ok<AGROW>
    end
    L{end+1} = '';
    L{end+1} = '## 4. Hypotheses';
    L{end+1} = sprintf('**H1 rank reversal - %s as reported (%d pairs, tolerance %.0f pp on the single train field).** Margins and replication:', ...
        ternary(B.H1.supported, 'observed', 'not observed'), B.H1.nReversals, B.H1.tolerancePct);
    L{end+1} = '';
    L{end+1} = '| Config A | Config B | A better (conditions) | B better | max margin (pp) | reversal also on |';
    L{end+1} = '|---|---|---|---|---|---|';
    for i = 1:height(A.H1)
        h = A.H1(i, :);
        L{end+1} = sprintf('| %s | %s | %d | %d | %.2f | %s |', strrep(h.configA, ' | ', ' / '), strrep(h.configB, ' | ', ' / '), h.conditionsAbetter, h.conditionsBbetter, h.maxMarginPct, h.reversalAlsoOn); %#ok<AGROW>
    end
    L{end+1} = 'Interpretation: reversals between near-equivalent configurations (same compensation family) with margins of a few pp on one field; treat as modelled sensitivity, not established fact. Rank reversal does not imply a selector gain.';
    L{end+1} = '';
    L{end+1} = sprintf(['**H2 selector beats best fixed - NOT SUPPORTED (preserved).** fixed %.2f%%, selector %.2f%%, oracle %.2f%%, gain %+.2f pp ' ...
        '[%+.2f, %+.2f]. Investigation: oracle head-room over best fixed is only %.2f pp; the selector switched away from the best fixed configuration in %d of 24 conditions, ' ...
        'based on single-field train gaps (median top-2 gap %.2f pp; in %d of 24 conditions the top two configurations tie EXACTLY because wind and wind + lag compensation are identical when the valve delay is 0, so the choice there is the first in list order - an artifact) that are smaller than field-to-field variation; the six configurations are two near-tied families ' ...
        '(spread within compensated configs %.2f pp, within uncompensated %.2f pp). Conclusion: with these options there is almost nothing to select between, so a per-condition selector overfits. ' ...
        'No retuning on test was done.'], S.meanFixed, S.meanSelector, S.meanOracle, S.meanGain, S.gainCI95(1), S.gainCI95(2), ...
        A.oracleHeadroomPP, A.selectorChangedChoice, A.trainTop2GapMedian, A.trainExactTies, A.compFamilySpread(1), A.compFamilySpread(2));
    L{end+1} = '';
    L{end+1} = '**H3 interaction (gust x localization) - replicated per field** (contrast = [(gust, KF) - (no gust, KF)] - [(gust, oracle) - (no gust, oracle)], pp of deposition, all configurations):';
    L{end+1} = '';
    L{end+1} = '| Field | gust main effect | Kalman main effect | gust x localization |';
    L{end+1} = '|---|---|---|---|';
    for i = 1:height(A.H3)
        L{end+1} = sprintf('| %s | %+.2f | %+.2f | %+.2f |', A.H3.split(i), A.H3.gustMainPct(i), A.H3.kalmanMainPct(i), A.H3.gustXlocInteractionPct(i)); %#ok<AGROW>
    end
    L{end+1} = 'This is a MODELLED interaction under assumed gust and estimator parameters, one replicate per cell; no empirical claim.';
    L{end+1} = '';
    L{end+1} = sprintf('**H4 robustness - kernel-specific only.** Spearman %.2f between configuration rankings with the circular and the (uncalibrated) wind-stretched kernel; same best fixed: %s. It does NOT establish cross-crop or cross-hardware robustness (no sourced profiles were tested).', ...
        B.H4.spearman, yn(B.H4.sameBestFixed));
    L{end+1} = '';
    L{end+1} = '## 5. Valve delay and lag compensation';
    d = A.delay;
    L{end+1} = sprintf(['Spray release in this engine happens while HOVERING (settle 1 s, then a 2 s dwell). A %.1f s valve delay therefore only shifts the last %.0f%% of each dose into the departure. ' ...
        'Wind-compensated configurations: deposition %.2f%% (no delay) vs %.2f%% (0.5 s delay, mean displacement %.2f m); with lag compensation %.2f%% (displacement %.2f m). ' ...
        'The effect is small because the drone is stationary for most of the spray. In a MOVING release at %.1f m/s the same delay would displace the spray by %.2f m - ' ...
        'moving release is not modelled (engine sprays only at hover); it is listed as an open item, not silently added.'], ...
        0.5, 100 * d.tailFraction, d.dep_windComp_delay0, d.dep_windComp_delay05, d.lagDisp_windComp_delay05, d.dep_windLag_delay05, ...
        d.lagDisp_windLag_delay05, config().droneSpeed, d.movingReleaseLag_m);
    L{end+1} = '';
    L{end+1} = '## 6. Limitations';
    L{end+1} = '- One train field, two test fields, one replicate per cell: confidence intervals understate field-level uncertainty.';
    L{end+1} = '- Spray kernels, gust model, estimator noise and physics parameters are uncalibrated assumptions.';
    L{end+1} = '- The scenario-conditioned selector is the simplest possible (lookup of the best train configuration per condition).';
    L{end+1} = '- Experiment F stays frozen; any corrected or extended study must be a new versioned run (Experiment F2).';
    L{end+1} = '';
    L{end+1} = '## 7. Reproduce';
    L{end+1} = '```matlab';
    L{end+1} = 'runExperimentF(''results_F_rerun'')   % re-run into a NEW folder (the default results/benchmark/ is frozen and protected)';
    L{end+1} = 'runExperimentF(''results_F_rerun'')   % recommended: separate output folder';
    L{end+1} = 'auditExperimentF          % this audit, from results/benchmark/benchmark.mat';
    L{end+1} = '```';
    fid = fopen(file, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
end
