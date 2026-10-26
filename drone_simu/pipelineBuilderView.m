function api = pipelineBuilderView(parent, app)
%PIPELINEBUILDERVIEW Manual pipeline builder + paired comparison (evaluation view).
%
%   api = pipelineBuilderView(parentContainer [, dashboardApp])
%
%   Choose one method per stage (perception, localization, coverage, controller, routing,
%   spray compensation, deposition kernel) and the scenario, then RUN SELECTED runs the real
%   two-pass mission through runPipeline (same engine as the Mission tab and the batch
%   experiments). COMPARE WITH... re-runs the current choice on the identical frozen scenario
%   and tabulates it beside the earlier runs (2-4). Unavailable methods are listed but cannot
%   be run. This view shows ground-truth scoring (it is not the Mission screen).
%
%   api (for tests and the dashboard): getPc, setPc, runSelected, compareWith, resetLegacy,
%   exportRun, clearCompare, state.
    if nargin < 2, app = []; end
    if nargin < 1 || isempty(parent)
        fig = uifigure('Name', 'Pipeline builder', 'Position', [40 40 1440 800]);
        parent = uigridlayout(fig, [1 1]); parent.Padding = [0 0 0 0];
    end
    R = pipelineRegistry();
    st.last = []; st.compare = {}; st.lastValid = struct();

    g = uigridlayout(parent, [1 3]);
    g.ColumnWidth = {370, '1x', 440}; g.Padding = [6 6 6 6]; g.ColumnSpacing = 6;

    % ================= left: mode, actions, pipeline, scenario =================
    L = uigridlayout(g, [4 1]);
    L.RowHeight = {150, 292, 580, 10}; L.Scrollable = 'on'; L.Padding = [0 0 0 0]; L.RowSpacing = 5;

    ap = uipanel(L, 'Title', 'Mode & actions');
    ag = uigridlayout(ap, [4 3]); ag.RowHeight = {22, 28, 28, 22}; ag.Padding = [6 4 6 4]; ag.RowSpacing = 4; ag.ColumnSpacing = 4;
    lb = uilabel(ag, 'Text', 'Mode'); lb.Layout.Column = 1;
    ui.mode = uidropdown(ag, 'Items', R.mode.label', 'ItemsData', R.mode.id', 'Value', 'manual', 'ValueChangedFcn', @(~, ~) onChange());
    ui.mode.Layout.Column = [2 3];
    ui.run = uibutton(ag, 'push', 'Text', 'RUN SELECTED', 'FontWeight', 'bold', 'BackgroundColor', [0.80 0.93 0.80], ...
        'ButtonPushedFcn', @(~, ~) runSelected());
    ui.cmp = uibutton(ag, 'push', 'Text', 'COMPARE WITH...', 'FontSize', 10, 'ButtonPushedFcn', @(~, ~) compareWith());
    ui.reset = uibutton(ag, 'push', 'Text', 'RESET TO LEGACY', 'FontSize', 10, 'ButtonPushedFcn', @(~, ~) resetLegacy());
    ui.save = uibutton(ag, 'push', 'Text', 'SAVE CONFIG', 'ButtonPushedFcn', @(~, ~) saveCfg());
    ui.load = uibutton(ag, 'push', 'Text', 'LOAD CONFIG', 'ButtonPushedFcn', @(~, ~) loadCfg());
    ui.export = uibutton(ag, 'push', 'Text', 'EXPORT RUN', 'ButtonPushedFcn', @(~, ~) exportRun());
    ui.pending = uilabel(ag, 'Text', 'No run yet - press RUN SELECTED', 'FontColor', [0.6 0.4 0], 'FontWeight', 'bold');
    ui.pending.Layout.Column = [1 3];

    pp = uipanel(L, 'Title', 'Pipeline (one method per stage)');
    pg = uigridlayout(pp, [8 2]); pg.RowHeight = repmat({24}, 1, 8); pg.ColumnWidth = {112, '1x'};
    pg.Padding = [6 4 6 4]; pg.RowSpacing = 6;
    stages = {'perception', 'Perception'; 'localization', 'Localization'; 'coverage', 'Pass-1 coverage'; ...
              'controller', 'Path following'; 'routing', 'Pass-2 routing'; 'sprayCompensation', 'Spray control'; 'kernel', 'Deposition kernel'};
    for i = 1:size(stages, 1)
        T = R.(stages{i, 1});
        lab = T.label';
        for k = 1:height(T), if ~T.available(k), lab{k} = [lab{k} '  (UNAVAILABLE)']; end, end
        uilabel(pg, 'Text', stages{i, 2});
        ui.(stages{i, 1}) = uidropdown(pg, 'Items', lab, 'ItemsData', T.id', ...
            'Tooltip', 'Unavailable methods are listed for transparency and cannot be run', ...
            'ValueChangedFcn', @(src, ev) onStage(src, ev, stages{i, 1}));
    end
    uilabel(pg, 'Text', 'Target geolocation');
    ui.geo = uicheckbox(pg, 'Text', 'Pass-2 targets at ESTIMATED plant position', 'Value', false, ...
        'Tooltip', 'Truth firewall: record each flagged plant where the estimator believed it was (needs an estimator)', ...
        'ValueChangedFcn', @(~, ~) onChange());

    sp = uipanel(L, 'Title', 'Scenario (held fixed for paired comparisons)');
    sg = uigridlayout(sp, [22 2]); sg.RowHeight = repmat({22}, 1, 22); sg.ColumnWidth = {150, '1x'};
    sg.Padding = [6 4 6 4]; sg.RowSpacing = 2;
    ui.shape = row(sg, 'Field shape', 'dd', {'Trapezoid', 'Rectangle', 'UShape'});
    ui.length = row(sg, 'Rect. length / width (m)', 'pair');
    ui.bottom = row(sg, 'Trap. bottom / top (m)', 'pair');
    ui.height = row(sg, 'Trap. height (m)', 'num');
    ui.rowStyle = row(sg, 'Rows', 'dd', {'Curved', 'Straight'});
    ui.rowSpacing = row(sg, 'Row / plant spacing (m)', 'pair');
    ui.fieldSeed = row(sg, 'Field (disease) seed', 'num');
    ui.obstacle = row(sg, 'Obstacle in field', 'dd', {'none', 'pond'});
    ui.keepAll = row(sg, 'Keep all row pieces', 'chk');
    ui.wind = row(sg, 'Wind ON', 'chk');
    ui.windSpeed = row(sg, 'Wind speed / dir (m/s, deg)', 'pair');
    ui.gust = row(sg, 'Gust RMS (m/s, 0 = off) / seed', 'pair');
    ui.delay = row(sg, 'Valve delay (s)', 'num');
    ui.locSeed = row(sg, 'Localization noise seed', 'num');
    ui.speed = row(sg, 'Drone speed (m/s)', 'num');
    ui.payload = row(sg, 'Payload / tank model', 'chk');
    ui.dynamics = row(sg, 'Vehicle dynamics model', 'chk');
    ui.energy = row(sg, 'Energy / battery model', 'chk');
    ui.atmosphere = row(sg, 'Atmosphere drift model', 'chk');
    ui.altModel = row(sg, 'Altitude model / altitude (m)', 'chkpair');
    [hwIds, hwLabels] = hardwareProfileList();
    ui.hw = row(sg, 'Hardware profile', 'dd', hwLabels);
    ui.hw.ItemsData = hwIds; ui.hw.Value = 'assumedDefault';
    ui.hw.Tooltip = 'Versioned profiles in profiles/*.json; uncited manufacturer / literature values are rejected';

    % ================= centre: map =================
    C = uigridlayout(g, [3 1]); C.RowHeight = {28, '1x', 30}; C.Padding = [0 0 0 0]; C.RowSpacing = 4;
    ui.title = uilabel(C, 'Text', 'Run a pipeline to see its mission', 'FontWeight', 'bold', 'FontSize', 14, ...
        'HorizontalAlignment', 'center', 'BackgroundColor', [0.93 0.95 0.98]);
    ui.ax = uiaxes(C);
    og = uigridlayout(C, [1 5]); og.Padding = [2 0 2 0];
    ui.ovEst = uicheckbox(og, 'Text', 'Est. track', 'Value', false, 'ValueChangedFcn', @(~, ~) drawRun());
    ui.ovRel = uicheckbox(og, 'Text', 'Release pts', 'Value', true, 'ValueChangedFcn', @(~, ~) drawRun());
    ui.ovDep = uicheckbox(og, 'Text', 'Deposition', 'Value', true, 'ValueChangedFcn', @(~, ~) drawRun());
    ui.ovTruth = uicheckbox(og, 'Text', 'True disease', 'Value', true, 'ValueChangedFcn', @(~, ~) drawRun());
    ui.replay = uibutton(og, 'push', 'Text', 'Replay in MISSION', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) replayInMission());

    % ================= right: run info, metrics, comparison, warnings =================
    rt = uitabgroup(g);
    t1 = uitab(rt, 'Title', 'This run');
    t1g = uigridlayout(t1, [2 1]); t1g.RowHeight = {150, '1x'}; t1g.Padding = [4 4 4 4];
    ui.info = uitextarea(t1g, 'Editable', 'off', 'FontName', 'Consolas', 'FontSize', 10, 'Value', {'-'});
    ui.metrics = uitable(t1g, 'ColumnName', {'Group', 'Metric', 'Value', 'Unit'}, 'ColumnWidth', {80, 170, 70, 'auto'}, 'RowName', {});
    t2 = uitab(rt, 'Title', 'Compare (paired)');
    t2g = uigridlayout(t2, [3 1]); t2g.RowHeight = {44, '1x', 28}; t2g.Padding = [4 4 4 4];
    ui.cmpInfo = uilabel(t2g, 'Text', 'COMPARE WITH... adds the current selection, run on the same scenario.', 'WordWrap', 'on');
    ui.cmpTable = uitable(t2g, 'RowName', {});
    ui.clear = uibutton(t2g, 'push', 'Text', 'Clear comparison', 'ButtonPushedFcn', @(~, ~) clearCompare());
    t3 = uitab(rt, 'Title', 'Warnings');
    t3g = uigridlayout(t3, [1 1]); t3g.Padding = [4 4 4 4];
    ui.warn = uitextarea(t3g, 'Editable', 'off', 'Value', {'-'});

    setPc(pipelineDefaults());
    api = struct('getPc', @getPc, 'setPc', @setPc, 'runSelected', @runSelected, 'compareWith', @compareWith, ...
        'resetLegacy', @resetLegacy, 'exportRun', @exportRun, 'clearCompare', @clearCompare, 'state', @getState, 'ui', ui);

    function s = getState()
        s = st;                                 % live state (nested function, not a captured copy)
    end

    % ------------------------------------------------------------------ controls
    function h = row(gr, label, kind, items)
        uilabel(gr, 'Text', label);
        switch kind
            case 'dd'
                h = uidropdown(gr, 'Items', items, 'ValueChangedFcn', @(~, ~) onChange());
            case 'num'
                h = uieditfield(gr, 'numeric', 'ValueChangedFcn', @(~, ~) onChange());
            case 'chk'
                h = uicheckbox(gr, 'Text', '', 'ValueChangedFcn', @(~, ~) onChange());
            case 'pair'
                q = uigridlayout(gr, [1 2]); q.Padding = [0 0 0 0]; q.ColumnSpacing = 4;
                h = [uieditfield(q, 'numeric', 'ValueChangedFcn', @(~, ~) onChange()), ...
                     uieditfield(q, 'numeric', 'ValueChangedFcn', @(~, ~) onChange())];
            case 'chkpair'
                q = uigridlayout(gr, [1 2]); q.Padding = [0 0 0 0]; q.ColumnWidth = {30, '1x'};
                h = [uicheckbox(q, 'Text', '', 'ValueChangedFcn', @(~, ~) onChange()), ...
                     uieditfield(q, 'numeric', 'ValueChangedFcn', @(~, ~) onChange())];
        end
    end

    function pc = getPc()
        pc = pipelineDefaults();
        pc.mode = ui.mode.Value;
        for i2 = 1:size(stages, 1), pc.pipeline.(stages{i2, 1}) = ui.(stages{i2, 1}).Value; end
        pc.pipeline.geolocateTargets = logical(ui.geo.Value);
        F = pc.scenario.field;
        F.shape = ui.shape.Value; F.length = ui.length(1).Value; F.width = ui.length(2).Value;
        F.bottom = ui.bottom(1).Value; F.top = ui.bottom(2).Value; F.height = ui.height.Value;
        F.rowStyle = ui.rowStyle.Value; F.rowSpacing = ui.rowSpacing(1).Value; F.plantSpacing = ui.rowSpacing(2).Value;
        F.seed = ui.fieldSeed.Value;
        F.obstacle = ui.obstacle.Value; F.keepAllRuns = logical(ui.keepAll.Value);
        pc.scenario.field = F;
        pc.scenario.wind = struct('enabled', logical(ui.wind.Value), 'speed', ui.windSpeed(1).Value, 'dirDeg', ui.windSpeed(2).Value);
        pc.scenario.gust_mps = ui.gust(1).Value; pc.scenario.gustSeed = ui.gust(2).Value;
        pc.scenario.valveDelay_s = ui.delay.Value; pc.scenario.locSeed = ui.locSeed.Value;
        pc.scenario.droneSpeed = ui.speed.Value;
        pc.scenario.hardwareProfile = ui.hw.Value;
        pc.scenario.physics = struct('payload', logical(ui.payload.Value), 'dynamics', logical(ui.dynamics.Value), ...
            'energy', logical(ui.energy.Value), 'atmosphere', logical(ui.atmosphere.Value), ...
            'altitudeModel', logical(ui.altModel(1).Value), 'altitude_m', ui.altModel(2).Value);
    end

    function setPc(pc)
        ui.mode.Value = pc.mode;
        for i2 = 1:size(stages, 1), ui.(stages{i2, 1}).Value = pc.pipeline.(stages{i2, 1}); end
        ui.geo.Value = pc.pipeline.geolocateTargets;
        F = pc.scenario.field;
        ui.shape.Value = F.shape; ui.length(1).Value = F.length; ui.length(2).Value = F.width;
        ui.bottom(1).Value = F.bottom; ui.bottom(2).Value = F.top; ui.height.Value = F.height;
        ui.rowStyle.Value = F.rowStyle; ui.rowSpacing(1).Value = F.rowSpacing; ui.rowSpacing(2).Value = F.plantSpacing;
        ui.fieldSeed.Value = F.seed;
        ui.obstacle.Value = F.obstacle; ui.keepAll.Value = F.keepAllRuns;
        ui.wind.Value = pc.scenario.wind.enabled; ui.windSpeed(1).Value = pc.scenario.wind.speed; ui.windSpeed(2).Value = pc.scenario.wind.dirDeg;
        ui.gust(1).Value = pc.scenario.gust_mps; ui.gust(2).Value = pc.scenario.gustSeed;
        ui.delay.Value = pc.scenario.valveDelay_s; ui.locSeed.Value = pc.scenario.locSeed; ui.speed.Value = pc.scenario.droneSpeed;
        if any(strcmp(ui.hw.ItemsData, pc.scenario.hardwareProfile)), ui.hw.Value = pc.scenario.hardwareProfile; end
        ph = pc.scenario.physics;
        ui.payload.Value = ph.payload; ui.dynamics.Value = ph.dynamics; ui.energy.Value = ph.energy; ui.atmosphere.Value = ph.atmosphere;
        ui.altModel(1).Value = ph.altitudeModel; ui.altModel(2).Value = ph.altitude_m;
        for i2 = 1:size(stages, 1), st.lastValid.(stages{i2, 1}) = ui.(stages{i2, 1}).Value; end
        onChange();
    end

    function onStage(src, ev, stage)
        T = R.(stage);
        k = find(strcmp(T.id, ev.Value), 1);
        if ~T.available(k)
            alertIf(sprintf('%s: "%s" is UNAVAILABLE.\n%s\nThe previous choice is kept - nothing is substituted.', stage, T.label{k}, T.note{k}), 'Unavailable method');
            src.Value = st.lastValid.(stage);
            return;
        end
        st.lastValid.(stage) = ev.Value;
        onChange();
    end

    function onChange()
        if isempty(st.last)
            ui.pending.Text = 'No run yet - press RUN SELECTED';
            return;
        end
        [h, ~, ~] = pipelineHash(getPc());
        if strcmp(h, st.last.pcRequestedHash)
            ui.pending.Text = sprintf('Up to date: %s', st.last.runId);
            ui.pending.FontColor = [0 0.45 0.1];
        else
            ui.pending.Text = 'Pending changes - press RUN SELECTED';
            ui.pending.FontColor = [0.75 0.35 0];
        end
    end

    % ------------------------------------------------------------------ actions
    function res = runSelected()
        res = [];
        pc = getPc();
        [ok, errs, ~] = validatePipeline(pc);
        if ~ok, alertIf(strjoin(errs, newline), 'Invalid pipeline'); return; end
        dlg = progress('Running the two-pass mission with the selected pipeline ...');
        try
            res = runPipeline(pc);
        catch ME
            closeDlg(dlg);
            alertIf(ME.message, 'Run failed'); res = []; return;
        end
        closeDlg(dlg);
        [res.pcRequestedHash, ~, ~] = pipelineHash(pc);
        st.last = res;
        showRun(res);
        onChange();
    end

    function res = compareWith()
        res = [];
        if isempty(st.compare)
            if isempty(st.last), alertIf('Run a first pipeline with RUN SELECTED.', 'Nothing to compare'); return; end
            st.compare = {st.last};
        end
        if numel(st.compare) >= 4, alertIf('At most 4 runs can be compared. Clear the comparison first.', 'Comparison full'); return; end
        pc = getPc();
        [~, hS] = pipelineHash(pc);
        if ~strcmp(hS, st.compare{1}.scenarioHash)
            alertIf(['The scenario differs from the first compared run (field, seeds or environment changed). ' ...
                'A paired comparison needs the identical scenario: restore it or clear the comparison.'], 'Not a paired comparison');
            return;
        end
        res = runSelected();
        if isempty(res), return; end
        st.compare{end+1} = res;
        showCompare();
    end

    function showCompare()
        if isempty(st.compare), ui.cmpTable.Data = table(); ui.cmpInfo.Text = 'No comparison.'; return; end
        T = comparePipelineRuns(st.compare);
        ui.cmpTable.Data = roundT(T);
        ui.cmpTable.ColumnName = T.Properties.VariableNames;
        ui.cmpTable.ColumnWidth = [{62, 140, 78}, repmat({58}, 1, width(T) - 3)];
        ui.cmpTable.FontSize = 10;
        labs = strjoin(cellfun(@(r, k) sprintf('Run%d = %s', k, pipelineLabel(r.pc)), st.compare, num2cell(1:numel(st.compare)), ...
            'UniformOutput', false), '   ');
        ui.cmpInfo.Text = sprintf('%s. %s', T.Properties.Description, labs);
    end

    function clearCompare()
        st.compare = {};
        showCompare();
    end

    function resetLegacy()
        setPc(pipelineDefaults());
    end

    function saveCfg()
        [f, p] = uiputfile('*.json', 'Save pipeline configuration', 'pipeline_config.json');
        if isequal(f, 0), return; end
        savePipelineConfig(getPc(), fullfile(p, f));
    end

    function loadCfg()
        [f, p] = uigetfile('*.json', 'Load pipeline configuration');
        if isequal(f, 0), return; end
        [pc, w] = loadPipelineConfig(fullfile(p, f));
        setPc(pc);
        if ~isempty(w), alertIf(strjoin(w, newline), 'Configuration loaded with notes'); end
    end

    function d = exportRun(baseDir)
        d = '';
        if isempty(st.last), alertIf('Nothing to export: run a pipeline first.', 'No run'); return; end
        if nargin < 1, baseDir = ''; end
        cmpT = [];
        if numel(st.compare) >= 2, cmpT = comparePipelineRuns(st.compare); end
        d = exportPipelineRun(st.last, baseDir, cmpT);
        alertIf(['Exported to ' d], 'Exported');
    end

    function replayInMission()
        if isempty(st.last) || isempty(app), return; end
        app.replayExternalRun(st.last);
    end

    % ------------------------------------------------------------------ display
    function showRun(res)
        S = res.pc.scenario;
        ui.title.Text = sprintf('%s   [%s]', pipelineLabel(res.pc), res.runId);
        ui.metrics.Data = roundT(res.runMetrics);
        info = {sprintf('Run ID     : %s', res.runId), sprintf('Config hash: %s', res.configHash(1:16)), ...
            sprintf('Scenario   : %s', res.scenarioHash(1:16)), sprintf('Code       : %s', res.codeHash), ...
            sprintf('Seeds      : field %d | gust %d | localization %d', S.field.seed, S.gustSeed, S.locSeed), ...
            sprintf('Mode       : %s', res.pcRequested.mode)};
        for i2 = 1:size(stages, 1)
            I = res.info.(stages{i2, 1});
            info{end+1} = sprintf('%-17s: %s [%s] %s', stages{i2, 2}, I.id, I.status, I.implementation); %#ok<AGROW>
        end
        info{end+1} = ['Features   : ' strjoin(res.info.enabledFeatures, ', ')];
        info{end+1} = ['Calibration: ' res.info.calibration];
        ui.info.Value = info;
        w = res.warnings; if isempty(w), w = {'none'}; end
        ui.warn.Value = w;
        ui.replay.Enable = onoff(~isempty(app));
        drawRun();
    end

    function drawRun()
        if isempty(st.last), return; end
        res = st.last; ax = ui.ax; f = res.field; r = res.run; c = res.cfg;
        cla(ax, 'reset'); hold(ax, 'on'); axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'on');
        if ui.ovDep.Value
            mx = max(r.grid.mass(:)); if mx <= 0, mx = 1; end
            imagesc(ax, r.grid.xv, r.grid.yv, r.grid.mass, 'AlphaData', double(r.grid.mass > 0.02 * mx), 'HandleVisibility', 'off');
            set(ax, 'YDir', 'normal'); colormap(ax, parula);
        end
        patch(ax, f.polygon(:, 1), f.polygon(:, 2), 'w', 'FaceColor', 'none', 'EdgeColor', 'k', 'LineWidth', 1.5, 'DisplayName', 'field');
        for q = 1:numel(f.rows), plot(ax, f.rows{q}(:, 1), f.rows{q}(:, 2), '-', 'Color', [0.9 0.9 0.9], 'HandleVisibility', 'off'); end
        if isfield(f, 'obstacles')
            for q = 1:numel(f.obstacles)
                patch(ax, f.obstacles{q}(:, 1), f.obstacles{q}(:, 2), [0.55 0.75 0.95], 'EdgeColor', [0.2 0.4 0.7], ...
                    'DisplayName', 'obstacle (no-fly)', 'HandleVisibility', onoff(q == 1));
            end
        end
        P = f.plants;
        if ui.ovTruth.Value
            dis = P.TrueDisease == "DISEASED";
            dose = plantDose(c, f, r.grid);
            tr = dose >= c.internal2.metrics.treatedDoseFraction * c.internal2.spray.flowRate * c.internal2.spray.duration;
            scatter(ax, P.X(~dis), P.Y(~dis), 10, [0.7 0.7 0.7], 'filled', 'DisplayName', 'healthy');
            scatter(ax, P.X(dis & ~tr), P.Y(dis & ~tr), 30, [0.85 0.1 0.1], 'filled', 'DisplayName', 'diseased, NOT treated');
            scatter(ax, P.X(dis & tr), P.Y(dis & tr), 30, [0.1 0.3 0.95], 'filled', 'DisplayName', 'diseased, treated');
        else
            scatter(ax, P.X, P.Y, 10, [0.7 0.7 0.7], 'filled', 'DisplayName', 'plants');
        end
        plot(ax, r.targets.XY(:, 1), r.targets.XY(:, 2), 'ko', 'MarkerSize', 9, 'DisplayName', 'flagged targets');
        plot(ax, r.log1.truePos(:, 1), r.log1.truePos(:, 2), '-', 'Color', [0.1 0.35 0.9], 'LineWidth', 1.2, 'DisplayName', 'survey (true)');
        if ~isempty(r.legLogs)
            tp = cell2mat(cellfun(@(L) L.truePos, r.legLogs(:), 'UniformOutput', false));
            plot(ax, tp(:, 1), tp(:, 2), '-', 'Color', [0.8 0.1 0.8], 'LineWidth', 1.2, 'DisplayName', 'treatment (true)');
        end
        if ui.ovEst.Value
            ep = [r.log1.estPos; cell2mat(cellfun(@(L) L.estPos, r.legLogs(:), 'UniformOutput', false))];
            plot(ax, ep(:, 1), ep(:, 2), ':', 'Color', [0.2 0.2 0.2], 'LineWidth', 1.0, 'DisplayName', 'estimated track');
        end
        if ui.ovRel.Value
            plot(ax, r.releasePts(:, 1), r.releasePts(:, 2), 'kx', 'MarkerSize', 7, 'DisplayName', 'release points');
        end
        if c.internal2.wind.enabled
            bx = min(f.polygon(:, 1)); by = max(f.polygon(:, 2)) + 1.5; a = c.internal2.wind.dirDeg;
            quiver(ax, bx, by, 2 * cosd(a), 2 * sind(a), 0, 'b', 'LineWidth', 2, 'MaxHeadSize', 1.5, 'DisplayName', 'wind');
        end
        legend(ax, 'Location', 'southoutside', 'NumColumns', 4, 'FontSize', 8, 'Box', 'off');
        xlabel(ax, 'X (m)'); ylabel(ax, 'Y (m)');
    end

    % ------------------------------------------------------------------ helpers
    function alertIf(msg, ttl)
        f = ancestor(parent, 'figure');
        if ~isempty(f) && strcmp(f.Visible, 'on'), uialert(f, msg, ttl); else, warning('pipelineBuilder:alert', '%s: %s', ttl, msg); end
    end
    function d = progress(msg)
        f = ancestor(parent, 'figure'); d = [];
        if ~isempty(f) && strcmp(f.Visible, 'on'), d = uiprogressdlg(f, 'Title', 'Pipeline run', 'Message', msg, 'Indeterminate', 'on'); end
    end
    function closeDlg(d)
        if ~isempty(d) && isvalid(d), close(d); end
    end
end

function D = roundT(T)
    D = T;
    for i = 1:width(D)
        if isnumeric(D{:, i}), D{:, i} = round(D{:, i}, 3); end
    end
end

function s = onoff(b)
    if b, s = 'on'; else, s = 'off'; end
end
