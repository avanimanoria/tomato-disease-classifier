function plotInternal2(cfg, field, runs, mets)
%PLOTINTERNAL2 Overlay maps (one tile per run) + tracking / spray summary.
%
%   Figure 1, per tile: field polygon, curved rows, reference survey path
%   (dashed), actual survey path, Pass-2 transit path, true diseased plants
%   (red), flagged targets (black rings), commanded spray release points
%   (x), and the estimated deposition footprint (colour overlay).
%   Figure 2: signed cross-track error vs time (Pass 1) and spray allocation.
%   Deposition colours are relative (simplified model, not validated).

    poly = field.polygon;
    P = field.plants;
    isDis = P.TrueDisease == "DISEASED";
    nR = numel(runs);

    % common axis limits over all runs
    allXY = poly;
    for i = 1:nR
        allXY = [allXY; runs{i}.log1.truePos]; %#ok<AGROW>
        for j = 1:numel(runs{i}.legLogs)
            allXY = [allXY; runs{i}.legLogs{j}.truePos]; %#ok<AGROW>
        end
    end
    pad = 1.5;
    xl = [min(allXY(:,1)) - pad, max(allXY(:,1)) + pad];
    yl = [min(allXY(:,2)) - pad, max(allXY(:,2)) + pad];

    figure('Name', 'Internal-2: reference vs actual vs corrected', 'Position', [60 60 1350 800]);
    tl = tiledlayout(2, ceil(nR / 2), 'TileSpacing', 'compact', 'Padding', 'compact');
    for i = 1:nR
        run = runs{i};
        ax = nexttile(tl);
        hold(ax, 'on'); axis(ax, 'equal'); grid(ax, 'on');

        g = run.grid;
        mx = max(g.mass(:));
        if mx <= 0, mx = 1; end
        imagesc(ax, g.xv, g.yv, g.mass, 'AlphaData', double(g.mass > 0.02 * mx));
        set(ax, 'YDir', 'normal');
        colormap(ax, parula);

        hB = patch(ax, poly(:,1), poly(:,2), 'w', 'FaceColor', 'none', 'EdgeColor', 'k', 'LineWidth', 1.5);
        for r = 1:numel(field.rows)
            plot(ax, field.rows{r}(:,1), field.rows{r}(:,2), '-', 'Color', [0.8 0.8 0.8]);
        end
        hRef = plot(ax, field.surveyRef.pts(:,1), field.surveyRef.pts(:,2), 'k--', 'LineWidth', 0.8);
        hAct = plot(ax, run.log1.truePos(:,1), run.log1.truePos(:,2), 'b-', 'LineWidth', 1.2);
        if ~isempty(run.legLogs)
            tpCell = cellfun(@(L) L.truePos, run.legLogs, 'UniformOutput', false);
            tp2 = vertcat(tpCell{:});
            hP2 = plot(ax, tp2(:,1), tp2(:,2), 'm-', 'LineWidth', 1.2);
        else
            hP2 = plot(ax, nan, nan, 'm-', 'LineWidth', 1.2);
        end
        hH = scatter(ax, P.X(~isDis), P.Y(~isDis), 8, [0.55 0.55 0.55], 'filled');
        hD = scatter(ax, P.X(isDis), P.Y(isDis), 22, [0.85 0.1 0.1], 'filled');
        hT = plot(ax, run.targets.XY(:,1), run.targets.XY(:,2), 'ko', 'MarkerSize', 9, 'LineWidth', 1);
        if isempty(run.targets.XY), hT = plot(ax, nan, nan, 'ko', 'MarkerSize', 9); end
        hS = plot(ax, run.releasePts(:,1), run.releasePts(:,2), 'kx', 'MarkerSize', 7, 'LineWidth', 1.5);
        if isempty(run.releasePts), hS = plot(ax, nan, nan, 'kx', 'MarkerSize', 7); end

        xlim(ax, xl); ylim(ax, yl);
        xlabel(ax, 'X (m)'); ylabel(ax, 'Y (m)');
        m = mets{i};
        title(ax, {run.name, sprintf('RMSE %.2f m | max %.2f m | treated %.0f%% | on-target %.0f%%', ...
            m.survey.crossRMSE, m.survey.crossMaxAbs, 100*m.spray.treatmentSuccess, m.spray.targetDepositionPct)}, ...
            'FontSize', 8, 'Interpreter', 'none');
        if i == 1
            hLeg = [hB hRef hAct hP2 hH hD hT hS];
        end
    end
    lg = legend(ax, hLeg, ...
        {'Field boundary', 'Reference survey path', 'Actual survey path', 'Pass-2 actual path', ...
         'Healthy plant', 'Truly diseased plant', 'Flagged target', 'Commanded spray point'}, ...
        'FontSize', 8, 'NumColumns', 4);
    lg.Layout.Tile = 'south';
    title(tl, 'Internal-2 (colour overlay = relative simulated deposition, assumed parameters)');

    % ---------------- figure 2 ----------------
    figure('Name', 'Internal-2: tracking and spray allocation', 'Position', [100 100 1200 600]);
    ax1 = subplot(1, 2, 1); hold(ax1, 'on'); grid(ax1, 'on');
    for i = 1:nR
        plot(ax1, runs{i}.log1.t, runs{i}.log1.cross, 'LineWidth', 1.2, 'DisplayName', runs{i}.name);
    end
    yline(ax1, 0, 'k-', 'HandleVisibility', 'off');
    xlabel(ax1, 'Pass-1 time (s)'); ylabel(ax1, 'Signed cross-track error (m)');
    title(ax1, 'Survey tracking error');
    legend(ax1, 'Location', 'southoutside', 'NumColumns', 2, 'FontSize', 8, 'Interpreter', 'none');

    ax2 = subplot(1, 2, 2);
    alloc = zeros(nR, 3);
    names = cell(1, nR);
    for i = 1:nR
        alloc(i, :) = [mets{i}.spray.targetDepositionPct, mets{i}.spray.onHealthyPct, mets{i}.spray.onOtherGroundPct];
        names{i} = runs{i}.name;
    end
    bar(ax2, alloc, 'stacked');
    set(ax2, 'XTickLabel', names, 'TickLabelInterpreter', 'none', 'XTickLabelRotation', 20);
    ylabel(ax2, '% of emitted spray'); ylim(ax2, [0 100]);
    legend(ax2, {'On truly diseased plants (useful)', 'On healthy plants', 'Other ground / outside'}, ...
        'Location', 'southoutside', 'NumColumns', 1, 'FontSize', 8);
    title(ax2, 'Spray allocation (simplified model)'); grid(ax2, 'on');
end
