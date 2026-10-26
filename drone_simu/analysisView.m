function h = analysisView(parent, projDir)
%ANALYSISVIEW Read-only comparative analysis of all algorithms, experiments and tests.
%
%   analysisView                      % opens its own window
%   analysisView(tabOrPanel)          % builds into an existing container (dashboard tab)
%
%   Reports only what is already saved on disk - nothing is re-simulated here:
%     results/benchmark/*   Experiment F (runExperimentF): routing benchmark, pipeline benchmark,
%                           scenario-conditioned selection, hypotheses H1-H4, feature ablation
%     results/*.csv         Experiments A-E and D2 (main_experiments)
%   This view uses ground-truth evaluation metrics (it is an evaluation/research view, not the
%   Mission screen). "Reload results" only re-reads the files.

    if nargin < 2 || isempty(projDir), projDir = fileparts(mfilename('fullpath')); end
    if nargin < 1 || isempty(parent)
        fig = uifigure('Name', 'Comparative analysis - Internal-2 simulation', 'Position', [40 40 1440 800]);
        parent = uigridlayout(fig, [1 1]);
        parent.Padding = [0 0 0 0];
    end
    root = uigridlayout(parent, [2 1]);
    root.RowHeight = {30, '1x'}; root.Padding = [6 4 6 4]; root.RowSpacing = 4;
    top = uigridlayout(root, [1 3]); top.ColumnWidth = {'1x', 150, 10}; top.Padding = [0 0 0 0];
    hdr = uilabel(top, 'Text', '', 'FontWeight', 'bold', 'FontSize', 13);
    uibutton(top, 'push', 'Text', 'Reload results', 'ButtonPushedFcn', @(~, ~) fill());
    tabs = uitabgroup(root);
    h.tabs = tabs; h.header = hdr;
    fill();

    function fill()
        delete(tabs.Children);
        benchFile = fullfile(projDir, 'results', 'benchmark', 'benchmark.mat');
        if isfile(benchFile)
            S = load(benchFile); B = S.B;
            hdr.Text = sprintf('Experiment F benchmark: %s | %d simulated missions | %.0f min%s | all values simulated, uncalibrated', ...
                B.meta.date, B.meta.nRuns, B.meta.runtime_s / 60, ternary(B.meta.quick, ' (QUICK)', ''));
            summaryTab(B);
            routingTab(B);
            pipelineTab(B);
            selectionTab(B);
            disturbanceTab(B);
        else
            hdr.Text = 'Benchmark results not available yet - Experiments A-E and the gap status are shown below.';
            t = uitab(tabs, 'Title', 'Summary');
            g = uigridlayout(t, [2 1]); g.RowHeight = {190, '1x'}; g.Padding = [12 10 12 10];
            uilabel(g, 'VerticalAlignment', 'top', 'WordWrap', 'on', 'FontSize', 13, 'Text', { ...
                'The algorithm benchmark (Experiment F) has not finished, or has not been run on this computer.', ...
                ['Expected file: ' fullfile(projDir, 'results', 'benchmark', 'benchmark.mat')], '', ...
                'To create it, run in the MATLAB command window:   runExperimentF      (about 30-40 minutes)', ...
                'then press "Reload results" (top right). Nothing is simulated by this view.', '', ...
                'When available, these tabs appear: Routing algorithms | Spray pipelines | Selection (H1, H2) | Disturbances (H3, H4, ablation).'});
            sub = uigridlayout(g, [2 1]); sub.RowHeight = {22, '1x'}; sub.Padding = [0 0 0 0];
            uilabel(sub, 'Text', 'Already available - saved results of Experiments A-E:', 'FontWeight', 'bold');
            uitable(sub, 'Data', experimentHeadlines(projDir), 'ColumnName', {'Experiment', 'Comparison', 'Result', 'Source file'}, ...
                'ColumnWidth', {140, 520, 420, 'auto'});
        end
        experimentsTab();
        methodTab();
    end

    % ------------------------------------------------------------------ tabs
    function summaryTab(B)
        t = uitab(tabs, 'Title', 'Summary');
        g = uigridlayout(t, [1 1]); g.Padding = [6 6 6 6];
        uitextarea(g, 'Value', B.report, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 11);
    end

    function routingTab(B)
        t = uitab(tabs, 'Title', 'Routing algorithms');
        g = uigridlayout(t, [2 2]); g.RowHeight = {'1x', '1x'}; g.ColumnWidth = {'1.3x', '1x'};
        T = B.routing.summary;
        tb = uitable(g, 'Data', roundTable(T, 2), 'ColumnName', T.Properties.VariableNames);
        tb.Layout.Row = 1; tb.Layout.Column = [1 2];
        ax = uiaxes(g); ax.Layout.Row = 2; ax.Layout.Column = 1;
        bar(ax, categorical(T.algorithm, T.algorithm), [T.geometric_m, T.flown_m]);
        hold(ax, 'on');
        errorbar(ax, (1:height(T)) - 0.15, T.geometric_m, T.geometricCI95_m, 'k.', 'HandleVisibility', 'off');
        ylabel(ax, 'Pass-2 route (m)'); legend(ax, {'geometric', 'flown'}, 'Location', 'northeast');
        title(ax, sprintf('Same frozen targets, %d fields, equal speed (95%% CI)', T.nFields(1)));
        ax2 = uiaxes(g); ax2.Layout.Row = 2; ax2.Layout.Column = 2;
        bar(ax2, categorical(T.algorithm, T.algorithm), T.vsNearestNeighbourPct);
        ylabel(ax2, 'Route length vs nearest-neighbour (%)'); title(ax2, 'Relative route length (negative = shorter)');
        grid(ax2, 'on');
    end

    function pipelineTab(B)
        t = uitab(tabs, 'Title', 'Spray pipelines');
        g = uigridlayout(t, [2 2]); g.RowHeight = {'1x', '1.1x'}; g.ColumnWidth = {'1.4x', '1x'};
        T = B.pipeline.summary;
        tb = uitable(g, 'Data', roundTable(T, 2), 'ColumnName', T.Properties.VariableNames);
        tb.Layout.Row = 1; tb.Layout.Column = [1 2];
        ax = uiaxes(g); ax.Layout.Row = 2; ax.Layout.Column = 1;
        cfgs = unique(T.config, 'stable');
        tr = arrayfun(@(c) pick(T, c, "train", 'targetDepositionPct'), cfgs);
        te = arrayfun(@(c) pick(T, c, "test", 'targetDepositionPct'), cfgs);
        bar(ax, categorical(cfgs, cfgs), [tr te]);
        ylabel(ax, 'Target deposition (% of emitted)'); legend(ax, {'train', 'held-out test'}, 'Location', 'northwest');
        title(ax, 'Primary metric by configuration (24 disturbance conditions each)'); grid(ax, 'on');
        pg = uigridlayout(g, [2 1]); pg.Layout.Row = 2; pg.Layout.Column = 2; pg.RowHeight = {24, '1x'};
        uilabel(pg, 'Text', 'Pareto-optimal on test (deposition up; off-field, energy, time down):', 'FontWeight', 'bold');
        uitable(pg, 'Data', roundTable(B.pipeline.pareto, 2), 'ColumnName', B.pipeline.pareto.Properties.VariableNames);
    end

    function selectionTab(B)
        t = uitab(tabs, 'Title', 'Selection (H1, H2)');
        S = B.selection;
        g = uigridlayout(t, [3 2]); g.RowHeight = {60, '1x', '1x'}; g.ColumnWidth = {'1.5x', '1x'};
        msg = sprintf(['Best fixed (train): %s.  Held-out test mean deposition: fixed %.2f%% | selector %.2f%% | oracle %.2f%%.\n' ...
            'Selector gain %+.2f pp (95%% bootstrap CI %+.2f .. %+.2f), wins / ties / losses %d / %d / %d.  H2: %s.  H1 rank reversals: %d pair(s).'], ...
            S.bestFixed, S.meanFixed, S.meanSelector, S.meanOracle, S.meanGain, S.gainCI95(1), S.gainCI95(2), ...
            S.wins, S.ties, S.losses, supp(S.H2supported), B.H1.nReversals);
        l = uilabel(g, 'Text', msg, 'WordWrap', 'on', 'FontWeight', 'bold'); l.Layout.Column = [1 2];
        tb = uitable(g, 'Data', roundTable(S.perTest, 2), 'ColumnName', S.perTest.Properties.VariableNames);
        tb.Layout.Row = [2 3]; tb.Layout.Column = 1;
        ax = uiaxes(g); ax.Layout.Row = 2; ax.Layout.Column = 2;
        bar(ax, categorical({'best fixed', 'selector', 'oracle'}, {'best fixed', 'selector', 'oracle'}), ...
            [S.meanFixed, S.meanSelector, S.meanOracle]);
        ylabel(ax, 'Test mean deposition (%)'); title(ax, 'Held-out evaluation'); grid(ax, 'on');
        tb2 = uitable(g, 'Data', roundTable(B.H1.table, 2), 'ColumnName', B.H1.table.Properties.VariableNames);
        tb2.Layout.Row = 3; tb2.Layout.Column = 2;
    end

    function disturbanceTab(B)
        t = uitab(tabs, 'Title', 'Disturbances (H3, H4, ablation)');
        g = uigridlayout(t, [2 3]); g.RowHeight = {'1x', '1x'};
        tb = uitable(g, 'Data', roundTable(B.H3.table, 2), 'ColumnName', B.H3.table.Properties.VariableNames);
        tb.Layout.Row = [1 2]; tb.Layout.Column = 1;
        ax = uiaxes(g); ax.Layout.Row = 1; ax.Layout.Column = [2 3];
        A = B.ablation;
        bar(ax, categorical(A.feature, A.feature), [A.targetDepositionPct, A.treatmentSuccessPct]);
        ylabel(ax, '%'); legend(ax, {'target deposition', 'treated diseased'}, 'Location', 'northeast');
        title(ax, 'Single-feature ablation on Fully Corrected (one realistic effect at a time)'); grid(ax, 'on');
        tb2 = uitable(g, 'Data', roundTable(B.H4.configMeans, 2), 'ColumnName', B.H4.configMeans.Properties.VariableNames);
        tb2.Layout.Row = 2; tb2.Layout.Column = 2;
        uilabel(g, 'WordWrap', 'on', 'VerticalAlignment', 'top', 'Text', { ...
            sprintf('H3 interactions: %s', supp(B.H3.supported)), ...
            sprintf('Largest: %s = %+.1f pp', B.H3.largestInteraction.term, B.H3.largestInteraction.effectPct), '', ...
            sprintf('H4 kernel robustness: %s', supp(B.H4.supported)), ...
            sprintf('Spearman %.2f, same best fixed: %s, selector agreement %.0f%%', B.H4.spearman, ...
                yesno(B.H4.sameBestFixed), B.H4.selectorAgreementPct), '', ...
            'Effects are in percentage points of target deposition; localization contrast = Kalman vs ground truth.'});
    end

    function experimentsTab()
        t = uitab(tabs, 'Title', 'Experiments A-E');
        g = uigridlayout(t, [1 1]); g.Padding = [6 6 6 6];
        uitable(g, 'Data', experimentHeadlines(projDir), 'ColumnName', {'Experiment', 'Comparison', 'Result', 'Source file'}, ...
            'ColumnWidth', {140, 520, 420, 'auto'});
    end

    function methodTab()
        t = uitab(tabs, 'Title', 'Method & gap status');
        g = uigridlayout(t, [1 1]); g.Padding = [6 6 6 6];
        uitable(g, 'Data', gapStatus(), 'ColumnName', {'Charter item', 'Status in this simulator', 'Where'}, ...
            'ColumnWidth', {330, 640, 'auto'});
    end
end

% ======================================================================================
function v = pick(T, c, sp, col)
    x = T.(col)(T.config == c & T.split == sp);
    if isempty(x), v = NaN; else, v = x(1); end
end

function D = roundTable(T, nd)
    D = T;
    for i = 1:width(D)
        if isnumeric(D{:, i}), D{:, i} = round(D{:, i}, nd); end
    end
end

function C = experimentHeadlines(projDir)
    R = fullfile(projDir, 'results');
    C = {};
    try
        T = readtable(fullfile(R, 'experimentAB.csv'));
        p = strcmp(T.detectMode, 'perfectVisible') & T.windSpeed_mps == max(T.windSpeed_mps);
        off = T(p & T.pid == 0, :); on = T(p & T.pid == 1, :);
        C(end+1, :) = {'A - navigation', sprintf('Cross-track RMSE at %.1f m/s wind, PID off vs on', off.windSpeed_mps), ...
            sprintf('%.3f m vs %.3f m', off.crossRMSE_m, on.crossRMSE_m), 'experimentAB.csv'};
        C(end+1, :) = {'B - perception', 'Disease recall (perfect classifier) at max wind, PID off vs on', ...
            sprintf('%.0f%% vs %.0f%%', 100 * off.recall, 100 * on.recall), 'experimentAB.csv'};
    catch, end
    try
        T = readtable(fullfile(R, 'experimentC_flown.csv'));
        e = T(strcmp(T.condition, 'equalSpeed'), :);
        for i = 1:height(e)
            C(end+1, :) = {'C - routing', sprintf('Flown Pass-2 route, %s (equal speed, 42 frozen targets)', e.strategy{i}), ...
                sprintf('%.1f m, %.1f s travel (geometric %.1f m)', e.measuredDistance_m(i), e.measuredTravelTime_s(i), e.predictedDistance_m(i)), ...
                'experimentC_flown.csv'}; %#ok<AGROW>
        end
    catch, end
    try
        T = readtable(fullfile(R, 'experimentD.csv'));
        w = T(T.windSpeed_mps == 2, :);
        C(end+1, :) = {'D - spray drift', sprintf('Target deposition at 2 m/s wind (drift %.2f m), uncompensated vs compensated', w.driftDistance_m(1)), ...
            sprintf('%.1f%% vs %.1f%%', w.targetDepositionPct(w.compensated == 0), w.targetDepositionPct(w.compensated == 1)), 'experimentD.csv'};
    catch, end
    try
        T = readtable(fullfile(R, 'experimentD2.csv'));
        w = T(T.windSpeed_mps == 2, :);
        for a = [0.9 1.1 1.25]
            r = w(abs(w.windEstimateScale - a) < 1e-9, :);
            C(end+1, :) = {'D2 - wind estimate', sprintf('Deposition at 2 m/s with wind estimate x%.2f', a), ...
                sprintf('%.1f%% (residual %.2f m)', r.targetDepositionPct, abs(r.residualAlongWind_m)), 'experimentD2.csv'}; %#ok<AGROW>
        end
    catch, end
    try
        T = readtable(fullfile(R, 'experimentE.csv'));
        for i = 1:height(T)
            C(end+1, :) = {'E - end to end', sprintf('%s (wind %d, PID %d, comp %d)', T.scenario{i}, T.wind(i), T.pid(i), T.compensate(i)), ...
                sprintf('treated %.0f%%, deposition %.1f%%, cross-track %.3f m', 100 * T.treatmentSuccess(i), T.targetDepositionPct(i), ...
                T.surveyCrossRMSE_m(i)), 'experimentE.csv'}; %#ok<AGROW>
        end
    catch, end
    try
        T = readtable(fullfile(R, 'ablation8_reference.csv'));
        C(end+1, :) = {'Ablation (8 combos)', 'wind x PID x compensation: treated plants', ...
            strjoin(arrayfun(@(i) sprintf('%d%d%d:%d', T.wind(i), T.pid(i), T.comp(i), T.treated(i)), 1:height(T), 'UniformOutput', false), '  '), ...
            'ablation8_reference.csv'};
    catch, end
    if isempty(C), C = {'-', 'No saved experiment CSVs found in results/', 'run main_experiments', '-'}; end
end

function C = gapStatus()
    C = { ...
     'Perception: teammate CNN vs parametric detector', 'BLOCKED - no trained model or plant images in this folder; detection stays parametric', 'detectPlants.m'; ...
     'Localization: oracle (upper bound)', 'Implemented (default)', 'getEstimatedState.m'; ...
     'Localization: IMU-only dead reckoning (weak baseline)', 'Implemented - mode imuDeadReckoning', 'stepVehicleAdvanced.m'; ...
     'Localization: optical flow + LiDAR/landmark fusion', 'Implemented as a LINEAR position KF (flow prediction + periodic fixes), not EKF/ESKF/SLAM', 'stepVehicleAdvanced.m'; ...
     'Controller receives estimate, truth only for scoring', 'Implemented for all estimator modes', 'flyReference.m'; ...
     'Estimator consistency (NEES)', 'Implemented (advancedMetrics.estNEES)', 'advancedMetrics.m'; ...
     'Coverage: boustrophedon baseline', 'Implemented (original)', 'generateIrregularField.m'; ...
     'Coverage: polygon decomposition', 'NOT implemented (prior art exists; would need new coverage planner)', '-'; ...
     'Control: PID + one alternative', 'Implemented - pure pursuit (guidance feature)', 'purePursuitController.m'; ...
     'Routing: fixed / NN / NN+2-opt', 'Implemented', 'planTreatmentRoute.m, planRouteAdvanced.m'; ...
     'Routing: methods from the literature', 'Implemented - cheapest insertion, Or-opt, ant colony (+2-opt)', 'planRouteAdvanced.m'; ...
     'Routing: risk/energy-aware heuristic', 'NOT implemented', '-'; ...
     'Spray: none / analytical wind offset', 'Implemented (original)', 'sprayContext.m'; ...
     'Spray: actuation (valve) delay + lag compensation', 'Implemented (actuation feature)', 'advActuatedDeposition.m'; ...
     'Spray: non-circular kernel', 'Implemented as UNCALIBRATED wind-stretched ellipse (H4 robustness)', 'advDepositKernel.m'; ...
     'Spray: calibration against published deposition data', 'NOT done - needs extracted numeric tables', '-'; ...
     'Payload depletion -> mass, downwash, energy', 'Implemented (payload, dynamics, atmosphere, energy)', 'stepVehicleAdvanced.m, advancedDrift.m'; ...
     'Humidity / temperature', 'Implemented (evaporation via wet-bulb DeltaT)', 'advancedDrift.m'; ...
     'Altitude as a real input', 'Implemented (perception feature)', 'applyAdvancedDerived.m'; ...
     'Off-field deposition, boundary violation, actuator timing error', 'Implemented as metrics', 'advancedMetrics.m'; ...
     'Selection: best fixed vs scenario-conditioned vs oracle', 'Implemented with train / held-out test fields', 'runExperimentF.m'; ...
     'H1-H4, CIs, worst-decile, Pareto', 'Implemented (paired bootstrap, t intervals)', 'runExperimentF.m'; ...
     'Hardware profiles from datasheets', 'NOT implemented - no verified specifications available', '-'; ...
     'Physical / field validation', 'NOT possible in simulation', '-'};
end

function s = supp(b), if b, s = 'SUPPORTED'; else, s = 'NOT SUPPORTED'; end, end
function s = yesno(b), if b, s = 'yes'; else, s = 'no'; end, end
function v = ternary(c, a, b), if c, v = a; else, v = b; end, end
