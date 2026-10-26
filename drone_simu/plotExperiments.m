function fig = plotExperiments(kind, res, visible)
%PLOTEXPERIMENTS Sweep plots for Experiments 'AB', 'C' and 'D' (raw values, no smoothing).
%
%   fig = plotExperiments('AB' | 'C' | 'D', res [, visible])
%   res is the struct returned by runExperimentAB / runExperimentC / runExperimentD.
%   visible = 'on' (default) | 'off'.

    if nargin < 3, visible = 'on'; end
    switch upper(kind)
        case 'AB', fig = plotAB(res, visible);
        case 'C',  fig = plotC(res, visible);
        case 'D',  fig = plotD(res, visible);
        case 'D2', fig = plotD2(res, visible);
        otherwise, error('plotExperiments:badKind', 'kind must be AB, C or D.');
    end
end

function fig = plotAB(res, visible)
    T = res.table;
    fig = figure('Name', 'Experiments A/B: vehicle-disturbance sweep', 'Visible', visible, ...
                 'Position', [40 40 1400 760]);
    perfect = T(T.detectMode == "perfectVisible", :);
    stoch   = T(T.detectMode == "stochastic", :);
    panels = { ...
        perfect, 'crossRMSE_m',     'Cross-track RMSE (m)',            'A: cross-track RMSE'; ...
        perfect, 'crossMaxAbs_m',   'Max |cross-track| (m)',           'A: max deviation'; ...
        perfect, 'posRMSE_m',       'Position RMSE vs timed ref (m)',  'A: position RMSE (distinct from cross-track)'; ...
        perfect, 'observationRate', 'Plant observation rate',          'B: plants observed / all plants'; ...
        perfect, 'recall',          'Disease recall',                  'B: recall, perfectVisible (= diseased observation rate)'; ...
        stoch,   'recall',          'Disease recall',                  'B: recall, stochastic detector'};
    for p = 1:size(panels, 1)
        ax = subplot(2, 3, p); hold(ax, 'on'); grid(ax, 'on');
        D = panels{p, 1};
        for pid = [0 1]
            S = D(D.pid == pid, :);
            plot(ax, S.windSpeed_mps, S.(panels{p, 2}), '-o', 'LineWidth', 1.4, ...
                'DisplayName', ternary(pid, 'PID ON', 'PID OFF'));
        end
        xlabel(ax, 'Wind speed (m/s)');
        ylabel(ax, panels{p, 3});
        title(ax, panels{p, 4}, 'FontSize', 9);
        if startsWith(panels{p, 2}, {'observation', 'recall'}), ylim(ax, [0 1.05]); end
        if p == 1, legend(ax, 'Location', 'best'); end
    end
    sgtitle(sprintf(['Experiments A/B - same field, seed, ground truth; wind 0 = no-wind control ' ...
        '(ground disturbance = %.3g x wind; assumed parameters)'], res.windCoupling));
end

function fig = plotC(res, visible)
    T = res.geometricTable;
    fig = figure('Name', 'Experiment C: routing comparison (frozen target set)', 'Visible', visible, ...
                 'Position', [60 60 1100 450]);
    counts = unique(T.targetCount)';
    algos = ["Stage7-style", "Direct fixed order", "Nearest-neighbour"];
    metrics = {'distance_m', 'Distance (m)'; 'flightTime_s', 'Flight time (s)'};
    for q = 1:2
        ax = subplot(1, 2, q); hold(ax, 'on'); grid(ax, 'on');
        V = zeros(numel(counts), numel(algos));
        for i = 1:numel(counts)
            for a = 1:numel(algos)
                V(i, a) = T.(metrics{q, 1})(T.targetCount == counts(i) & T.algorithm == algos(a));
            end
        end
        b = bar(ax, [V; nan(1, numel(algos))]);   % NaN pad row: a single group would otherwise draw as one series
        xlim(ax, [0.5 numel(counts) + 0.5]);
        set(ax, 'XTick', 1:numel(counts), 'XTickLabel', string(counts));
        xlabel(ax, 'Number of frozen targets'); ylabel(ax, metrics{q, 2});
        title(ax, ['C: ' metrics{q, 2}]);
        for a = 1:numel(b), b(a).DisplayName = char(algos(a)); end
        yline(ax, T.(ternary(q == 1, 'fullSurveyDistance_m', 'fullSurveyTime_s'))(1), 'k--', 'repeat full survey', ...
            'HandleVisibility', 'off');
        if q == 1, legend(ax, 'Location', 'best'); end
    end
    sgtitle('Experiment C - identical frozen target set and start for every algorithm (geometric, nominal)');
