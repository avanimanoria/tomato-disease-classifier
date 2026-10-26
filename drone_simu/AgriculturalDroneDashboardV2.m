classdef AgriculturalDroneDashboardV2 < matlab.apps.AppBase
    %AGRICULTURALDRONEDASHBOARDV2 Mission dashboard on top of the frozen Internal-2 engine.
    %
    %   app = AgriculturalDroneDashboardV2;                    % run it
    %   app = AgriculturalDroneDashboardV2('Visible', 'off', 'AutoPlay', false);   % tests
    %
    %   COMPUTE-THEN-REPLAY: START builds one cfg from the controls (uiToConfig),
    %   runs ONE mission with the shared engine (runInternal2Scenario) and then
    %   replays the exact generated logs. PAUSE / RESUME / STOP / RESET act on
    %   playback only; configuration is locked while a replay is active. Nothing
    %   is simulated incrementally and nothing here contains scenario logic: the
    %   preset dropdown only sets the three switches (scenarioPresets) and its label
    %   is recomputed from the switches (matchPreset), so manual edits show "Custom".
    %
    %   INFORMATION BOUNDARY: Mission mode shows only what the drone could know. The
    %   map, the observation card, the treatment status and the completion summary are
    %   functions of the replayed prefix and the detector's output; the hidden plant
    %   labels and all ground-truth evaluation belong to Experiments mode (a later
    %   milestone). golden/testDashboardV2.m enforces this with a source scan and a
    %   perturbation test.
    %
    %   Geometry controls (shape, dimensions, row style, spacings) invalidate the
    %   generated field immediately; every other setting simply applies on next START.

    properties (Access = public)
        UIFigure        matlab.ui.Figure
        ModeTabs        matlab.ui.container.TabGroup

        % ---- left: configuration ----
        PresetDropDown  matlab.ui.control.DropDown
        ShapeDropDown   matlab.ui.control.DropDown
        RectLengthEdit  matlab.ui.control.NumericEditField
        RectWidthEdit   matlab.ui.control.NumericEditField
        TrapBottomEdit  matlab.ui.control.NumericEditField
        TrapTopEdit     matlab.ui.control.NumericEditField
        TrapHeightEdit  matlab.ui.control.NumericEditField
        RowStyleDropDown matlab.ui.control.DropDown
        RowSpacingEdit  matlab.ui.control.NumericEditField
        PlantSpacingEdit matlab.ui.control.NumericEditField
        FieldGrid       matlab.ui.container.GridLayout
        FieldInfoLabel  matlab.ui.control.Label
        WindCheck       matlab.ui.control.CheckBox
        WindSpeedEdit   matlab.ui.control.NumericEditField
        WindDirEdit     matlab.ui.control.NumericEditField
        PidCheck        matlab.ui.control.CheckBox
        RoutingDropDown matlab.ui.control.DropDown
        AdvRoutingCheck matlab.ui.control.CheckBox
        CompCheck       matlab.ui.control.CheckBox
        DroneSpeedEdit  matlab.ui.control.NumericEditField
        PlaybackEdit    matlab.ui.control.NumericEditField
        GenerateButton  matlab.ui.control.Button
        StartButton     matlab.ui.control.Button
        PauseButton     matlab.ui.control.Button
        ResumeButton    matlab.ui.control.Button
        StopButton      matlab.ui.control.Button
        ResetButton     matlab.ui.control.Button

        % ---- centre: map + summary ----
        PhaseLabel      matlab.ui.control.Label
        MapAxes         matlab.ui.control.UIAxes
        RefCheck        matlab.ui.control.CheckBox
        TrajCheck       matlab.ui.control.CheckBox
        FlagCheck       matlab.ui.control.CheckBox
        RouteCheck      matlab.ui.control.CheckBox
        ReleaseCheck    matlab.ui.control.CheckBox
        SprayCheck      matlab.ui.control.CheckBox
        CenterGrid      matlab.ui.container.GridLayout
        SummaryPanel    matlab.ui.container.Panel
        SummaryLeft     matlab.ui.control.Label
        SummaryRight    matlab.ui.control.Label
        SummaryAdv      matlab.ui.control.Label

        % ---- advanced options (enhancement; master switch default OFF) ----
        AdvMasterCheck  matlab.ui.control.CheckBox     % on the MISSION tab
        AdvMasterCheck2 matlab.ui.control.CheckBox     % same switch, on the ADVANCED OPTIONS tab
        AdvStatusLabel  matlab.ui.control.Label
        PosSrcLabel     matlab.ui.control.Label
        EstimatorLabel  matlab.ui.control.Label
        AltLabel        matlab.ui.control.Label
        TelAx1          matlab.ui.control.UIAxes
        TelAx2          matlab.ui.control.UIAxes

        % ---- right: status ----
        StateLabel      matlab.ui.control.Label
        PosLabel        matlab.ui.control.Label
        SpeedLabel      matlab.ui.control.Label
        TimeLabel       matlab.ui.control.Label
        DistLabel       matlab.ui.control.Label
        CrossLabel      matlab.ui.control.Label
        ObsPanel        matlab.ui.container.Panel
        ObsAxes         matlab.ui.control.UIAxes
        ObsIdLabel      matlab.ui.control.Label
        ObsPosLabel     matlab.ui.control.Label
        ObsStateLabel   matlab.ui.control.Label
        ObsDetLabel     matlab.ui.control.Label
        ObsCountLabel   matlab.ui.control.Label
        TrFlagLabel     matlab.ui.control.Label
        TrTargetLabel   matlab.ui.control.Label
        TrSprayedLabel  matlab.ui.control.Label
        TrRouteLabel    matlab.ui.control.Label
        TrPumpLabel     matlab.ui.control.Label
        TrEmitLabel     matlab.ui.control.Label

        Timer           timer
    end

    properties (Access = public)
        mode = 'NOFIELD'     % NOFIELD | READY | COMPUTING | PLAYING | PAUSED | STOPPED | DONE
        field                % from generateIrregularField
        fieldKey             % geometry values the field was generated with
        cfg                  % cfg used for the current/last mission
        run                  % engine output of the current mission
        tl                   % replay timeline
        cursor = 1           % replay step (float)
        lastTic = []
        autoPlay = true      % false in tests: no wall-clock timer, replay advanced via tickOnce
        frames = 0           % render count (diagnostics)
        obsKey = []          % last drawn observation-schematic state (avoids redrawing every frame)
        h = struct()         % graphics handles on the map
        AdvCtl = struct()    % advanced-option controls: AdvCtl.(feature).enable / .(parameter)
        telH = struct()      % advanced telemetry line handles
        PipelineView = struct()   % api of the PIPELINE BUILDER tab (pipelineBuilderView)
    end

    properties (Constant)
        cUnseen = [0.82 0.82 0.82]
        cObserved = [0.25 0.62 0.32]
        cFlagged = [0.86 0.12 0.08]
    end

    % ================================================================== public API
    methods (Access = public)
        function app = AgriculturalDroneDashboardV2(varargin)
            vis = 'on';
            for i = 1:2:numel(varargin)
                if strcmpi(varargin{i}, 'Visible'), vis = varargin{i+1}; end
                if strcmpi(varargin{i}, 'AutoPlay'), app.autoPlay = logical(varargin{i+1}); end
            end
            createComponents(app, vis);
            app.Timer = timer('ExecutionMode', 'fixedRate', 'Period', 0.05, 'BusyMode', 'drop', ...
                'TimerFcn', @(~, ~) app.onTick());
            app.syncPresetLabel();
            app.updateWindEnable();
            app.updateShapeRows();
            app.updateAdvEnable();
            app.setMode('NOFIELD');
            app.drawEmptyMap('Set the configuration, then GENERATE FIELD');
            app.resetPanels();
        end

        function delete(app)
            if ~isempty(app.Timer) && isvalid(app.Timer)
                stop(app.Timer);
                delete(app.Timer);
            end
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end

        function s = readControls(app)
            %READCONTROLS Current control values as the struct uiToConfig expects.
            s.wind = logical(app.WindCheck.Value);
            s.pid = logical(app.PidCheck.Value);
            s.comp = logical(app.CompCheck.Value);
            s.windSpeed = app.WindSpeedEdit.Value;
            s.windDirDeg = app.WindDirEdit.Value;
            s.routing = app.RoutingDropDown.Value;
            s.advancedRouting = logical(app.AdvRoutingCheck.Value);
            s.droneSpeed = app.DroneSpeedEdit.Value;
            s.rowSpacing = app.RowSpacingEdit.Value;
            s.plantSpacing = app.PlantSpacingEdit.Value;
            s.shape = app.ShapeDropDown.Value;
            s.rect = struct('length', app.RectLengthEdit.Value, 'width', app.RectWidthEdit.Value);
            s.trap = struct('bottom', app.TrapBottomEdit.Value, 'top', app.TrapTopEdit.Value, ...
                            'height', app.TrapHeightEdit.Value);
            s.rowStyle = app.RowStyleDropDown.Value;
            s.adv = app.readAdvControls();
        end

        function setSwitches(app, wind, pid, comp)
            %SETSWITCHES Set the three independent switches (as a user would) and refresh the label.
            app.WindCheck.Value = logical(wind);
            app.PidCheck.Value = logical(pid);
            app.CompCheck.Value = logical(comp);
            app.onSwitchChanged();
        end

        function generateField(app)
            try
                c = uiToConfig(app.readControls());
                evalc('f = generateIrregularField(c);');     % the engine prints a summary; keep the console quiet
            catch ME
                app.alert(ME.message, 'Field generation');
                return;
            end
            app.field = f;
            app.fieldKey = app.geometryKey();
            app.run = []; app.tl = []; app.cursor = 1;
            app.FieldInfoLabel.Text = sprintf('Rows: %d | Plants: %d | Survey path: %.1f m', ...
                f.numRows, height(f.plants), f.surveyRef.len);
            app.drawField(c);
            app.setText(app.PhaseLabel, 'Field generated - press START');
            app.resetPanels();
            app.setMode('READY');
        end

        function startMission(app)
            if ~any(strcmp(app.mode, {'READY', 'STOPPED', 'DONE'}))
                return;
            end
            if isempty(app.field)
                app.alert('Generate the field first.', 'No field'); return;
            end
            if ~isequal(app.fieldKey, app.geometryKey())
                app.alert('Field geometry changed since the field was generated. Press GENERATE FIELD.', 'Field out of date');
                return;
            end
            prev = app.mode;
            app.setMode('COMPUTING');
            dlg = [];
            try
                s = app.readControls();
                c = uiToConfig(s);
                label = matchPreset(s.wind, s.pid, s.comp);
                if strcmp(app.UIFigure.Visible, 'on')
                    dlg = uiprogressdlg(app.UIFigure, 'Title', 'Computing mission', ...
                        'Message', 'Running the Internal-2 engine (a few seconds) ...', 'Indeterminate', 'on');
                end
                r = runInternal2Scenario(c, app.field, label);
                if isfield(r, 'cfgEffective'), c = r.cfgEffective; end   % advanced runs: altitude-derived values
                t = missionTimeline(c, app.field, r);
            catch ME
                if ~isempty(dlg) && isvalid(dlg), close(dlg); end
                app.alert(ME.message, 'Mission computation failed');
                app.setMode(prev);
                return;
            end
            if ~isempty(dlg) && isvalid(dlg), close(dlg); end
            app.cfg = c; app.run = r; app.tl = t;
            app.cursor = 1;
            app.drawField(c);
            app.expandLimits(t.pos);
            app.setSummaryConfig(label, c);
            app.setupTelemetry();
            app.updateSystemStatus(c);
            app.lastTic = tic;
            app.setMode('PLAYING');
            app.render(1);
            if app.autoPlay, start(app.Timer); end
        end

        function pauseMission(app)
            if strcmp(app.mode, 'PLAYING')
                stopTimer(app);
                app.setMode('PAUSED');
            end
        end

        function resumeMission(app)
            if strcmp(app.mode, 'PAUSED')
                app.lastTic = tic;
                app.setMode('PLAYING');
                if app.autoPlay, start(app.Timer); end
            end
        end

        function stopMission(app)
            if any(strcmp(app.mode, {'PLAYING', 'PAUSED'}))
                stopTimer(app);
                app.setMode('STOPPED');
                app.setText(app.PhaseLabel, [app.PhaseLabel.Text '   [STOPPED]']);
            end
        end

        function resetMission(app)
            if any(strcmp(app.mode, {'NOFIELD', 'COMPUTING'})), return; end
            stopTimer(app);
            app.run = []; app.tl = []; app.cursor = 1;
            if isempty(app.field)
                app.setMode('NOFIELD'); return;
            end
            c = uiToConfig(app.readControls());
            app.drawField(c);
            app.setText(app.PhaseLabel, 'Reset - press START');
            app.resetPanels();
            app.setMode('READY');
        end

        function replayExternalRun(app, res)
            %REPLAYEXTERNALRUN Replay a PIPELINE BUILDER run in this Mission view (same replay layer).
            %   The Mission configuration controls are not changed; the field is marked as external,
            %   so START requires GENERATE FIELD again.
            stopTimer(app);
            app.field = res.field; app.fieldKey = []; app.cfg = res.cfg; app.run = res.run;
            app.tl = missionTimeline(res.cfg, res.field, res.run); app.cursor = 1;
            app.drawField(res.cfg);
            app.expandLimits(app.tl.pos);
            app.setSummaryConfig('Custom', res.cfg);
            txt = app.SummaryLeft.Text; txt{1} = ['Pipeline run ' res.runId]; txt{2} = pipelineLabel(res.pc);
            app.SummaryLeft.Text = txt;
            app.setupTelemetry();
            app.updateSystemStatus(res.cfg);
            app.FieldInfoLabel.Text = 'Field from PIPELINE BUILDER - press GENERATE FIELD to return';
            app.lastTic = tic;
            app.setMode('PLAYING');
            app.render(1);
            app.ModeTabs.SelectedTab = app.ModeTabs.Children(1);
            if app.autoPlay, start(app.Timer); end
        end

        function tickOnce(app, nSteps)
            %TICKONCE Advance the replay by nSteps steps (test hook; same path as the timer).
            if ~strcmp(app.mode, 'PLAYING'), return; end
            app.advance(nSteps);
        end

        function seek(app, k)
            %SEEK Jump the replay display to step k (test hook).
            if isempty(app.tl), return; end
            app.cursor = min(max(k, 1), app.tl.N);
            app.render(round(app.cursor));
            if app.cursor >= app.tl.N && any(strcmp(app.mode, {'PLAYING', 'PAUSED'}))
                stopTimer(app);
                app.setMode('DONE');
            end
        end
    end

    % ================================================================== callbacks / logic
    methods (Access = private)
        function onPresetChanged(app)
            ui = app.PresetDropDown.Value;
            [uiNames, backend] = presetUiName();
            k = find(strcmp(uiNames, ui), 1);
            if ~isempty(k)
                T = scenarioPresets();
                j = find(T.name == string(backend{k}), 1);
                app.WindCheck.Value = T.wind(j);
                app.PidCheck.Value = T.pid(j);
                app.CompCheck.Value = T.comp(j);
            end
            app.onSwitchChanged();      % "Custom" (or any edit) re-derives the label from the switches
        end

        function onAdvRoutingChanged(app)
            %ONADVROUTINGCHANGED Show the optional routing algorithms only when the user opts in.
            base = {'fixedOrder', 'nearestNeighbour', 'stage7Return'};
            if app.AdvRoutingCheck.Value
                app.RoutingDropDown.Items = [base, {'nearestNeighbour2opt', 'cheapestInsertion', 'nearestNeighbourOrOpt', 'antColony'}];
            else
                if ~any(strcmp(app.RoutingDropDown.Value, base)), app.RoutingDropDown.Value = 'nearestNeighbour'; end
                app.RoutingDropDown.Items = base;
            end
        end

        function onSwitchChanged(app)
            app.updateWindEnable();
            app.syncPresetLabel();
        end

        function onGeometryChanged(app)
            %ONGEOMETRYCHANGED Any geometry control invalidates the generated field.
            app.updateShapeRows();
            if isempty(app.field) || app.configLocked(), return; end
            stopTimer(app);
            app.field = []; app.fieldKey = []; app.run = []; app.tl = []; app.cursor = 1;
            app.FieldInfoLabel.Text = 'Geometry changed - generate the field again';
            app.drawEmptyMap('Geometry changed - press GENERATE FIELD');
            app.resetPanels();
            app.setMode('NOFIELD');
        end

        function syncPresetLabel(app)
            name = matchPreset(app.WindCheck.Value, app.PidCheck.Value, app.CompCheck.Value);
            app.PresetDropDown.Value = presetUiName(name);
        end

        function updateWindEnable(app)
            on = app.WindCheck.Value && ~app.configLocked();
            app.WindSpeedEdit.Enable = onoff(on);
            app.WindDirEdit.Enable = onoff(on);
        end

        function updateShapeRows(app)
            rect = strcmp(app.ShapeDropDown.Value, 'Rectangle');
            rh = app.FieldGrid.RowHeight;
            rh(2:3) = {ternary(rect, 22, 0)};
            rh(4:6) = {ternary(rect, 0, 22)};
            app.FieldGrid.RowHeight = rh;
            set([app.RectLengthEdit app.RectWidthEdit], 'Visible', onoff(rect));
            set([app.TrapBottomEdit app.TrapTopEdit app.TrapHeightEdit], 'Visible', onoff(~rect));
            ch = app.FieldGrid.Children;
            for i = 1:numel(ch)
                if strcmp(ch(i).Tag, 'rectLbl'), ch(i).Visible = onoff(rect); end
                if strcmp(ch(i).Tag, 'trapLbl'), ch(i).Visible = onoff(~rect); end
            end
        end

        function k = geometryKey(app)
            s = app.readControls();
            k = struct('shape', s.shape, 'rect', s.rect, 'trap', s.trap, 'rowStyle', s.rowStyle, ...
                       'rowSpacing', s.rowSpacing, 'plantSpacing', s.plantSpacing);
        end

        function tf = configLocked(app)
            tf = any(strcmp(app.mode, {'PLAYING', 'PAUSED', 'COMPUTING'}));
        end

        function setMode(app, m)
            app.mode = m;
            locked = app.configLocked();
            cfgCtl = [app.PresetDropDown app.ShapeDropDown app.RectLengthEdit app.RectWidthEdit ...
                      app.TrapBottomEdit app.TrapTopEdit app.TrapHeightEdit app.RowStyleDropDown ...
                      app.RowSpacingEdit app.PlantSpacingEdit app.WindCheck app.PidCheck app.CompCheck ...
                      app.RoutingDropDown app.AdvRoutingCheck app.DroneSpeedEdit];
            set(cfgCtl, 'Enable', onoff(~locked));
            app.updateWindEnable();
            app.updateAdvEnable();
            en = struct('gen', any(strcmp(m, {'NOFIELD', 'READY', 'STOPPED', 'DONE'})), ...
                        'start', any(strcmp(m, {'READY', 'STOPPED', 'DONE'})), ...
                        'pause', strcmp(m, 'PLAYING'), ...
                        'resume', strcmp(m, 'PAUSED'), ...
                        'stop', any(strcmp(m, {'PLAYING', 'PAUSED'})), ...
                        'reset', any(strcmp(m, {'PLAYING', 'PAUSED', 'STOPPED', 'DONE', 'READY'})));
            app.GenerateButton.Enable = onoff(en.gen);
            app.StartButton.Enable = onoff(en.start);
            app.PauseButton.Enable = onoff(en.pause);
            app.ResumeButton.Enable = onoff(en.resume);
            app.StopButton.Enable = onoff(en.stop);
            app.ResetButton.Enable = onoff(en.reset);
            app.StateLabel.Text = sprintf('Mission: %s', m);
        end

        function stopTimer(app)
            if strcmp(app.Timer.Running, 'on'), stop(app.Timer); end
        end

        function onTick(app)
            if ~strcmp(app.mode, 'PLAYING') || isempty(app.tl), return; end
            speed = max(1, app.PlaybackEdit.Value);           % simulated s per wall s
            dtWall = min(toc(app.lastTic), 0.25);             % a UI stall must not make playback leap ahead
            app.lastTic = tic;
            app.advance(dtWall * speed / app.tl.dt);
        end

        function advance(app, nSteps)
            app.cursor = min(app.cursor + nSteps, app.tl.N);
            app.render(round(app.cursor));
            if app.cursor >= app.tl.N
                stopTimer(app);
                app.setMode('DONE');
            end
        end

        % ------------------------------------------------------------ map drawing
        function drawEmptyMap(app, msg)
            ax = app.MapAxes;
            cla(ax, 'reset'); hold(ax, 'on'); axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'on');
            xlabel(ax, 'X (m)'); ylabel(ax, 'Y (m)');
            legend(ax, 'off'); axis(ax, 'off');
            text(ax, 0.5, 0.5, msg, 'Units', 'normalized', ...
                'HorizontalAlignment', 'center', 'FontSize', 13, 'Color', [0.45 0.45 0.45]);
            app.setText(app.PhaseLabel, 'No field yet');
            app.h = struct();
            if ~isempty(app.CenterGrid), app.CenterGrid.RowHeight = {32, '1x', 52, 118}; end
        end

        function drawField(app, c)
            ax = app.MapAxes;
            f = app.field;
            P = f.plants;
            cla(ax, 'reset'); hold(ax, 'on'); axis(ax, 'equal'); grid(ax, 'on'); box(ax, 'on');
            xlabel(ax, 'X (m)'); ylabel(ax, 'Y (m)');
            poly = f.polygon;
            pad = 2.0;
            xlim(ax, [min(poly(:,1)) - pad, max(poly(:,1)) + pad]);
            ylim(ax, [min(poly(:,2)) - pad, max(poly(:,2)) + 3.2]);

            h.poly = patch(ax, poly(:,1), poly(:,2), 'w', 'FaceColor', [0.99 0.99 0.97], 'EdgeColor', 'k', 'LineWidth', 1.6);
            for r = 1:numel(f.rows)
                plot(ax, f.rows{r}(:,1), f.rows{r}(:,2), '-', 'Color', [0.90 0.90 0.90], 'HandleVisibility', 'off');
            end
            h.ref = plot(ax, f.surveyRef.pts(:,1), f.surveyRef.pts(:,2), 'k--', 'LineWidth', 0.8);
            h.release = plot(ax, nan, nan, 'x', 'Color', [0.2 0.2 0.2], 'MarkerSize', 7, 'LineWidth', 1.3);
            h.plants = scatter(ax, P.X, P.Y, 26, repmat(app.cUnseen, height(P), 1), 'filled');
            h.flag = plot(ax, nan, nan, 'o', 'Color', [0.1 0.1 0.1], 'MarkerSize', 10, 'LineWidth', 1.2);
            h.trail1 = plot(ax, nan, nan, '-', 'Color', [0.10 0.35 0.90], 'LineWidth', 1.4);
            h.trail2 = plot(ax, nan, nan, '-', 'Color', [0.80 0.10 0.80], 'LineWidth', 1.4);
            h.spray = patch(ax, nan, nan, 'm', 'FaceAlpha', 0.30, 'EdgeColor', 'm', 'Visible', 'off');
            th = linspace(0, 2*pi, 48);
            h.th = th;
            h.cam = plot(ax, nan, nan, '-', 'Color', [0.1 0.6 0.8], 'LineWidth', 1.1);
            h.drone = plot(ax, nan, nan, '^', 'MarkerFaceColor', [0.10 0.35 0.90], 'MarkerEdgeColor', 'w', 'MarkerSize', 11);
            % wind indicator (only when wind is enabled for this configuration)
            wOn = c.internal2.wind.enabled;
            ang = c.internal2.wind.dirDeg;
            bx = min(poly(:,1)) + 1.5; by = max(poly(:,2)) + 1.6;       % arrow centre; spans +-0.9 m around it
            h.wind = quiver(ax, bx - 0.9*cosd(ang), by - 0.9*sind(ang), 1.8*cosd(ang), 1.8*sind(ang), 0, 'Color', [0.1 0.3 0.9], ...
                'LineWidth', 2.2, 'MaxHeadSize', 1.5, 'Visible', onoff(wOn), 'HandleVisibility', 'off');
            h.windTxt = text(ax, bx + 1.6, by, sprintf('Wind %.1f m/s toward %.0f deg', c.internal2.wind.speed, ang), ...
                'Visible', onoff(wOn), 'FontSize', 9, 'Color', [0.1 0.3 0.9], 'VerticalAlignment', 'middle');
            hl = [scatter(ax, nan, nan, 26, app.cUnseen, 'filled'), scatter(ax, nan, nan, 26, app.cObserved, 'filled'), ...
                  scatter(ax, nan, nan, 26, app.cFlagged, 'filled'), h.ref, h.trail1, h.trail2];
            legend(ax, hl, {'Not yet observed', 'Observed (not flagged)', 'Flagged by detector', 'Reference path', ...
                'Actual survey trajectory', 'Treatment route flown'}, 'Location', 'southoutside', ...
                'NumColumns', 3, 'FontSize', 8, 'Box', 'off');
            app.h = h;
            app.applyOverlays();
            set(h.drone, 'XData', f.surveyRef.pts(1,1), 'YData', f.surveyRef.pts(1,2));
            app.fitMapHeight();
        end

        function expandLimits(app, pos)
            ax = app.MapAxes;
            xl = xlim(ax); yl = ylim(ax);
            xlim(ax, [min(xl(1), min(pos(:,1)) - 1), max(xl(2), max(pos(:,1)) + 1)]);
            ylim(ax, [min(yl(1), min(pos(:,2)) - 1), max(yl(2), max(pos(:,2)) + 1)]);
            app.fitMapHeight();
        end

        function applyOverlays(app)
            if isempty(fieldnames(app.h)), return; end
            h = app.h;
            set(h.ref, 'Visible', onoff(app.RefCheck.Value));
            set(h.trail1, 'Visible', onoff(app.TrajCheck.Value));
            set(h.trail2, 'Visible', onoff(app.RouteCheck.Value));
            set(h.flag, 'Visible', onoff(app.FlagCheck.Value));
            set(h.release, 'Visible', onoff(app.ReleaseCheck.Value));
            if ~isempty(app.run)
                if app.ReleaseCheck.Value
                    set(h.release, 'XData', app.run.releasePts(:,1), 'YData', app.run.releasePts(:,2));
                else
                    set(h.release, 'XData', nan, 'YData', nan);
                end
            end
        end

        function render(app, k)
            app.frames = app.frames + 1;
            h = app.h; tl = app.tl;
            st = missionStateAt(tl, k);
            P = app.field.plants;
            C = repmat(app.cUnseen, height(P), 1);
            C(st.observed, :) = repmat(app.cObserved, nnz(st.observed), 1);
            if app.FlagCheck.Value
                C(st.flagged, :) = repmat(app.cFlagged, nnz(st.flagged), 1);
            end
            h.plants.CData = C;
            set(h.flag, 'XData', P.X(st.flagged), 'YData', P.Y(st.flagged));
            p = st.pos;
            set(h.drone, 'XData', p(1), 'YData', p(2));
            set(h.cam, 'XData', p(1) + app.cfg.cameraFovRadius * cos(h.th), 'YData', p(2) + app.cfg.cameraFovRadius * sin(h.th));
            n1 = tl.n1;
            set(h.trail1, 'XData', tl.pos(1:min(k, n1), 1), 'YData', tl.pos(1:min(k, n1), 2));
            if k > n1
                set(h.trail2, 'XData', tl.pos(n1+1:k, 1), 'YData', tl.pos(n1+1:k, 2));
            else
                set(h.trail2, 'XData', nan, 'YData', nan);
            end
            if st.isSpraying && app.SprayCheck.Value
                S = app.cfg.internal2.spray;
                fr = S.releaseHeight * tand(S.nozzleHalfAngle);
                cc = p + app.run.driftTrue;
                set(h.spray, 'XData', cc(1) + fr * cos(h.th), 'YData', cc(2) + fr * sin(h.th), 'Visible', 'on');
            else
                set(h.spray, 'XData', nan, 'YData', nan, 'Visible', 'off');
            end
            app.setText(app.PhaseLabel, st.phaseText);
            app.updateStatus(st);
            app.updateObservation(st);
            app.updateTreatment(st);
            if st.done
                app.showSummary();
            else
                app.SummaryRight.Text = {'Mission summary', 'Shown when the mission completes.'};
            end
            app.updateAdvLive(st);
        end

        function updateStatus(app, st)
            if isempty(st)
                app.setText(app.PosLabel, 'Position: -'); app.setText(app.SpeedLabel, 'Ground speed: -');
                app.setText(app.TimeLabel, 'Mission time: -'); app.setText(app.DistLabel, 'Flown distance: -');
                app.setText(app.CrossLabel, 'Cross-track error: -');
                return;
            end
            k = st.k;
            if k > 1
                spd = norm(app.tl.pos(k, :) - app.tl.pos(k-1, :)) / app.tl.dt;
            else
                spd = 0;
            end
            app.setText(app.PosLabel, sprintf('Position: (%.2f, %.2f) m', st.pos(1), st.pos(2)));
            app.setText(app.SpeedLabel, sprintf('Ground speed: %.2f m/s', spd));
            app.setText(app.TimeLabel, sprintf('Mission time: %.1f s', st.t));
            app.setText(app.DistLabel, sprintf('Flown distance: %.1f m', st.distance));
            app.setText(app.CrossLabel, sprintf('Cross-track error: %+.3f m', st.cross));
        end

        function updateObservation(app, st)
            P = app.field.plants;
            nP = height(P);
            if st.inPass2 && st.tgtPlant > 0
                idx = st.tgtPlant;
                app.ObsPanel.Title = 'Current Treatment Target';
                kind = 'target';
            else
                idx = st.obsPlant;
                app.ObsPanel.Title = 'Current Observation';
                kind = 'obs';
            end
            if idx == 0
                app.setText(app.ObsIdLabel, 'No plant observed yet');
                app.setText(app.ObsPosLabel, '');
                app.setText(app.ObsStateLabel, '');
                app.setText(app.ObsDetLabel, '');
                app.drawObsSchematic(0, false);
            else
                flagged = app.tl.flagStep(idx) > 0 && app.tl.flagStep(idx) <= st.k;
                app.setText(app.ObsIdLabel, sprintf('Plant ID: %s', P.ID(idx)));
                app.setText(app.ObsPosLabel, sprintf('Position: (%.2f, %.2f) m', P.X(idx), P.Y(idx)));
                if strcmp(kind, 'obs')
                    app.setText(app.ObsStateLabel, sprintf('Observed: YES (t = %.1f s)', app.tl.t(app.tl.firstStep(idx))));
                    app.setText(app.ObsDetLabel, ['Detector: ' ternary(flagged, 'FLAGGED', 'NOT FLAGGED')]);
                else
                    stageTxt = {'', 'in transit', 'settling', 'SPRAYING'};
                    if st.done, what = 'mission complete'; elseif st.isRefill, what = 'refill trip'; elseif app.tl.isReturn(st.k), what = 'returning to survey path'; else, what = stageTxt{st.stage}; end
                    app.setText(app.ObsStateLabel, sprintf('Observed: YES (Pass 1) | now: %s', what));
                    app.setText(app.ObsDetLabel, 'Detector: FLAGGED (Pass 1)');
                end
                app.drawObsSchematic(1, flagged);
            end
            app.setText(app.ObsCountLabel, sprintf('Observed %d / %d plants | flagged %d', st.nObserved, nP, st.nFlagged));
        end

        function drawObsSchematic(app, state, flagged)
            key = [state, flagged];
            if isequal(app.obsKey, key), return; end
            app.obsKey = key;
            ax = app.ObsAxes;
            cla(ax); hold(ax, 'on'); axis(ax, 'equal'); axis(ax, 'off');
            th = linspace(0, 2*pi, 60);
            plot(ax, cos(th), sin(th), '-', 'Color', [0.1 0.6 0.8], 'LineWidth', 1.2);
            plot(ax, [-1.25 1.25], [0 0], ':', 'Color', [0.8 0.8 0.8]);
            plot(ax, [0 0], [-1.05 1.05], ':', 'Color', [0.8 0.8 0.8]);
            if state > 0
                col = ternary(flagged, app.cFlagged, app.cObserved);
                scatter(ax, 0, 0, 120, col, 'filled');
                if flagged, plot(ax, 0.38 * cos(th), 0.38 * sin(th), 'k-', 'LineWidth', 1.3); end
            end
            xlim(ax, [-1.4 1.4]); ylim(ax, [-1.15 1.15]);
            text(ax, 0, -1.12, 'schematic: camera footprint (not a photo)', 'FontSize', 7, 'Color', [0.45 0.45 0.45], ...
                'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
        end

        function updateTreatment(app, st)
            nT = app.tl.nTargets;
            if st.inPass2
                app.setText(app.TrFlagLabel, sprintf('Targets queued: %d', nT));
                if st.target > 0
                    app.setText(app.TrTargetLabel, sprintf('Current target: %d / %d (%s)', st.target, nT, app.field.plants.ID(st.tgtPlant)));
                else
                    app.setText(app.TrTargetLabel, 'Current target: -');
                end
                app.setText(app.TrSprayedLabel, sprintf('Sprayed: %d / %d', st.sprayed, nT));
            else
                app.setText(app.TrFlagLabel, sprintf('Flagged so far: %d', st.nFlagged));
                app.setText(app.TrTargetLabel, 'Current target: - (Pass 1)');
                app.setText(app.TrSprayedLabel, 'Sprayed: 0');
            end
            app.setText(app.TrRouteLabel, sprintf('Pass-2 route flown: %.1f m', st.pass2Distance));
            app.setText(app.TrPumpLabel, ['Pump: ' ternary(st.isSpraying, 'ON', 'OFF')]);
            app.setText(app.TrEmitLabel, sprintf('Spray emitted so far: %.0f mL', st.emitted_mL));
        end

        function setSummaryConfig(app, label, c)
            I = c.internal2;
            app.SummaryLeft.Text = { ...
                'Mission configuration', ...
                sprintf('Preset: %s', presetUiName(label)), ...
                sprintf('Wind %s | PID %s | Comp. %s', onoff(I.wind.enabled), onoff(I.ctrl.enabled), onoff(I.spray.compensate)), ...
                sprintf('Routing: %s', I.treat.routing), ...
                sprintf('Drone speed: %.1f m/s', c.droneSpeed)};
            app.SummaryRight.Text = {'Mission summary', 'Shown when the mission completes.'};
        end

        function showSummary(app)
            s = missionSummary(app.tl);
            app.SummaryRight.Text = { ...
                'Mission summary (operational)', ...
                sprintf('Duration %.1f s (Pass 1 %.1f, Pass 2 %.1f)', s.totalTime_s, s.pass1Time_s, s.pass2Time_s), ...
                sprintf('Distance %.1f m (Pass 1 %.1f, Pass 2 %.1f)', s.totalDistance_m, s.pass1Distance_m, s.pass2Distance_m), ...
                sprintf('Plants observed %d / %d | targets flagged %d', s.plantsObserved, s.plantsTotal, s.targetsFlagged), ...
                sprintf('Targets sprayed %d | spray emitted %.0f mL', s.targetsSprayed, s.sprayEmitted_mL)};
        end

        function resetPanels(app)
            app.obsKey = [];
            app.updateStatus([]);
            app.ObsPanel.Title = 'Current Observation';
            app.setText(app.ObsIdLabel, 'No plant observed yet');
            app.setText(app.ObsPosLabel, ''); app.setText(app.ObsStateLabel, ''); app.setText(app.ObsDetLabel, '');
            app.setText(app.ObsCountLabel, 'Observed - / - plants | flagged -');
            app.drawObsSchematic(0, false);
            app.setText(app.TrFlagLabel, 'Flagged so far: -');
            app.setText(app.TrTargetLabel, 'Current target: -');
            app.setText(app.TrSprayedLabel, 'Sprayed: -');
            app.setText(app.TrRouteLabel, 'Pass-2 route flown: -');
            app.setText(app.TrPumpLabel, 'Pump: OFF');
            app.setText(app.TrEmitLabel, 'Spray emitted so far: -');
            app.SummaryLeft.Text = {'Mission configuration', 'No mission run yet.'};
            app.SummaryRight.Text = {'Mission summary', 'Shown when the mission completes.'};
            if ~isempty(app.SummaryAdv)
                app.SummaryAdv.Text = {'Advanced physics', ternary(app.AdvMasterCheck.Value, 'ON - applied on the next START', 'OFF (original simulation)')};
            end
            if ~isempty(app.TelAx1), cla(app.TelAx1); cla(app.TelAx2); app.telH = struct(); end
            if ~isempty(app.PosSrcLabel), app.updateSystemStatus([]); end
        end

        function fitMapHeight(app)
            %FITMAPHEIGHT Size the map row to the field's aspect ratio (no dead space above/below the plot).
            try
                axW = app.MapAxes.Position(3);
                xr = diff(xlim(app.MapAxes)); yr = diff(ylim(app.MapAxes));
                availH = app.CenterGrid.Position(4) - 32 - 52 - 4 * 4;
                need = (max(axW - 100, 200)) * yr / xr + 135;
                need = min(max(need, 300), availH - 110);
                app.CenterGrid.RowHeight = {32, need, 52, '1x'};
            catch
                % layout not measurable yet (e.g. hidden figure): keep the current row heights
            end
        end

        % ------------------------------------------------------------ advanced options (enhancement)
        function createAdvancedTab(app, tabA)
            %CREATEADVANCEDTAB One panel per optional feature: Enable + its parameters (defaults from config.m).
            cfg0 = config();
            [keys, titles] = advFeatures();
            gA = uigridlayout(tabA, [5 4]);
            gA.RowHeight = {30, 262, 262, 262, 300};
            gA.Scrollable = 'on';
            gA.ColumnWidth = {'1x', '1x', '1x', '1x'};
            gA.Padding = [8 6 8 6]; gA.RowSpacing = 6; gA.ColumnSpacing = 8;
            hg = uigridlayout(gA, [1 2]);
            hg.Layout.Row = 1; hg.Layout.Column = [1 4];
            hg.ColumnWidth = {250, '1x'}; hg.Padding = [0 0 0 0];
            app.AdvMasterCheck2 = uicheckbox(hg, 'Text', 'Advanced mode (master switch)', 'FontWeight', 'bold', ...
                'Value', false, 'ValueChangedFcn', @(src, ~) app.onAdvMasterChanged(src));
            app.AdvStatusLabel = uilabel(hg, 'Text', '', 'FontWeight', 'bold');
            for i = 1:numel(keys)
                f = keys{i};
                p = uipanel(gA, 'Title', titles{i});
                p.Layout.Row = 2 + floor((i - 1) / 4);
                p.Layout.Column = mod(i - 1, 4) + 1;
                prm = setdiff(fieldnames(cfg0.enhancements.(f)), {'enabled'}, 'stable');
                pg = uigridlayout(p, [1 + numel(prm), 2]);
                pg.RowHeight = repmat({22}, 1, 1 + numel(prm));
                pg.ColumnWidth = {'1x', 72}; pg.Padding = [8 4 8 4]; pg.RowSpacing = 3;
                pg.Scrollable = 'on';
                ctl = struct();
                ctl.enable = uicheckbox(pg, 'Text', 'Enable', 'Value', false, 'ValueChangedFcn', @(~, ~) app.updateAdvEnable());
                ctl.enable.Layout.Column = [1 2];
                for j = 1:numel(prm)
                    uilabel(pg, 'Text', advParamLabel(prm{j}));
                    dv = cfg0.enhancements.(f).(prm{j});
                    if ischar(dv)
                        ctl.(prm{j}) = uidropdown(pg, 'Items', advParamChoices(f, prm{j}), 'Value', dv);
                    else
                        ctl.(prm{j}) = uieditfield(pg, 'numeric', 'Value', dv);
                    end
                end
                app.AdvCtl.(f) = ctl;
            end
            cp = uipanel(gA, 'Title', 'Considerations: not modelled yet / before any real-world use');
            cp.Layout.Row = 5; cp.Layout.Column = [1 2];
            cg = uigridlayout(cp, [1 1]); cg.Padding = [10 4 10 4];
            uilabel(cg, 'VerticalAlignment', 'top', 'WordWrap', 'on', 'FontSize', 11, 'Text', { ...
                'Not modelled:', ...
                '- Liquid slosh in a partly filled tank', ...
                '- Line pressure, nozzle clogging, severity-based dose (valve delay IS modelled)', ...
                '- Battery voltage sag and temperature; automatic return-to-home', ...
                '- Terrain slope, obstacles, no-fly / buffer zones, non-convex fields', ...
                '- Real camera imaging and CNN detection (detection stays parametric)', ...
                '- Full droplet-size spectrum, wind shear; the stretched kernel is UNCALIBRATED', ...
                '- Full EKF/ESKF or SLAM (the Kalman mode is a linear position filter)', ...
                '- Polygon-decomposition coverage, hardware profiles from datasheets', ...
                '- Product-label dose limits (L/ha) and local regulations', ...
                'Safety limits are advisories only (reported, no change to the flight).', ...
                'Every value is an assumption: calibrate against datasheets, flight logs and spray-card tests.'});
            tp = uipanel(gA, 'Title', 'Advanced telemetry (replayed mission)');
            tp.Layout.Row = 5; tp.Layout.Column = [3 4];
            tg = uigridlayout(tp, [1 2]); tg.Padding = [4 4 4 4];
            app.TelAx1 = uiaxes(tg);
            app.TelAx2 = uiaxes(tg);
            title(app.TelAx1, 'Payload'); title(app.TelAx2, 'Energy / localization');
        end

        function A = readAdvControls(app)
            A.enabled = logical(app.AdvMasterCheck.Value);
            keys = advFeatures();
            for i = 1:numel(keys)
                f = keys{i};
                ctl = app.AdvCtl.(f);
                fn = fieldnames(ctl);
                for j = 1:numel(fn)
                    if strcmp(fn{j}, 'enable')
                        A.(f).enabled = logical(ctl.enable.Value);
                    else
                        A.(f).(fn{j}) = ctl.(fn{j}).Value;
                    end
                end
            end
        end

        function onAdvMasterChanged(app, src)
            app.AdvMasterCheck.Value = src.Value;
            app.AdvMasterCheck2.Value = src.Value;
            app.updateAdvEnable();
        end

        function updateAdvEnable(app)
            if isempty(fieldnames(app.AdvCtl)), return; end
            master = app.AdvMasterCheck.Value;
            locked = app.configLocked();
            app.AdvMasterCheck.Enable = onoff(~locked);
            app.AdvMasterCheck2.Enable = onoff(~locked);
            keys = advFeatures();
            nOn = 0;
            for i = 1:numel(keys)
                ctl = app.AdvCtl.(keys{i});
                ctl.enable.Enable = onoff(master && ~locked);
                fn = setdiff(fieldnames(ctl), {'enable'});
                for j = 1:numel(fn)
                    ctl.(fn{j}).Enable = onoff(master && ~locked && ctl.enable.Value);
                end
                nOn = nOn + (master && ctl.enable.Value);
            end
            if master && app.AdvCtl.perception.enable.Value
                app.AltLabel.Text = 'Altitude: set in ADVANCED OPTIONS (perception model on)';
            else
                app.AltLabel.Text = sprintf('Altitude: %.1f m (model assumption, not simulated)', config().flightAltitude);
            end
            if ~master
                app.AdvStatusLabel.Text = 'Advanced mode is OFF: the simulation runs exactly as the original.';
                app.AdvStatusLabel.FontColor = [0.3 0.3 0.3];
            elseif nOn == 0
                app.AdvStatusLabel.Text = 'Advanced mode ON, but no feature enabled: still the original simulation.';
                app.AdvStatusLabel.FontColor = [0.6 0.4 0];
            else
                app.AdvStatusLabel.Text = sprintf('Advanced mode ON: %d feature(s) enabled - applied on the next START.', nOn);
                app.AdvStatusLabel.FontColor = [0 0.45 0.1];
            end
        end

        function updateSystemStatus(app, c)
            %UPDATESYSTEMSTATUS Position source as actually used by the mission being shown.
            if ~isempty(c) && advOn(c, 'localization')
                lm = c.enhancements.localization.mode;
                app.PosSrcLabel.Text = ['Position: ESTIMATE (' lm ')'];
                if strcmp(lm, 'kalman')
                    app.EstimatorLabel.Text = 'GPS-denied estimator: LINEAR KF (flow + fixes)';
                elseif strcmp(lm, 'errorModel')
                    app.EstimatorLabel.Text = 'GPS-denied estimator: ERROR MODEL ONLY';
                else
                    app.EstimatorLabel.Text = 'GPS-denied estimator: ODOMETRY ONLY (no fixes)';
                end
            else
                app.PosSrcLabel.Text = 'Position: SIMULATION GROUND TRUTH';
                app.EstimatorLabel.Text = 'GPS-denied estimator: NOT INTEGRATED';
            end
        end

        function setupTelemetry(app)
            ax1 = app.TelAx1; ax2 = app.TelAx2;
            cla(ax1, 'reset'); cla(ax2, 'reset');
            app.telH = struct();
            title(ax1, 'Payload'); title(ax2, 'Energy / localization');
            if isempty(app.tl) || ~isfield(app.tl, 'adv')
                text(ax1, 0.5, 0.5, 'Advanced mode off for this mission', 'Units', 'normalized', ...
                    'HorizontalAlignment', 'center', 'Color', [0.5 0.5 0.5]);
                return;
            end
            A = app.tl.adv;
            hold(ax1, 'on'); grid(ax1, 'on');
            app.telH.liq = plot(ax1, nan, nan, 'b-', 'LineWidth', 1.4);
            xlabel(ax1, 'Mission time (s)'); ylabel(ax1, 'Tank liquid (L)');
            ylim(ax1, [0, max(1.05 * A.tankCap, 0.1)]);
            grid(ax2, 'on');
            yyaxis(ax2, 'left');
            app.telH.bat = plot(ax2, nan, nan, '-', 'LineWidth', 1.4);
            ylabel(ax2, 'Battery left (%)'); ylim(ax2, [0 100]);
            yyaxis(ax2, 'right');
            app.telH.err = plot(ax2, nan, nan, '-', 'LineWidth', 1.1);
            ylabel(ax2, 'Estimate error (m, sim truth)');
            xlabel(ax2, 'Mission time (s)');
        end

        function updateAdvLive(app, st)
            tl = app.tl;
            if ~isfield(tl, 'adv')
                app.setText(app.SummaryAdv, {'Advanced physics', 'OFF for this mission (original simulation)'});
                return;
            end
            A = tl.adv; k = st.k;
            lines = {'Advanced physics (live)', sprintf('Tank %.2f / %.1f L | mass %.2f kg', A.liquid(k), A.tankCap, A.mass(k))};
            if A.energyOn
                lines{end+1} = sprintf('Battery left %.0f%% (%.1f Wh used)', 100 * (1 - A.energyWh(k) / A.batteryWh), A.energyWh(k));
            else
                lines{end+1} = 'Energy model off';
            end
            lines{end+1} = sprintf('Refills %d | wind now %.1f m/s', A.refillNo(k), A.wind(k));
            if A.locOn
                lines{end+1} = sprintf('Estimate error %.2f m (sim truth)', A.estErr(k));
            else
                lines{end+1} = 'Position estimate: ground truth';
            end
            if st.done && isfield(app.run, 'advanced') && ~isempty(app.run.advanced.advisories)
                adv = app.run.advanced.advisories;
                lines{end+1} = sprintf('Advisories (%d): %s', numel(adv), adv{1});
            end
            app.setText(app.SummaryAdv, lines);
            if isfield(app.telH, 'liq') && (mod(app.frames, 4) == 0 || st.done || k == 1)
                x = tl.t(1:k);
                set(app.telH.liq, 'XData', x, 'YData', A.liquid(1:k));
                if A.energyOn, set(app.telH.bat, 'XData', x, 'YData', 100 * (1 - A.energyWh(1:k) / A.batteryWh)); end
                if A.locOn, set(app.telH.err, 'XData', x, 'YData', A.estErr(1:k)); end
            end
        end

        function setText(~, lbl, txt)
            % Set a label only when it changes (each uilabel update is a costly browser round-trip).
            if ~isequal(lbl.Text, txt), lbl.Text = txt; end
        end

        function alert(app, msg, ttl)
            if strcmp(app.UIFigure.Visible, 'on')
                uialert(app.UIFigure, msg, ttl);
            else
                warning('AgriculturalDroneDashboardV2:alert', '%s: %s', ttl, msg);
            end
        end

        function overlayChanged(app)
            app.applyOverlays();
            if ~isempty(app.tl) && any(strcmp(app.mode, {'PAUSED', 'STOPPED', 'DONE', 'PLAYING'}))
                app.render(round(app.cursor));
            end
        end

        % ------------------------------------------------------------ components
        function createComponents(app, vis)
            app.UIFigure = uifigure('Name', 'Agricultural Drone Dashboard V2 - Internal-2 engine', ...
                'Position', [20 20 1440 800], 'Visible', vis, 'CloseRequestFcn', @(~, ~) delete(app));
            app.UIFigure.SizeChangedFcn = @(~, ~) app.fitMapHeight();
            rootG = uigridlayout(app.UIFigure, [1 1]);      % tab group fills the window at any size
            rootG.Padding = [0 0 0 0];
            app.ModeTabs = uitabgroup(rootG);
            tabM = uitab(app.ModeTabs, 'Title', 'MISSION');
            tabP = uitab(app.ModeTabs, 'Title', 'PIPELINE BUILDER');
            tabA = uitab(app.ModeTabs, 'Title', 'ADVANCED OPTIONS');
            tabC = uitab(app.ModeTabs, 'Title', 'COMPARATIVE ANALYSIS');
            tabE = uitab(app.ModeTabs, 'Title', 'EXPERIMENTS');
            uilabel(tabE, 'Position', [30 700 900 24], 'FontSize', 14, ...
                'Text', 'Experiments mode (read-only viewer of the frozen saved results) is a later milestone.');

            g = uigridlayout(tabM, [1 3]);
            g.ColumnWidth = {330, '1x', 340};
            g.Padding = [8 6 8 6]; g.ColumnSpacing = 8;

            % ---------------- left column ----------------
            L = uigridlayout(g, [6 1]);
            L.Layout.Column = 1;
            L.RowHeight = {56, 100, 226, 104, 128, 104};
            L.Scrollable = 'on';
            L.Padding = [0 0 0 0];
            L.RowSpacing = 5;

            pp = uipanel(L, 'Title', 'Preset');
            pg = uigridlayout(pp, [1 2]); pg.Padding = [8 4 8 4]; pg.ColumnWidth = {'1x', 118};
            [uiNames, ~] = presetUiName();
            app.PresetDropDown = uidropdown(pg, 'Items', [uiNames {'Custom'}], 'Value', uiNames{1}, ...
                'ValueChangedFcn', @(~, ~) app.onPresetChanged());
            app.AdvMasterCheck = uicheckbox(pg, 'Text', 'Advanced mode', 'Value', false, 'FontWeight', 'bold', ...
                'Tooltip', 'Optional advanced physics (ADVANCED OPTIONS tab). Off = original simulation.', ...
                'ValueChangedFcn', @(src, ~) app.onAdvMasterChanged(src));

            bp = uipanel(L, 'Title', 'Field / Mission Controls');
            bg = uigridlayout(bp, [2 5]);
            bg.RowHeight = {30, 30}; bg.Padding = [8 4 8 4]; bg.RowSpacing = 4; bg.ColumnSpacing = 4;
            app.GenerateButton = uibutton(bg, 'push', 'Text', 'GENERATE FIELD', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(~, ~) app.generateField());
            app.GenerateButton.Layout.Column = [1 5];
            app.StartButton = uibutton(bg, 'push', 'Text', 'START', 'FontWeight', 'bold', 'FontSize', 10, ...
                'BackgroundColor', [0.80 0.93 0.80], 'ButtonPushedFcn', @(~, ~) app.startMission());
            app.PauseButton = uibutton(bg, 'push', 'Text', 'PAUSE', 'FontSize', 10, 'ButtonPushedFcn', @(~, ~) app.pauseMission());
            app.ResumeButton = uibutton(bg, 'push', 'Text', 'RESUME', 'FontSize', 10, 'ButtonPushedFcn', @(~, ~) app.resumeMission());
            app.StopButton = uibutton(bg, 'push', 'Text', 'STOP', 'FontSize', 10, 'ButtonPushedFcn', @(~, ~) app.stopMission());
            app.ResetButton = uibutton(bg, 'push', 'Text', 'RESET', 'FontSize', 10, 'ButtonPushedFcn', @(~, ~) app.resetMission());

            fp = uipanel(L, 'Title', 'Field   (changing these needs GENERATE FIELD)');
            fg = uigridlayout(fp, [10 2]);
            app.FieldGrid = fg;
            fg.ColumnWidth = {140, '1x'};
            fg.RowHeight = repmat({22}, 1, 10);
            fg.Padding = [8 4 8 4]; fg.RowSpacing = 3;
            geo = @(~, ~) app.onGeometryChanged();
            uilabel(fg, 'Text', 'Shape');
            app.ShapeDropDown = uidropdown(fg, 'Items', {'Rectangle', 'Trapezoid'}, 'Value', 'Trapezoid', 'ValueChangedFcn', geo);
            uilabel(fg, 'Text', 'Length (m)', 'Tag', 'rectLbl');
            app.RectLengthEdit = uieditfield(fg, 'numeric', 'Value', 30, 'ValueChangedFcn', geo);
            uilabel(fg, 'Text', 'Width (m)', 'Tag', 'rectLbl');
            app.RectWidthEdit = uieditfield(fg, 'numeric', 'Value', 14, 'ValueChangedFcn', geo);
            uilabel(fg, 'Text', 'Bottom width (m)', 'Tag', 'trapLbl');
            app.TrapBottomEdit = uieditfield(fg, 'numeric', 'Value', 30, 'ValueChangedFcn', geo);
            uilabel(fg, 'Text', 'Top width (m)', 'Tag', 'trapLbl');
            app.TrapTopEdit = uieditfield(fg, 'numeric', 'Value', 18, 'ValueChangedFcn', geo);
            uilabel(fg, 'Text', 'Height (m)', 'Tag', 'trapLbl');
            app.TrapHeightEdit = uieditfield(fg, 'numeric', 'Value', 14, 'ValueChangedFcn', geo);
            uilabel(fg, 'Text', 'Rows');
            app.RowStyleDropDown = uidropdown(fg, 'Items', {'Straight', 'Curved'}, 'Value', 'Curved', 'ValueChangedFcn', geo);
            uilabel(fg, 'Text', 'Row spacing (m)');
            app.RowSpacingEdit = uieditfield(fg, 'numeric', 'Value', 2, 'ValueChangedFcn', geo);
            uilabel(fg, 'Text', 'Plant spacing (m)');
            app.PlantSpacingEdit = uieditfield(fg, 'numeric', 'Value', 0.5, 'ValueChangedFcn', geo);
            app.FieldInfoLabel = uilabel(fg, 'Text', 'No field generated', 'FontColor', [0.35 0.35 0.35], 'FontSize', 11);
            app.FieldInfoLabel.Layout.Column = [1 2];

            ep = uipanel(L, 'Title', 'Environment');
            eg = uigridlayout(ep, [3 2]);
            eg.ColumnWidth = {140, '1x'}; eg.RowHeight = {22, 22, 22}; eg.Padding = [8 4 8 4]; eg.RowSpacing = 3;
            app.WindCheck = uicheckbox(eg, 'Text', 'Wind ON', 'Value', false, ...
                'ValueChangedFcn', @(~, ~) app.onSwitchChanged());
            app.WindCheck.Layout.Column = [1 2];
            uilabel(eg, 'Text', 'Wind speed (m/s)');
            app.WindSpeedEdit = uieditfield(eg, 'numeric', 'Value', 2.0);
            uilabel(eg, 'Text', 'Direction toward (deg)');
            app.WindDirEdit = uieditfield(eg, 'numeric', 'Value', 90);

            np = uipanel(L, 'Title', 'Navigation / Spray');
            ng = uigridlayout(np, [4 2]);
            ng.ColumnWidth = {140, '1x'}; ng.RowHeight = {22, 22, 22, 22}; ng.Padding = [8 4 8 4]; ng.RowSpacing = 3;
            app.PidCheck = uicheckbox(ng, 'Text', 'PID path correction ON', 'Value', false, ...
                'ValueChangedFcn', @(~, ~) app.onSwitchChanged());
            app.PidCheck.Layout.Column = [1 2];
            uilabel(ng, 'Text', 'Pass-2 routing');
            app.RoutingDropDown = uidropdown(ng, 'Items', {'fixedOrder', 'nearestNeighbour', 'stage7Return'}, ...
                'Value', 'nearestNeighbour');
            app.AdvRoutingCheck = uicheckbox(ng, 'Text', 'Advanced routing (enhancement, opt-in)', 'Value', false, ...
                'ValueChangedFcn', @(~, ~) app.onAdvRoutingChanged());
            app.AdvRoutingCheck.Layout.Column = [1 2];
            app.CompCheck = uicheckbox(ng, 'Text', 'Spray compensation ON', 'Value', false, ...
                'ValueChangedFcn', @(~, ~) app.onSwitchChanged());
            app.CompCheck.Layout.Column = [1 2];

            mp = uipanel(L, 'Title', 'Mission');
            mg = uigridlayout(mp, [3 2]);
            mg.ColumnWidth = {140, '1x'}; mg.RowHeight = {22, 22, 22}; mg.Padding = [8 4 8 4]; mg.RowSpacing = 3;
            uilabel(mg, 'Text', 'Drone speed (m/s)');
            app.DroneSpeedEdit = uieditfield(mg, 'numeric', 'Value', 1.5);
            uilabel(mg, 'Text', 'Playback speed (x)');
            app.PlaybackEdit = uieditfield(mg, 'numeric', 'Value', 8);
            cfg0 = config();
            app.AltLabel = uilabel(mg, 'Text', sprintf('Altitude: %.1f m (model assumption, not simulated)', cfg0.flightAltitude), ...
                'FontColor', [0.4 0.4 0.4], 'FontSize', 10);
            app.AltLabel.Layout.Column = [1 2];

            % ---------------- centre column ----------------
            C = uigridlayout(g, [4 1]);
            C.Layout.Column = 2;
            app.CenterGrid = C;
            C.RowHeight = {32, '1x', 52, 118};
            C.Padding = [0 0 0 0]; C.RowSpacing = 4;
            app.PhaseLabel = uilabel(C, 'Text', 'No field yet', 'FontSize', 16, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'BackgroundColor', [0.93 0.95 0.98]);
            app.MapAxes = uiaxes(C);
            og = uigridlayout(C, [2 3]);
            og.Padding = [4 0 4 0]; og.RowSpacing = 2; og.RowHeight = {22, 22};
            app.RefCheck = uicheckbox(og, 'Text', 'Reference path', 'Value', true, 'ValueChangedFcn', @(~, ~) app.overlayChanged());
            app.TrajCheck = uicheckbox(og, 'Text', 'Actual trajectory', 'Value', true, 'ValueChangedFcn', @(~, ~) app.overlayChanged());
            app.FlagCheck = uicheckbox(og, 'Text', 'Flagged targets', 'Value', true, 'ValueChangedFcn', @(~, ~) app.overlayChanged());
            app.RouteCheck = uicheckbox(og, 'Text', 'Treatment route', 'Value', true, 'ValueChangedFcn', @(~, ~) app.overlayChanged());
            app.ReleaseCheck = uicheckbox(og, 'Text', 'Release points', 'Value', false, 'ValueChangedFcn', @(~, ~) app.overlayChanged());
            app.SprayCheck = uicheckbox(og, 'Text', 'Spray footprint', 'Value', false, 'ValueChangedFcn', @(~, ~) app.overlayChanged());

            app.SummaryPanel = uipanel(C, 'Title', 'Mission Summary');
            sg2 = uigridlayout(app.SummaryPanel, [1 3]);
            sg2.Padding = [8 2 8 2]; sg2.ColumnSpacing = 12; sg2.ColumnWidth = {'1x', '1.1x', '1.2x'};
            app.SummaryLeft = uilabel(sg2, 'Text', {'-'}, 'VerticalAlignment', 'top');
            app.SummaryAdv = uilabel(sg2, 'Text', {'-'}, 'VerticalAlignment', 'top', 'FontSize', 11);
            app.SummaryRight = uilabel(sg2, 'Text', {'-'}, 'VerticalAlignment', 'top');

            % ---------------- right column ----------------
            R = uigridlayout(g, [4 1]);
            R.Layout.Column = 3;
            R.RowHeight = {150, 232, 170, 144};
            R.Padding = [0 0 0 0]; R.RowSpacing = 5;

            sp = uipanel(R, 'Title', 'Drone / Navigation Status');
            sg = uigridlayout(sp, [6 1]);
            sg.RowHeight = repmat({19}, 1, 6); sg.Padding = [10 2 10 2]; sg.RowSpacing = 1;
            app.StateLabel = uilabel(sg, 'Text', 'Mission: -', 'FontWeight', 'bold');
            app.PosLabel = uilabel(sg, 'Text', 'Position: -');
            app.SpeedLabel = uilabel(sg, 'Text', 'Ground speed: -');
            app.TimeLabel = uilabel(sg, 'Text', 'Mission time: -');
            app.DistLabel = uilabel(sg, 'Text', 'Flown distance: -');
            app.CrossLabel = uilabel(sg, 'Text', 'Cross-track error: -');

            app.ObsPanel = uipanel(R, 'Title', 'Current Observation');
            og2 = uigridlayout(app.ObsPanel, [6 1]);
            og2.RowHeight = {86, 19, 19, 19, 19, 19}; og2.Padding = [10 2 10 2]; og2.RowSpacing = 1;
            app.ObsAxes = uiaxes(og2);
            app.ObsAxes.Toolbar.Visible = 'off';
            app.ObsAxes.Interactions = [];
            app.ObsIdLabel = uilabel(og2, 'Text', 'No plant observed yet', 'FontWeight', 'bold');
            app.ObsPosLabel = uilabel(og2, 'Text', '');
            app.ObsStateLabel = uilabel(og2, 'Text', '');
            app.ObsDetLabel = uilabel(og2, 'Text', '', 'FontWeight', 'bold');
            app.ObsCountLabel = uilabel(og2, 'Text', '', 'FontColor', [0.35 0.35 0.35]);

            tp = uipanel(R, 'Title', 'Treatment Status');
            tg = uigridlayout(tp, [7 1]);
            tg.RowHeight = repmat({19}, 1, 7); tg.Padding = [10 2 10 2]; tg.RowSpacing = 1;
            app.TrFlagLabel = uilabel(tg, 'Text', 'Flagged so far: -');
            app.TrTargetLabel = uilabel(tg, 'Text', 'Current target: -');
            app.TrSprayedLabel = uilabel(tg, 'Text', 'Sprayed: -');
            app.TrRouteLabel = uilabel(tg, 'Text', 'Pass-2 route flown: -');
            app.TrPumpLabel = uilabel(tg, 'Text', 'Pump: OFF', 'FontWeight', 'bold');
            app.TrEmitLabel = uilabel(tg, 'Text', 'Spray emitted so far: -');
            uilabel(tg, 'Text', 'Deposition outcome: Experiments mode', 'FontColor', [0.45 0.45 0.45], 'FontSize', 10);

            yp = uipanel(R, 'Title', 'System Status');
            yg = uigridlayout(yp, [6 1]);
            yg.RowHeight = repmat({19}, 1, 6); yg.Padding = [10 2 10 2]; yg.RowSpacing = 1;
            app.PosSrcLabel = uilabel(yg, 'Text', 'Position: SIMULATION GROUND TRUTH');
            uilabel(yg, 'Text', 'GPS: NOT USED');
            app.EstimatorLabel = uilabel(yg, 'Text', 'GPS-denied estimator: NOT INTEGRATED');
            uilabel(yg, 'Text', 'Detector: PARAMETRIC (no image / CNN inference)');
            uilabel(yg, 'Text', 'Mission: precomputed, replayed');
            uilabel(yg, 'Text', 'Spray model: simplified, unvalidated');

            app.createAdvancedTab(tabA);
            try
                app.PipelineView = pipelineBuilderView(tabP, app);   % manual pipeline + paired comparison (separate file)
            catch ME
                uilabel(tabP, 'Position', [30 700 900 24], 'Text', ['Pipeline builder unavailable: ' ME.message]);
            end
            try
                analysisView(tabC);                 % read-only report of saved results (separate file)
            catch ME
                uilabel(tabC, 'Position', [30 700 900 24], 'Text', ['Comparative analysis unavailable: ' ME.message]);
            end
        end
    end
end

function s = onoff(tf)
    if tf, s = 'on'; else, s = 'off'; end
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end

function s = advParamLabel(name)
%ADVPARAMLABEL Readable label (with units) for an advanced-option parameter.
    L = struct('dryMass_kg', 'Dry mass (kg)', 'tankCapacity_L', 'Tank capacity (L)', ...
        'liquidDensity_kgL', 'Liquid density (kg/L)', 'refillTime_s', 'Refill time (s)', ...
        'velTimeConstant_s', 'Velocity response (s)', 'thrustToWeightFull', 'Thrust/weight (full)', ...
        'dragArea_m2', 'Drag area CdA (m^2)', 'airDensity_kgm3', 'Air density (kg/m^3)', ...
        'battery_Wh', 'Battery (Wh)', 'reservePct', 'Reserve (%)', 'rotorDiskArea_m2', 'Rotor disk area (m^2)', ...
        'efficiency', 'Efficiency (0-1)', 'avionics_W', 'Avionics (W)', ...
        'sigma_mps', 'Gust RMS (m/s)', 'periodMin_s', 'Shortest period (s)', 'periodMax_s', 'Longest period (s)', ...
        'nComponents', 'Components', 'seed', 'Random seed', ...
        'temperature_C', 'Air temperature (C)', 'relHumidity_pct', 'Relative humidity (%)', ...
        'dropletVMD_um', 'Droplet size VMD (um)', 'downwashFactor', 'Downwash factor', ...
        'altitude_m', 'Flight altitude (m)', 'cameraHalfFOV_deg', 'Camera half-FOV (deg)', ...
        'canopyHeight_m', 'Canopy height (m)', 'detectRefAltitude_m', 'Detect. ref. altitude (m)', ...
        'detectAltitudeScale_m', 'Detect. falloff (m)', ...
        'randomWalk_m_sqrt_s', 'Random walk (m/sqrt(s))', 'scaleError', 'Odometry scale error', ...
        'fixInterval_s', 'Absolute fix every (s)', 'fixNoise_m', 'Fix noise (m)', ...
        'maxSprayWind_mps', 'Max spray wind (m/s)', 'mode', 'Mode', 'imuAccelNoise_mps2', 'IMU accel noise (m/s^2)', ...
        'imuAccelBias_mps2', 'IMU accel bias (m/s^2)', 'flowVelNoise_mps', 'Optical-flow noise (m/s)', ...
        'lidarRange_m', 'LiDAR range (m)', 'lidarNoise_m', 'LiDAR noise (m)', 'lidarRate_Hz', 'LiDAR rate (Hz)', ...
        'flowDropoutProb', 'Flow dropout prob.', 'geolocateTargets', 'Geolocate targets (0/1)', ...
        'valveDelay_s', 'Valve delay (s)', 'lagCompensation', 'Lag compensation (0/1)', 'kernel', 'Spray kernel', ...
        'windStretch_perMps', 'Kernel stretch per m/s', 'lookahead_m', 'Look-ahead (m)', 'holdGain_per_s', 'Hold gain (1/s)');
    if isfield(L, name), s = L.(name); else, s = name; end
end
