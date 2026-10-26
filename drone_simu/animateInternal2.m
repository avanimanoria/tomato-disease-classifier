function fig = animateInternal2(cfg, field, runs, opts)
%ANIMATEINTERNAL2 Live, real-time replay of Internal-2 missions (one tile per run).
%
%   fig = animateInternal2(cfg, field, runs [, opts])
%
%   Replays the stored per-step logs of each run on a SHARED clock, so tiles
%   can be compared side by side. Nothing is re-simulated; the motion is the
%   exact simulated trajectory. What you see per tile:
%     blue triangle + circle    drone and its camera footprint (cfg.cameraFovRadius)
%     blue line                 Pass-1 survey trail (dashed black = reference path)
%     magenta line              Pass-2 transit trail
%     plant colours             grey = not yet observed; once observed: green =
%                               healthy, red = diseased; black ring = flagged
%                               target; blue = diseased and treated; orange =
%                               healthy but sprayed (false positive)
%     magenta disc              spray cloud (displaced by wind drift) while spraying
%     colour overlay            accumulated spray deposition (relative units)
%
%   opts (all optional):
%     speed       simulated seconds per wall-clock second (default 8)
%     stopAtTime  stop at this simulated time and leave the figure open
%     visible     'on' (default) | 'off'
%   Close the window to stop playback.

    if nargin < 4, opts = struct(); end
    speed  = getopt(opts, 'speed', 8);
    stopAt = getopt(opts, 'stopAtTime', inf);
    vis    = getopt(opts, 'visible', 'on');

    dt = cfg.dt;
    S = cfg.internal2.spray;
    P = field.plants;
    N = height(P);
    isDis = P.TrueDisease == "DISEASED";
    thr = cfg.internal2.metrics.treatedDoseFraction * S.flowRate * S.duration;
    footR = S.releaseHeight * tand(S.nozzleHalfAngle);
    th = linspace(0, 2*pi, 48);
    nR = numel(runs);

    cUnseen = [0.82 0.82 0.82]; cHealthy = [0.15 0.65 0.20]; cDis = [0.85 0.10 0.10];
    cTreated = [0.10 0.30 0.95]; cHealthyHit = [0.95 0.60 0.10];
    phaseName = {'Pass 1: survey', 'Pass 2: transit to target', 'Pass 2: settling', 'Pass 2: SPRAYING'};

    % ---- timelines, shared axis limits ----
    allXY = field.polygon;
    for i = 1:nR
        T(i) = buildTimeline(runs{i}); %#ok<AGROW>
        allXY = [allXY; T(i).pos]; %#ok<AGROW>
    end
    pad = 1.5;
    xl = [min(allXY(:,1)) - pad, max(allXY(:,1)) + pad];
    yl = [min(allXY(:,2)) - pad, max(allXY(:,2)) + pad];

    fig = figure('Name', 'Internal-2 live simulation', 'Visible', vis, ...
                 'Position', [40 40 1400 820], 'Color', 'w');
    nCols = ceil(nR / 2);
    for i = 1:nR
        run = runs{i};
        ax = subplot(2, nCols, i);
        hold(ax, 'on'); axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'on');
        xlim(ax, xl); ylim(ax, yl);
        xlabel(ax, 'X (m)'); ylabel(ax, 'Y (m)');
        colormap(ax, parula);

        g = initDepositionGrid(cfg, field);
        h(i).img = imagesc(ax, g.xv, g.yv, g.mass, 'AlphaData', zeros(size(g.mass))); %#ok<AGROW>
        set(ax, 'YDir', 'normal');
        patch(ax, field.polygon(:,1), field.polygon(:,2), 'w', 'FaceColor', 'none', 'EdgeColor', 'k', 'LineWidth', 1.5);
        for r = 1:numel(field.rows)
            plot(ax, field.rows{r}(:,1), field.rows{r}(:,2), '-', 'Color', [0.88 0.88 0.88]);
        end
        plot(ax, field.surveyRef.pts(:,1), field.surveyRef.pts(:,2), 'k--', 'LineWidth', 0.7);
        h(i).plants = scatter(ax, P.X, P.Y, 26, repmat(cUnseen, N, 1), 'filled');
        h(i).flag = plot(ax, nan, nan, 'ko', 'MarkerSize', 10, 'LineWidth', 1.2);
        h(i).trail1 = plot(ax, nan, nan, 'b-', 'LineWidth', 1.3);
        h(i).trail2 = plot(ax, nan, nan, 'm-', 'LineWidth', 1.3);
        h(i).spray = patch(ax, nan, nan, 'm', 'FaceAlpha', 0.35, 'EdgeColor', 'm');
        h(i).cam = patch(ax, nan, nan, 'b', 'FaceColor', 'none', 'EdgeColor', 'b', 'LineStyle', '-');
        h(i).drone = plot(ax, T(i).pos(1,1), T(i).pos(1,2), '^', 'MarkerFaceColor', 'b', ...
                          'MarkerEdgeColor', 'w', 'MarkerSize', 10);
        h(i).txt = text(ax, xl(1) + 0.3, yl(2) - 0.3, '', 'VerticalAlignment', 'top', 'FontSize', 8, ...
                        'BackgroundColor', [1 1 1 0.85], 'Margin', 3);
        title(ax, sprintf('%s  (wind %s, PID %s, compensation %s)', run.name, ...
            onoff(run.flags.wind), onoff(run.flags.pid), onoff(run.flags.compensate)), ...
            'FontSize', 10, 'Interpreter', 'none');

        % per-run state
        [~, ~, firstStep] = detectPlants(field, run.log1, cfg);
        st(i).firstStep = firstStep; %#ok<AGROW>
        st(i).flagged = zeros(N, 1);
        st(i).flagged(run.targets.plantIdx) = firstStep(run.targets.plantIdx);
        st(i).grid = g;
        st(i).lastK = 0;
        st(i).treated = false(N, 1);
        st(i).lastImg = -inf;
    end
    hl = [scatter(nan, nan, 26, cUnseen, 'filled'), scatter(nan, nan, 26, cHealthy, 'filled'), ...
          scatter(nan, nan, 26, cDis, 'filled'), plot(nan, nan, 'ko', 'MarkerSize', 10), ...
          scatter(nan, nan, 26, cTreated, 'filled'), scatter(nan, nan, 26, cHealthyHit, 'filled')];
    legend(hl, {'not yet observed', 'observed healthy', 'observed diseased', 'flagged target', ...
                'diseased, treated', 'healthy, sprayed (false positive)'}, ...
           'Orientation', 'horizontal', 'Units', 'normalized', 'Position', [0.15 0.003 0.7 0.03], ...
           'FontSize', 8, 'Box', 'off');
    hClock = sgtitle(fig, '');
    drawnow;

    % ---- real-time playback loop ----
    nMax = max([T.N]);
    t0 = tic;
    while isvalid(fig)
        simT = min(toc(t0) * speed, stopAt);
        k = min(1 + floor(simT / dt), nMax);
        for i = 1:nR
            advance(i, min(k, T(i).N), false);
        end
        hClock.String = sprintf('Internal-2 live simulation | t = %.1f s | playback %gx real time | close window to stop', ...
                                (k - 1) * dt, speed);
        drawnow limitrate;
        if simT >= stopAt || k >= nMax, break; end
    end
    if isvalid(fig) && k >= nMax            % ran to the end: snap to the exact final deposition
        for i = 1:nR
            advance(i, T(i).N, true);
        end
        hClock.String = sprintf('Internal-2 live simulation | finished at t = %.1f s', (k - 1) * dt);
        drawnow;
    end

    % ================= nested helpers =================
    function advance(i, ki, final)
        run = runs{i};
        s = st(i);
        % deposit spray for the steps since last call (same model as the mission)
        needDose = false;
        for kk = s.lastK + 1 : ki
            if T(i).stage(kk) == 4
                s.grid = depositSpray(s.grid, T(i).pos(kk, :), run.driftTrue, S.flowRate * dt, cfg);
                if kk == T(i).N || T(i).stage(min(kk + 1, T(i).N)) ~= 4
                    needDose = true;            % a spray event just finished
                end
            end
        end
        s.lastK = ki;
        if final, s.grid = run.grid; needDose = true; end
        if needDose
            s.treated = plantDose(cfg, field, s.grid) >= thr;
        end

        % plant colours
        seen = s.firstStep > 0 & s.firstStep <= ki;
        C = repmat(cUnseen, N, 1);
        C(seen & ~isDis, :) = repmat(cHealthy, nnz(seen & ~isDis), 1);
        C(seen & isDis, :)  = repmat(cDis, nnz(seen & isDis), 1);
        C(s.treated & isDis, :)  = repmat(cTreated, nnz(s.treated & isDis), 1);
        C(s.treated & ~isDis, :) = repmat(cHealthyHit, nnz(s.treated & ~isDis), 1);
        h(i).plants.CData = C;
        fl = s.flagged > 0 & s.flagged <= ki;
        set(h(i).flag, 'XData', P.X(fl), 'YData', P.Y(fl));

        % drone, footprint, trails, spray cloud
        p = T(i).pos(ki, :);
        n1 = T(i).n1;
        set(h(i).drone, 'XData', p(1), 'YData', p(2));
        set(h(i).cam, 'XData', p(1) + cfg.cameraFovRadius * cos(th), 'YData', p(2) + cfg.cameraFovRadius * sin(th));
        set(h(i).trail1, 'XData', T(i).pos(1:min(ki, n1), 1), 'YData', T(i).pos(1:min(ki, n1), 2));
        if ki > n1
            set(h(i).trail2, 'XData', T(i).pos(n1+1:ki, 1), 'YData', T(i).pos(n1+1:ki, 2));
        end
        if T(i).stage(ki) == 4
            c = p + run.driftTrue;
            set(h(i).spray, 'XData', c(1) + footR * cos(th), 'YData', c(2) + footR * sin(th));
        else
            set(h(i).spray, 'XData', nan, 'YData', nan);
        end

        % deposition overlay (throttled to ~8 Hz of wall time, always on the last frame)
        if final || toc(t0) - s.lastImg > 0.12
            m = s.grid.mass;
            mx = max(m(:));
            if mx <= 0, mx = 1; end
            set(h(i).img, 'CData', m, 'AlphaData', double(m > 0.02 * mx));
            s.lastImg = toc(t0);
        end

        nTrue = nnz(s.treated & isDis);
        h(i).txt.String = sprintf('%s\nobserved %d/%d | flagged %d | treated %d/%d diseased | healthy sprayed %d', ...
            phaseName{T(i).stage(ki)}, nnz(seen), N, nnz(fl), nTrue, nnz(isDis), nnz(s.treated & ~isDis));
        st(i) = s;
    end
end

function tl = buildTimeline(run)
%BUILDTIMELINE Concatenate survey + all Pass-2 leg logs into one step sequence.
%   stage: 1 survey, 2 transit, 3 settle, 4 spraying.
    pos = run.log1.truePos;
    stage = ones(size(pos, 1), 1);
    n1 = size(pos, 1);
    for j = 1:numel(run.legLogs)
        L = run.legLogs{j};
        pos = [pos; L.truePos]; %#ok<AGROW>
        stage = [stage; 1 + L.phase]; %#ok<AGROW>
    end
    tl.pos = pos;
    tl.stage = stage;
    tl.n1 = n1;
    tl.N = size(pos, 1);
end

function v = getopt(opts, name, default)
    if isfield(opts, name), v = opts.(name); else, v = default; end
end

function s = onoff(b)
    if b, s = 'ON'; else, s = 'OFF'; end
end