end

function fig = plotD(res, visible)
    T = res.table;
    fig = figure('Name', 'Experiment D: spray-only wind sweep', 'Visible', visible, 'Position', [50 50 1400 760]);
    panels = { ...
        'treatmentSuccess',    'Treatment success (treated / true diseased)', true; ...
        'targetDepositionPct', 'Target deposition (% of emitted)',            false; ...
        'offTargetPct',        'Off-target (% of emitted)',                   false; ...
        'wasted_mL',           'Wasted spray (mL)',                           false};
    unc = T(T.compensated == 0, :);
    cmp = T(T.compensated == 1, :);
    fp = unc.footprintRadius_m(1);
    cr = unc.canopyRadius_m(1);
    for p = 1:size(panels, 1)
        ax = subplot(2, 2, p); hold(ax, 'on'); grid(ax, 'on');
        plot(ax, unc.driftDistance_m, unc.(panels{p, 1}), '-o', 'LineWidth', 1.4, 'DisplayName', 'uncompensated');
        plot(ax, cmp.driftDistance_m, cmp.(panels{p, 1}), '-s', 'LineWidth', 1.4, 'DisplayName', 'upwind-compensated');
        xline(ax, cr, ':', 'canopy r', 'HandleVisibility', 'off');
        xline(ax, fp, ':', 'footprint r', 'HandleVisibility', 'off');
        xlabel(ax, 'Modelled spray drift distance, m  (wind speed m/s in parentheses)');
        ylabel(ax, panels{p, 2});
        ticks = unc.driftDistance_m;
        set(ax, 'XTick', ticks(1:2:end), 'XTickLabel', ...
            arrayfun(@(d, w) sprintf('%.2f (%.2g)', d, w), ticks(1:2:end), unc.windSpeed_mps(1:2:end), 'UniformOutput', false));
        if panels{p, 3}, ylim(ax, [0 1.05]); end
        if p == 1, legend(ax, 'Location', 'best'); end
    end
    sgtitle('Experiment D - spray model only (fixed hover over every diseased target); drift distance is the primary variable');
end

function fig = plotD2(res, visible)
    T = res.table;
    fig = figure('Name', 'Experiment D2: imperfect wind estimate', 'Visible', visible, 'Position', [60 60 1400 450]);
    alphas = unique(T.windEstimateScale)';
    winds = unique(T.windSpeed_mps)';
    cm = parula(numel(alphas) + 1);
    ax = subplot(1, 3, 1); hold(ax, 'on'); grid(ax, 'on');
    scatter(ax, T.residualAlongWind_m, T.targetDepositionPct, 22, T.windEstimateScale, 'filled');
    colormap(ax, parula); cb = colorbar(ax); cb.Label.String = 'alpha';
    xline(ax, -res.canopyRadius_m, ':'); xline(ax, res.canopyRadius_m, ':', 'canopy r');
    xlabel(ax, 'Signed residual displacement along wind (m)  (+ = lands downwind of plant)');
    ylabel(ax, 'Target deposition (% of emitted)');
    title(ax, 'D2: deposition vs residual displacement');
    ax = subplot(1, 3, 2); hold(ax, 'on'); grid(ax, 'on');
    for i = 1:numel(alphas)
        S = T(T.windEstimateScale == alphas(i), :);
        plot(ax, S.windSpeed_mps, S.targetDepositionPct, '-o', 'Color', cm(i, :), 'DisplayName', sprintf('alpha = %.2f', alphas(i)));
    end
    xlabel(ax, 'True wind speed (m/s)'); ylabel(ax, 'Target deposition (%)'); title(ax, 'D2: by wind-estimate scale');
    legend(ax, 'Location', 'best', 'FontSize', 7);
    ax = subplot(1, 3, 3);
    H = zeros(numel(alphas), numel(winds));
    for i = 1:numel(alphas)
        for j = 1:numel(winds)
            H(i, j) = T.offTargetPct(T.windEstimateScale == alphas(i) & T.windSpeed_mps == winds(j));
        end
    end
    imagesc(ax, winds, 1:numel(alphas), H);
    set(ax, 'YTick', 1:numel(alphas), 'YTickLabel', string(alphas), 'YDir', 'normal');
    colorbar(ax); xlabel(ax, 'True wind speed (m/s)'); ylabel(ax, 'windEstimateScale alpha');
    title(ax, 'D2: off-target (% of emitted)');
    sgtitle('Experiment D2 - true wind drives the spray; compensator uses alpha x true wind (spray-only)');
end

function out = ternary(c, a, b)
    if c, out = a; else, out = b; end
end
