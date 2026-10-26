classdef AgriculturalDroneDashboard < matlab.apps.AppBase
    %AGRICULTURALDRONEDASHBOARD Full live dashboard (Section 23, Panels A-H).
    %
    %   This is a PROGRAMMATIC UI app (built with uifigure/uiaxes/
    %   uibutton etc., the same component framework App Designer's
    %   canvas uses) rather than a binary .mlapp file - see the earlier
    %   explanation in this project's chat history for why. It runs
    %   identically to an App Designer app.
    %
    %   HOW TO RUN: type AgriculturalDroneDashboard in the Command Window.
    %
    %   This brings together every earlier stage: field/plant/path
    %   generation, continuous drone movement, simulated sensors, the
    %   virtual camera, real/demo disease detection, heuristic severity,
    %   the target queue with approach + second-image confirmation,
    %   simulated spraying, and return-to-path - all driven by a MATLAB
    %   timer so the UI stays responsive (PAUSE actually pauses).

    properties (Access = public)
        UIFigure          matlab.ui.Figure

        % Panel A: Field Input
        FieldPanel        matlab.ui.container.Panel
        LengthEdit        matlab.ui.control.NumericEditField
        WidthEdit         matlab.ui.control.NumericEditField
        RowSpacingEdit    matlab.ui.control.NumericEditField
        PlantSpacingEdit  matlab.ui.control.NumericEditField
        AltitudeEdit      matlab.ui.control.NumericEditField
        SpeedEdit         matlab.ui.control.NumericEditField
        SimSpeedEdit      matlab.ui.control.NumericEditField
        GenerateButton    matlab.ui.control.Button
        RowsLabel         matlab.ui.control.Label
        PlantsPerRowLabel matlab.ui.control.Label
        TotalPlantsLabel  matlab.ui.control.Label
        PathLengthLabel   matlab.ui.control.Label

        % Panel B: Mission Control
        MissionPanel      matlab.ui.container.Panel
        StartButton       matlab.ui.control.Button
        PauseButton       matlab.ui.control.Button
        ResumeButton      matlab.ui.control.Button
        StopButton        matlab.ui.control.Button
        ResetButton       matlab.ui.control.Button

        % Panel H: System Status
        SystemPanel       matlab.ui.control.Label
        MLModeLabel       matlab.ui.control.Label
        GPSLabel          matlab.ui.control.Label
        NavLabel          matlab.ui.control.Label
        IMULabel          matlab.ui.control.Label
        FlowLabel         matlab.ui.control.Label
        LidarLabel        matlab.ui.control.Label
        CompassLabel      matlab.ui.control.Label
        PumpLabel         matlab.ui.control.Label

        % Panel C: Live Field Map
        MapPanel          matlab.ui.container.Panel
        MapAxes           matlab.ui.control.UIAxes
        PlantScatter      matlab.graphics.chart.primitive.Scatter
        DroneMarker       matlab.graphics.chart.primitive.Line
        CamCircle         matlab.graphics.chart.primitive.Line
        ApproachLine      matlab.graphics.chart.primitive.Line
        ReturnLine        matlab.graphics.chart.primitive.Line

        % Panel D: Drone Status
        StatusPanel       matlab.ui.container.Panel
        XLabel            matlab.ui.control.Label
        YLabel            matlab.ui.control.Label
        ZLabel            matlab.ui.control.Label
        SpeedLabel        matlab.ui.control.Label
        RowLabel          matlab.ui.control.Label
        ProgressLabel     matlab.ui.control.Label
        DistanceLabel     matlab.ui.control.Label
        TimeLabel         matlab.ui.control.Label
        NavStateLabel     matlab.ui.control.Label

        % Panel E: Camera / Image
        CameraPanel       matlab.ui.container.Panel
        CameraImage       matlab.ui.control.Image
        PlantIDLabel      matlab.ui.control.Label
        PredictionLabel   matlab.ui.control.Label
        ConfidenceLabel   matlab.ui.control.Label
        SeverityLabel     matlab.ui.control.Label
        CoordsLabel       matlab.ui.control.Label

        % Panel F+G: Disease Info + Mission Statistics (+ Severity tab)
        StatsPanel        matlab.ui.container.Panel
        StatsTabGroup     matlab.ui.container.TabGroup
        StatsTab          matlab.ui.container.Tab
        SeverityTab       matlab.ui.container.Tab
        TotalStatLabel    matlab.ui.control.Label
        HealthyStatLabel  matlab.ui.control.Label
        DiseasedStatLabel matlab.ui.control.Label
        SprayedStatLabel  matlab.ui.control.Label
        QueuedStatLabel   matlab.ui.control.Label
        ConfirmedStatLabel matlab.ui.control.Label
        RejectedStatLabel matlab.ui.control.Label
        MissionStatLabel  matlab.ui.control.Label

        SeverityAxes       matlab.ui.control.UIAxes
        SeverityBarHandle  matlab.graphics.chart.primitive.Bar
        SeverityDisclaimerLabel matlab.ui.control.Label
        MildCountLabel     matlab.ui.control.Label
        ModerateCountLabel matlab.ui.control.Label
        SevereCountLabel   matlab.ui.control.Label

        % Weather Control (new - does not replace any existing panel)
        WeatherPanel       matlab.ui.container.Panel
        WindButton         matlab.ui.control.Button
        RainButton         matlab.ui.control.Button
        StormButton        matlab.ui.control.Button
        WeatherStatusLabel matlab.ui.control.Label
        FieldBoundaryHandle matlab.graphics.primitive.Rectangle
        WindArrowHandle    matlab.graphics.chart.primitive.Quiver
        RainOverlayHandle  matlab.graphics.primitive.Patch

        MissionTimer      timer
    end

    properties (Access = public)
        cfg
        fieldInfo
        plants
        path
        drone
        plantColors

        missionState   % 'IDLE' | 'RUNNING' | 'PAUSED' | 'STOPPED'
        phase          % 'SWEEP' | 'TARGETING' | 'DONE'
        subState        % targeting sub-state machine
        targetQueue
        targetCursor
        currentPlantIdx
        currentTargetXY
        nearestPoint
        resumeIdx
        sprayTicksRemaining
        simSpeed

        healthyCount
        diseasedCount
        confirmedCount
        rejectedCount
        sprayedCount

        % Weather state
        windEnabled
        rainEnabled
        stormEnabled
        weatherOffset   % [dx dy] current weather displacement from the true path
    end

    methods (Access = private)

        function GenerateButtonPushed(app, ~)
            app.cfg = config();
            app.cfg.fieldLength    = app.LengthEdit.Value;
            app.cfg.fieldWidth     = app.WidthEdit.Value;
            app.cfg.rowSpacing     = app.RowSpacingEdit.Value;
            app.cfg.plantSpacing   = app.PlantSpacingEdit.Value;
            app.cfg.flightAltitude = app.AltitudeEdit.Value;
            app.cfg.droneSpeed     = app.SpeedEdit.Value;
            app.simSpeed           = max(1, round(app.SimSpeedEdit.Value));

            try
                app.fieldInfo = generateField(app.cfg);
                app.plants    = generatePlants(app.cfg, app.fieldInfo);
                app.path      = generateZigZagPath(app.cfg, app.fieldInfo);

                app.RowsLabel.Text         = sprintf('Rows: %d', app.fieldInfo.numRows);
                app.PlantsPerRowLabel.Text = sprintf('Plants per row: %d', app.fieldInfo.plantsPerRow);
                app.TotalPlantsLabel.Text  = sprintf('Total plants: %d', app.fieldInfo.totalPlants);
                app.PathLengthLabel.Text   = sprintf('Est. path length: %.1f m', app.fieldInfo.estimatedPathLength);

                cla(app.MapAxes);
                hold(app.MapAxes, 'on');
                axis(app.MapAxes, 'equal');
                xlim(app.MapAxes, [-1, app.cfg.fieldLength+1]);
                ylim(app.MapAxes, [-1, app.cfg.fieldWidth+1]);
                grid(app.MapAxes, 'on');

                % rain overlay patch - drawn FIRST so it sits behind
                % everything else; hidden unless rain is toggled on
                app.RainOverlayHandle = patch(app.MapAxes, ...
                    [0 app.cfg.fieldLength app.cfg.fieldLength 0], ...
                    [0 0 app.cfg.fieldWidth app.cfg.fieldWidth], ...
                    [0.55 0.75 1], 'FaceAlpha', 0.18, 'EdgeColor', 'none', ...
                    'Visible', 'off');

                app.FieldBoundaryHandle = rectangle(app.MapAxes, ...
                    'Position', [0 0 app.cfg.fieldLength app.cfg.fieldWidth], ...
                    'EdgeColor','k','LineWidth',1.5);
                plot(app.MapAxes, app.path(:,1), app.path(:,2), 'b--', 'LineWidth', 1.0);

                app.plantColors = repmat([0.6 0.6 0.6], height(app.plants), 1);
                app.PlantScatter = scatter(app.MapAxes, app.plants.X, app.plants.Y, 25, ...
                    app.plantColors, 'filled');

                app.drone = initDrone(app.cfg, app.path);
                app.drone.state = "ZIGZAG_SEARCH";

                app.DroneMarker = plot(app.MapAxes, app.drone.pos(1), app.drone.pos(2), ...
                    'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');

                theta = linspace(0, 2*pi, 40);
                app.CamCircle = plot(app.MapAxes, ...
                    app.drone.pos(1)+app.cfg.cameraFovRadius*cos(theta), ...
                    app.drone.pos(2)+app.cfg.cameraFovRadius*sin(theta), 'c-', 'LineWidth', 1.2);

                app.ApproachLine = plot(app.MapAxes, nan, nan, 'y-', 'LineWidth', 1.5);
                app.ReturnLine   = plot(app.MapAxes, nan, nan, 'm-', 'LineWidth', 1.5);

                % wind direction arrow (fixed NE direction for this demo),
                % positioned just above the field, hidden unless wind is on
                arrowBaseX = app.cfg.fieldLength * 0.1;
                arrowBaseY = app.cfg.fieldWidth + 0.6;
                app.WindArrowHandle = quiver(app.MapAxes, arrowBaseX, arrowBaseY, 1.2, 1.2, ...
                    0, 'Color', [0.1 0.3 0.9], 'LineWidth', 2.2, 'MaxHeadSize', 2, 'Visible', 'off');

                title(app.MapAxes, 'Field generated - press START', 'Interpreter', 'none');

                generateDemoImages(app.cfg, app.plants); % skipped if real images already assigned

                app.resetMissionState();
                app.updateStatusPanel();
                app.updateStatsPanel();
                app.updateSystemPanel();

                app.PlantIDLabel.Text    = 'Plant: -';
                app.PredictionLabel.Text = 'Prediction: -';
                app.ConfidenceLabel.Text = 'Confidence: -';
                app.SeverityLabel.Text   = 'Severity: -';
                app.CoordsLabel.Text     = 'Coordinates: -';
                app.CameraImage.ImageSource = zeros(32,32,3,'uint8');

                app.updateWeatherVisuals(); % re-sync wind/rain/storm visuals to current toggle state
            catch ME
                uialert(app.UIFigure, ME.message, 'Field Generation Error');
            end
        end

        function resetMissionState(app)
            app.missionState  = 'IDLE';
            app.phase         = 'SWEEP';
            app.subState      = 'START';
            app.targetQueue   = table('Size',[0 7], ...
                'VariableTypes', {'string','double','double','double','double','double','string'}, ...
                'VariableNames', {'PlantID','X','Y','FirstConfidence','FirstSeverity','DetectionTime','Status'});
            app.targetCursor  = 1;
            app.currentPlantIdx = [];
            app.healthyCount  = 0;
            app.diseasedCount = 0;
            app.confirmedCount = 0;
            app.rejectedCount  = 0;
            app.sprayedCount   = 0;
            app.weatherOffset  = [0 0];
            app.PumpLabel.Text = 'Pump: OFF';
            set(app.ApproachLine, 'XData', nan, 'YData', nan);
            set(app.ReturnLine,   'XData', nan, 'YData', nan);
        end

        function WindButtonPushed(app, ~)
            app.windEnabled = ~app.windEnabled;
            app.updateWeatherVisuals();
        end

        function RainButtonPushed(app, ~)
            app.rainEnabled = ~app.rainEnabled;
            app.updateWeatherVisuals();
        end

        function StormButtonPushed(app, ~)
            app.stormEnabled = ~app.stormEnabled;
            app.updateWeatherVisuals();
        end

        function updateWeatherVisuals(app)
            % Button appearance
            if app.windEnabled
                app.WindButton.Text = 'WIND: ON';
                app.WindButton.BackgroundColor = [0.25 0.55 0.95];
                app.WindButton.FontColor = [1 1 1];
            else
                app.WindButton.Text = 'WIND: OFF';
                app.WindButton.BackgroundColor = [0.94 0.94 0.94];
                app.WindButton.FontColor = [0 0 0];
            end

            if app.rainEnabled
                app.RainButton.Text = 'RAIN: ON';
                app.RainButton.BackgroundColor = [0.25 0.55 0.95];
                app.RainButton.FontColor = [1 1 1];
            else
                app.RainButton.Text = 'RAIN: OFF';
                app.RainButton.BackgroundColor = [0.94 0.94 0.94];
                app.RainButton.FontColor = [0 0 0];
            end

            if app.stormEnabled
                app.StormButton.Text = 'STORM: ON';
                app.StormButton.BackgroundColor = [0.85 0.1 0.1];
                app.StormButton.FontColor = [1 1 1];
            else
                app.StormButton.Text = 'STORM: OFF';
                app.StormButton.BackgroundColor = [0.94 0.94 0.94];
                app.StormButton.FontColor = [0 0 0];
            end

            % Map visuals (only if the field/map has been generated)
            if ~isempty(app.WindArrowHandle) && isvalid(app.WindArrowHandle)
                app.WindArrowHandle.Visible = app.boolToOnOff(app.windEnabled);
            end
            if ~isempty(app.RainOverlayHandle) && isvalid(app.RainOverlayHandle)
                app.RainOverlayHandle.Visible = app.boolToOnOff(app.rainEnabled);
            end
            if ~isempty(app.FieldBoundaryHandle) && isvalid(app.FieldBoundaryHandle)
                if app.stormEnabled
                    app.FieldBoundaryHandle.EdgeColor = [0.85 0.1 0.1];
                    app.FieldBoundaryHandle.LineWidth = 3;
                else
                    app.FieldBoundaryHandle.EdgeColor = 'k';
                    app.FieldBoundaryHandle.LineWidth = 1.5;
                end
            end

            % Combined status text
            conditions = {};
            if app.windEnabled,  conditions{end+1} = 'Wind';  end %#ok<AGROW>
            if app.rainEnabled,  conditions{end+1} = 'Rain';  end %#ok<AGROW>
            if app.stormEnabled, conditions{end+1} = 'Storm'; end %#ok<AGROW>

            if isempty(conditions)
                app.WeatherStatusLabel.Text = 'Conditions: Clear';
                app.WeatherStatusLabel.FontColor = [0 0.5 0];
            else
                app.WeatherStatusLabel.Text = ['Conditions: ' strjoin(conditions, ' + ')];
                app.WeatherStatusLabel.FontColor = [0.75 0.1 0.1];
            end
        end

        function s = boolToOnOff(~, tf)
            if tf
                s = 'on';
            else
                s = 'off';
            end
        end

        function factor = getWeatherSpeedFactor(app)
            % RAIN: reduced visibility/caution -> slower flight.
            % STORM: much more cautious/unstable -> even slower.
            % These stack multiplicatively if both are active.
            factor = 1;
            if app.rainEnabled
                factor = factor * 0.55;
            end
            if app.stormEnabled
                factor = factor * 0.45;
            end
        end

        function applyWeatherDrift(app, targetXY)
            % WIND: steady directional push. STORM: random gusts on top.
            %
            % The weather displacement is kept as its OWN state
            % (app.weatherOffset), measured from the true, undisturbed
            % flight position. Each step the old offset is stripped off to
            % recover the true position, then a new offset is built:
            %     offset = (1 - correctionGain)*offset + disturbance
            % i.e. simulated IMU / optical-flow station-keeping pulls the
            % drone back toward the TRUE path every step, so error cannot
            % accumulate into a random walk. The offset is also capped
            % below the camera radius so plants keep being detected.
            %
            % targetXY (optional): during approach / return the offset is
            % faded out near the target so the drone can still reach it.
            if isempty(app.drone)
                return;
            end
            if isempty(app.weatherOffset)
                app.weatherOffset = [0 0];
            end

            oldOffset = app.weatherOffset;
            truePos   = app.drone.pos(1:2) - oldOffset; % undisturbed position

            disturbance = [0 0];
            if app.windEnabled
                windAngle = pi/4; % fixed NE direction, kept constant for a reproducible demo
                windStrength = 0.45; % steady crosswind -> leans ~0.3 m off the row
                windTurb     = 0.30; % small turbulence on top of the steady push
                disturbance = disturbance + app.cfg.dt * ( ...
                    windStrength * [cos(windAngle), sin(windAngle)] + windTurb * (2*rand(1,2) - 1));
            end
            if app.rainEnabled
                rainStrength = 1.0; % rain: droplet buffeting -> visible jitter
                disturbance = disturbance + rainStrength * app.cfg.dt * (2*rand(1,2) - 1);
            end
            if app.stormEnabled
                gustStrength = 1.3; % m/s-equivalent, random direction each step
                disturbance = disturbance + gustStrength * app.cfg.dt * (2*rand(1,2) - 1);
            end

            correctionGain = 0.15;  % fraction of offset removed per step (station-keeping)
            maxOffset      = 0.45;  % m, must stay below cfg.cameraFovRadius (0.6)

            newOffset = (1 - correctionGain) * oldOffset + disturbance;

            n = norm(newOffset);
            if n > maxOffset
                newOffset = newOffset * (maxOffset / n);
            end

            if nargin > 1 && ~isempty(targetXY)
                d = norm(targetXY(1:2) - truePos);
                newOffset = newOffset * min(1, d / 1.0); % fade out within 1 m of target
            end

            newPos = truePos + newOffset;
            margin = 2;
            newPos(1) = min(max(newPos(1), -margin), app.cfg.fieldLength + margin);
            newPos(2) = min(max(newPos(2), -margin), app.cfg.fieldWidth + margin);
            newOffset = newPos - truePos;

            app.drone.pos(1:2) = newPos;
            app.weatherOffset  = newOffset;
            app.drone.distanceTravelled = app.drone.distanceTravelled + norm(newOffset - oldOffset);
        end

        function StartButtonPushed(app, ~)
            if isempty(app.plants)
                uialert(app.UIFigure, 'Generate the field first.', 'No Field');
                return;
            end

            if strcmp(app.missionState, 'PAUSED')
                app.missionState = 'RUNNING';
                start(app.MissionTimer);
                return;
            end

            app.drone = initDrone(app.cfg, app.path);
            app.drone.state = "ZIGZAG_SEARCH";
            app.plants.State(:)       = "NOT_SEEN";
            app.plants.Disease(:)     = "UNKNOWN";
            app.plants.Confidence(:)  = 0;
            app.plants.Severity(:)    = 0;
            app.plants.SprayStatus(:) = "NOT_SPRAYED";
            app.plantColors = repmat([0.6 0.6 0.6], height(app.plants), 1);
            set(app.PlantScatter, 'CData', app.plantColors);
            set(app.DroneMarker, 'XData', app.drone.pos(1), 'YData', app.drone.pos(2));

            app.resetMissionState();
            app.missionState = 'RUNNING';
            if strcmp(app.MissionTimer.Running, 'off')
                start(app.MissionTimer);
            end
        end

        function PauseButtonPushed(app, ~)
            if strcmp(app.missionState, 'RUNNING')
                stop(app.MissionTimer);
                app.missionState = 'PAUSED';
            end
        end

        function ResumeButtonPushed(app, ~)
            if strcmp(app.missionState, 'PAUSED')
                start(app.MissionTimer);
                app.missionState = 'RUNNING';
            end
        end

        function StopButtonPushed(app, ~)
            if strcmp(app.MissionTimer.Running, 'on')
                stop(app.MissionTimer);
            end
            app.missionState = 'STOPPED';
            app.updateStatsPanel();
        end

        function ResetButtonPushed(app, ~)
            if strcmp(app.MissionTimer.Running, 'on')
                stop(app.MissionTimer);
            end
            if ~isempty(app.plants)
                app.drone = initDrone(app.cfg, app.path);
                app.plants.State(:)       = "NOT_SEEN";
                app.plants.Disease(:)     = "UNKNOWN";
                app.plants.Confidence(:)  = 0;
                app.plants.Severity(:)    = 0;
                app.plants.SprayStatus(:) = "NOT_SPRAYED";
                app.plantColors = repmat([0.6 0.6 0.6], height(app.plants), 1);
                set(app.PlantScatter, 'CData', app.plantColors);
                set(app.DroneMarker, 'XData', app.drone.pos(1), 'YData', app.drone.pos(2));
                title(app.MapAxes, 'Reset - press START', 'Interpreter', 'none');
            end
            app.resetMissionState();
            app.updateStatusPanel();
            app.updateStatsPanel();
        end

        function onTimerTick(app)
            if isempty(app.drone)
                return;
            end

            for i = 1:app.simSpeed
                if strcmp(app.phase, 'DONE')
                    break;
                end
                app.stepOnce();
            end

            theta = linspace(0, 2*pi, 40);
            set(app.DroneMarker, 'XData', app.drone.pos(1), 'YData', app.drone.pos(2));
            set(app.CamCircle, ...
                'XData', app.drone.pos(1)+app.cfg.cameraFovRadius*cos(theta), ...
                'YData', app.drone.pos(2)+app.cfg.cameraFovRadius*sin(theta));

            titleStr = sprintf('%s | Row %d/%d | t=%.1fs | state=%s', ...
                app.phase, app.drone.currentRow, app.fieldInfo.numRows, ...
                app.drone.missionTime, app.drone.state);
            title(app.MapAxes, titleStr, 'Interpreter', 'none');

            app.updateStatusPanel();
            app.updateStatsPanel();

            if strcmp(app.phase, 'DONE')
                stop(app.MissionTimer);
                app.missionState = 'STOPPED';
                app.drone.state = "MISSION_COMPLETE";
                title(app.MapAxes, sprintf('MISSION COMPLETE | t=%.1fs', app.drone.missionTime), ...
                    'Interpreter', 'none');
                app.updateStatusPanel();
            end
        end

        function stepOnce(app)
            if ~isempty(app.drone)
                app.drone.speed = app.cfg.droneSpeed * app.getWeatherSpeedFactor();
            end
            switch app.phase
                case 'SWEEP'
                    app.stepSweep();
                case 'TARGETING'
                    app.stepTargeting();
            end
        end

        function stepSweep(app)
            [app.drone, ~, missionDone] = simulateDrone(app.drone, app.path, app.cfg);
            app.applyWeatherDrift();

            camera = simulateCamera(app.drone, app.cfg);
            visibleIdx = getVisiblePlants(app.plants, camera);

            if ~isempty(visibleIdx)
                for k = 1:numel(visibleIdx)
                    idx = visibleIdx(k);
                    img = loadPlantImage(app.plants.ImagePath(idx));
                    result = detectDisease(img, app.cfg);
                    result = calculateSeverity(result);

                    app.plants.State(idx)      = result.label;
                    app.plants.Disease(idx)    = result.label;
                    app.plants.Confidence(idx) = result.confidence;
                    app.plants.Severity(idx)   = result.severity;

                    if result.label == "DISEASED"
                        app.diseasedCount = app.diseasedCount + 1;
                        app.plantColors(idx,:) = [0.85 0.1 0.1];
                        newRow = {app.plants.ID(idx), app.plants.X(idx), app.plants.Y(idx), ...
                                  result.confidence, result.severity, app.drone.missionTime, "PENDING"};
                        app.targetQueue = [app.targetQueue; newRow]; %#ok<AGROW>
                    else
                        app.healthyCount = app.healthyCount + 1;
                        app.plantColors(idx,:) = [0.2 0.8 0.2];
                    end
                end
                set(app.PlantScatter, 'CData', app.plantColors);

                lastIdx = visibleIdx(end);
                app.updateCameraPanel(lastIdx);
            end

            if missionDone
                if height(app.targetQueue) > 0
                    app.phase = 'TARGETING';
                    app.targetCursor = 1;
                    app.subState = 'START';
                else
                    app.phase = 'DONE';
                end
            end
        end

        function stepTargeting(app)
            if app.targetCursor > height(app.targetQueue)
                app.phase = 'DONE';
                return;
            end

            switch app.subState
                case 'START'
                    targetID = app.targetQueue.PlantID(app.targetCursor);
                    app.currentPlantIdx = find(app.plants.ID == targetID, 1);
                    app.currentTargetXY = [app.targetQueue.X(app.targetCursor), app.targetQueue.Y(app.targetCursor)];
                    app.drone.state = "TARGET_APPROACH";
                    app.subState = 'APPROACH';

                case 'APPROACH'
                    [app.drone, reached] = navigateToTarget(app.drone, app.currentTargetXY, app.cfg);
                    app.applyWeatherDrift(app.currentTargetXY);
                    set(app.ApproachLine, 'XData', [app.drone.pos(1), app.currentTargetXY(1)], ...
                        'YData', [app.drone.pos(2), app.currentTargetXY(2)]);
                    if reached
                        set(app.ApproachLine, 'XData', nan, 'YData', nan);
                        app.subState = 'CONFIRM';
                    end

                case 'CONFIRM'
                    app.drone.state = "CONFIRMATION";
                    [confirmed, result2] = confirmTarget(app.plants.ImagePath(app.currentPlantIdx), app.cfg);
                    app.updateCameraPanel(app.currentPlantIdx);

                    if confirmed
                        app.targetQueue.Status(app.targetCursor) = "CONFIRMED";
                        app.plants.Confidence(app.currentPlantIdx) = result2.confidence;
                        app.plants.Severity(app.currentPlantIdx)   = result2.severity;
                        app.confirmedCount = app.confirmedCount + 1;
                        app.drone.state = "SPRAYING";
                        app.sprayTicksRemaining = max(1, round(2 / app.cfg.dt / max(1,app.simSpeed)));
                        app.PumpLabel.Text = 'Pump: ON';
                        app.subState = 'SPRAY';
                    else
                        app.targetQueue.Status(app.targetCursor) = "REJECTED";
                        app.plants.State(app.currentPlantIdx)   = "HEALTHY";
                        app.plants.Disease(app.currentPlantIdx) = "HEALTHY";
                        app.plantColors(app.currentPlantIdx,:) = [0.2 0.8 0.2];
                        set(app.PlantScatter, 'CData', app.plantColors);
                        app.rejectedCount = app.rejectedCount + 1;
                        app.subState = 'NEXT';
                    end

                case 'SPRAY'
                    app.sprayTicksRemaining = app.sprayTicksRemaining - 1;
                    if app.sprayTicksRemaining <= 0
                        app.plants = sprayTarget(app.plants, app.currentPlantIdx, app.cfg);
                        app.PumpLabel.Text = 'Pump: OFF';
                        app.sprayedCount = app.sprayedCount + 1;
                        app.plantColors(app.currentPlantIdx,:) = [0 0 0];
                        set(app.PlantScatter, 'CData', app.plantColors);

                        app.drone.state = "RETURN_TO_PATH";
                        [app.nearestPoint, app.resumeIdx] = findNearestPathPoint(app.drone.pos, app.path);
                        app.subState = 'RETURN';
                    end

                case 'RETURN'
                    [app.drone, reached] = returnToPath(app.drone, app.nearestPoint, app.cfg);
                    app.applyWeatherDrift(app.nearestPoint(1:2));
                    set(app.ReturnLine, 'XData', [app.drone.pos(1), app.nearestPoint(1)], ...
                        'YData', [app.drone.pos(2), app.nearestPoint(2)]);
                    if reached
                        set(app.ReturnLine, 'XData', nan, 'YData', nan);
                        app.drone.pathIndex = app.resumeIdx - 1;
                        app.drone.state = "ZIGZAG_SEARCH";
                        app.subState = 'NEXT';
                    end

                case 'NEXT'
                    app.targetCursor = app.targetCursor + 1;
                    app.subState = 'START';
            end
        end

        function updateCameraPanel(app, plantIdx)
            img = loadPlantImage(app.plants.ImagePath(plantIdx));
            app.CameraImage.ImageSource = img;
            app.PlantIDLabel.Text    = sprintf('Plant: %s', app.plants.ID(plantIdx));
            app.PredictionLabel.Text = sprintf('Prediction: %s', app.plants.Disease(plantIdx));
            app.ConfidenceLabel.Text = sprintf('Confidence: %.1f%%', app.plants.Confidence(plantIdx));
            app.SeverityLabel.Text   = sprintf('Severity: %.0f (heuristic)', app.plants.Severity(plantIdx));
            app.CoordsLabel.Text     = sprintf('Coordinates: (%.1f, %.1f)', ...
                app.plants.X(plantIdx), app.plants.Y(plantIdx));
        end

        function updateStatusPanel(app)
            if isempty(app.drone)
                return;
            end
            app.XLabel.Text     = sprintf('X: %.2f m', app.drone.pos(1));
            app.YLabel.Text     = sprintf('Y: %.2f m', app.drone.pos(2));
            app.ZLabel.Text     = sprintf('Z: %.2f m', app.drone.pos(3));
            app.SpeedLabel.Text = sprintf('Speed: %.1f m/s', app.drone.speed);
            app.RowLabel.Text   = sprintf('Current row: %d / %d', app.drone.currentRow, app.fieldInfo.numRows);

            numSeen = sum(app.plants.State ~= "NOT_SEEN");
            progressPct = 100 * numSeen / height(app.plants);
            app.ProgressLabel.Text = sprintf('Mission progress: %.0f%%', progressPct);
            app.DistanceLabel.Text = sprintf('Distance travelled: %.1f m', app.drone.distanceTravelled);
            app.TimeLabel.Text     = sprintf('Mission time: %.1f s', app.drone.missionTime);
            app.NavStateLabel.Text = sprintf('State: %s', app.drone.state);
        end

        function updateStatsPanel(app)
            if isempty(app.plants)
                return;
            end
            app.TotalStatLabel.Text     = sprintf('Total plants: %d', height(app.plants));
            app.HealthyStatLabel.Text   = sprintf('Healthy: %d', app.healthyCount);
            app.DiseasedStatLabel.Text  = sprintf('Diseased: %d', app.diseasedCount);
            app.SprayedStatLabel.Text   = sprintf('Sprayed: %d', app.sprayedCount);
            app.QueuedStatLabel.Text    = sprintf('Targets queued: %d', height(app.targetQueue));
            app.ConfirmedStatLabel.Text = sprintf('Confirmed: %d', app.confirmedCount);
            app.RejectedStatLabel.Text  = sprintf('Rejected: %d', app.rejectedCount);
            app.MissionStatLabel.Text   = sprintf('Mission: %s', app.missionState);

            app.updateSeverityPanel();
        end

        function updateSeverityPanel(app)
            % Severity tab (Section 14) - HEURISTIC ONLY, see
            % calculateSeverity.m for the full explanation of why this
            % is not a validated measurement.
            if isempty(app.plants)
                return;
            end

            diseasedMask = app.plants.Disease == "DISEASED";
            sev = app.plants.Severity(diseasedMask);

            mildN     = sum(sev < 30);
            moderateN = sum(sev >= 30 & sev < 70);
            severeN   = sum(sev >= 70);
            healthyN  = sum(app.plants.Disease == "HEALTHY");

            set(app.SeverityBarHandle, 'YData', [healthyN, mildN, moderateN, severeN]);

            app.MildCountLabel.Text     = sprintf('Mild: %d', mildN);
            app.ModerateCountLabel.Text = sprintf('Moderate: %d', moderateN);
            app.SevereCountLabel.Text   = sprintf('Severe: %d', severeN);
        end

        function updateSystemPanel(app)
            if app.cfg.USE_REAL_MODEL
                app.MLModeLabel.Text = 'ML Mode: REAL ML';
            else
                app.MLModeLabel.Text = 'ML Mode: DEMO';
            end
            app.GPSLabel.Text     = 'GPS: DISABLED';
            app.NavLabel.Text     = 'Navigation: GPS-DENIED';
            app.IMULabel.Text     = 'IMU: SIMULATED';
            app.FlowLabel.Text    = 'Optical Flow: SIMULATED';
            app.LidarLabel.Text   = 'LiDAR: SIMULATED';
            app.CompassLabel.Text = 'Compass: SIMULATED';
        end
    end

    methods (Access = public)

        function app = AgriculturalDroneDashboard
            createComponents(app)
            app.missionState = 'IDLE';
            app.phase = 'SWEEP';
            app.simSpeed = 3;
            app.windEnabled = false;
            app.rainEnabled = false;
            app.stormEnabled = false;
            app.MissionTimer = timer('ExecutionMode', 'fixedRate', ...
                'Period', 0.05, 'BusyMode', 'drop', ...
                'TimerFcn', @(~,~) app.onTimerTick());
            app.updateWeatherVisuals(); % set initial button appearance (all OFF)
            % NOTE: updateSystemPanel() is intentionally NOT called here -
            % it depends on app.cfg, which does not exist until
            % GenerateButtonPushed runs. The System Status panel starts
            % with the static "-" placeholders set in createComponents,
            % and gets its real values the first time GENERATE FIELD is
            % pressed.
        end

        function delete(app)
            if ~isempty(app.MissionTimer) && isvalid(app.MissionTimer)
                if strcmp(app.MissionTimer.Running, 'on')
                    stop(app.MissionTimer);
                end
                delete(app.MissionTimer);
            end
            delete(app.UIFigure)
        end
    end

    methods (Access = private)

        function createComponents(app)
            app.UIFigure = uifigure('Name', 'Agricultural Drone Dashboard', ...
                'Position', [40 10 1400 740]);

            % ===== Panel A: Field Input =====
            app.FieldPanel = uipanel(app.UIFigure, 'Title', 'Field Input Panel', ...
                'Position', [20 300 380 340]);

            uilabel(app.FieldPanel, 'Text', 'Field Length (m):', 'Position', [10 290 140 22]);
            app.LengthEdit = uieditfield(app.FieldPanel, 'numeric', 'Position', [160 290 100 22], 'Value', 20);

            uilabel(app.FieldPanel, 'Text', 'Field Width (m):', 'Position', [10 258 140 22]);
            app.WidthEdit = uieditfield(app.FieldPanel, 'numeric', 'Position', [160 258 100 22], 'Value', 10);

            uilabel(app.FieldPanel, 'Text', 'Row Spacing (m):', 'Position', [10 226 140 22]);
            app.RowSpacingEdit = uieditfield(app.FieldPanel, 'numeric', 'Position', [160 226 100 22], 'Value', 2);

            uilabel(app.FieldPanel, 'Text', 'Plant Spacing (m):', 'Position', [10 194 140 22]);
            app.PlantSpacingEdit = uieditfield(app.FieldPanel, 'numeric', 'Position', [160 194 100 22], 'Value', 0.5);

            uilabel(app.FieldPanel, 'Text', 'Flight Altitude (m):', 'Position', [10 162 140 22]);
            app.AltitudeEdit = uieditfield(app.FieldPanel, 'numeric', 'Position', [160 162 100 22], 'Value', 2);

            uilabel(app.FieldPanel, 'Text', 'Drone Speed (m/s):', 'Position', [10 130 140 22]);
            app.SpeedEdit = uieditfield(app.FieldPanel, 'numeric', 'Position', [160 130 100 22], 'Value', 1.5);

            uilabel(app.FieldPanel, 'Text', 'Sim Speed (x):', 'Position', [10 98 140 22]);
            app.SimSpeedEdit = uieditfield(app.FieldPanel, 'numeric', 'Position', [160 98 100 22], 'Value', 3);

            app.GenerateButton = uibutton(app.FieldPanel, 'push', ...
                'Text', 'GENERATE FIELD', 'Position', [10 58 250 30], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(btn,event) GenerateButtonPushed(app, event));

            app.RowsLabel         = uilabel(app.FieldPanel, 'Text', 'Rows: -',            'Position', [10 32 350 20]);
            app.PlantsPerRowLabel = uilabel(app.FieldPanel, 'Text', 'Plants per row: -',   'Position', [10 14 350 20]);
            app.TotalPlantsLabel  = uilabel(app.FieldPanel, 'Text', 'Total plants: -',     'Position', [200 32 170 20]);
            app.PathLengthLabel   = uilabel(app.FieldPanel, 'Text', 'Est. path length: -', 'Position', [200 14 170 20]);

            % ===== Weather Control (new panel, uses the previously-blank
            % space above the Field Input panel - nothing existing moved) =====
            app.WeatherPanel = uipanel(app.UIFigure, 'Title', 'Weather Control', ...
                'Position', [20 650 380 70]);

            app.WindButton = uibutton(app.WeatherPanel, 'push', 'Text', 'WIND: OFF', ...
                'Position', [10 25 110 30], ...
                'ButtonPushedFcn', @(btn,event) WindButtonPushed(app, event));
            app.RainButton = uibutton(app.WeatherPanel, 'push', 'Text', 'RAIN: OFF', ...
                'Position', [130 25 110 30], ...
                'ButtonPushedFcn', @(btn,event) RainButtonPushed(app, event));
            app.StormButton = uibutton(app.WeatherPanel, 'push', 'Text', 'STORM: OFF', ...
                'Position', [250 25 120 30], ...
                'ButtonPushedFcn', @(btn,event) StormButtonPushed(app, event));

            app.WeatherStatusLabel = uilabel(app.WeatherPanel, 'Text', 'Conditions: Clear', ...
                'Position', [10 3 350 20], 'FontColor', [0 0.5 0], 'FontWeight', 'bold');

            % ===== Panel B: Mission Control =====
            app.MissionPanel = uipanel(app.UIFigure, 'Title', 'Mission Control', ...
                'Position', [20 195 380 90]);

            app.StartButton = uibutton(app.MissionPanel, 'push', 'Text', 'START', ...
                'Position', [10 25 68 30], 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(btn,event) StartButtonPushed(app, event));
            app.PauseButton = uibutton(app.MissionPanel, 'push', 'Text', 'PAUSE', ...
                'Position', [85 25 68 30], ...
                'ButtonPushedFcn', @(btn,event) PauseButtonPushed(app, event));
            app.ResumeButton = uibutton(app.MissionPanel, 'push', 'Text', 'RESUME', ...
                'Position', [160 25 68 30], ...
                'ButtonPushedFcn', @(btn,event) ResumeButtonPushed(app, event));
            app.StopButton = uibutton(app.MissionPanel, 'push', 'Text', 'STOP', ...
                'Position', [235 25 68 30], ...
                'ButtonPushedFcn', @(btn,event) StopButtonPushed(app, event));
            app.ResetButton = uibutton(app.MissionPanel, 'push', 'Text', 'RESET', ...
                'Position', [310 25 60 30], ...
                'ButtonPushedFcn', @(btn,event) ResetButtonPushed(app, event));

            % ===== Panel H: System Status =====
            sysPanel = uipanel(app.UIFigure, 'Title', 'System Status', ...
                'Position', [20 20 380 160]);

            app.MLModeLabel  = uilabel(sysPanel, 'Text', 'ML Mode: -',     'Position', [10 110 170 20]);
            app.GPSLabel     = uilabel(sysPanel, 'Text', 'GPS: -',         'Position', [195 110 170 20]);
            app.NavLabel     = uilabel(sysPanel, 'Text', 'Navigation: -',  'Position', [10 80  170 20]);
            app.IMULabel     = uilabel(sysPanel, 'Text', 'IMU: -',         'Position', [195 80  170 20]);
            app.FlowLabel    = uilabel(sysPanel, 'Text', 'Optical Flow: -','Position', [10 50  170 20]);
            app.LidarLabel   = uilabel(sysPanel, 'Text', 'LiDAR: -',       'Position', [195 50  170 20]);
            app.CompassLabel = uilabel(sysPanel, 'Text', 'Compass: -',     'Position', [10 20  170 20]);
            app.PumpLabel    = uilabel(sysPanel, 'Text', 'Pump: OFF', ...
                'Position', [195 20 170 20], 'FontWeight', 'bold');

            % ===== Panel C: Live Field Map =====
            app.MapPanel = uipanel(app.UIFigure, 'Title', 'Live Field Map', ...
                'Position', [420 20 560 680]);
            app.MapAxes = uiaxes(app.MapPanel, 'Position', [10 10 540 645]);
            xlabel(app.MapAxes, 'X (m)');
            ylabel(app.MapAxes, 'Y (m)');
            title(app.MapAxes, 'Generate a field to begin', 'Interpreter', 'none');

            % ===== Panel D: Drone Status =====
            app.StatusPanel = uipanel(app.UIFigure, 'Title', 'Drone Status', ...
                'Position', [1000 520 380 180]);

            app.XLabel        = uilabel(app.StatusPanel, 'Text', 'X: -',                  'Position', [10 140 350 20]);
            app.YLabel        = uilabel(app.StatusPanel, 'Text', 'Y: -',                  'Position', [10 121 350 20]);
            app.ZLabel        = uilabel(app.StatusPanel, 'Text', 'Z: -',                  'Position', [10 102 350 20]);
            app.SpeedLabel    = uilabel(app.StatusPanel, 'Text', 'Speed: -',              'Position', [10 83  350 20]);
            app.RowLabel      = uilabel(app.StatusPanel, 'Text', 'Current row: -',        'Position', [10 64  350 20]);
            app.ProgressLabel = uilabel(app.StatusPanel, 'Text', 'Mission progress: -',   'Position', [10 45  350 20]);
            app.DistanceLabel = uilabel(app.StatusPanel, 'Text', 'Distance travelled: -', 'Position', [10 26  350 20]);
            app.TimeLabel     = uilabel(app.StatusPanel, 'Text', 'Mission time: -', ...
                'Position', [10 7 170 20]);
            app.NavStateLabel = uilabel(app.StatusPanel, 'Text', 'State: -', ...
                'Position', [195 7 170 20], 'FontWeight', 'bold');

            % ===== Panel E: Camera / Image =====
            app.CameraPanel = uipanel(app.UIFigure, 'Title', 'Camera / Image Panel', ...
                'Position', [1000 295 380 215]);

            app.CameraImage = uiimage(app.CameraPanel, 'Position', [110 60 160 100], ...
                'ImageSource', zeros(32,32,3,'uint8'));

            app.PlantIDLabel    = uilabel(app.CameraPanel, 'Text', 'Plant: -',       'Position', [10 40 350 20]);
            app.PredictionLabel = uilabel(app.CameraPanel, 'Text', 'Prediction: -',  'Position', [10 20 170 20]);
            app.ConfidenceLabel = uilabel(app.CameraPanel, 'Text', 'Confidence: -',  'Position', [195 20 170 20]);
            app.SeverityLabel   = uilabel(app.CameraPanel, 'Text', 'Severity: -',    'Position', [10 0 170 20]);
            app.CoordsLabel     = uilabel(app.CameraPanel, 'Text', 'Coordinates: -', 'Position', [195 0 170 20]);

            % ===== Panel F+G: Disease Info + Mission Stats + Severity =====
            app.StatsPanel = uipanel(app.UIFigure, 'Title', 'Statistics', ...
                'Position', [1000 20 380 265]);

            app.StatsTabGroup = uitabgroup(app.StatsPanel, 'Position', [5 5 370 230]);

            % --- Tab 1: Mission Stats (Panels F+G) ---
            app.StatsTab = uitab(app.StatsTabGroup, 'Title', 'Mission Stats');

            app.TotalStatLabel     = uilabel(app.StatsTab, 'Text', 'Total plants: -',     'Position', [10 175 170 20]);
            app.QueuedStatLabel    = uilabel(app.StatsTab, 'Text', 'Targets queued: -',   'Position', [195 175 170 20]);
            app.HealthyStatLabel   = uilabel(app.StatsTab, 'Text', 'Healthy: -',          'Position', [10 145 170 20]);
            app.ConfirmedStatLabel = uilabel(app.StatsTab, 'Text', 'Confirmed: -',        'Position', [195 145 170 20]);
            app.DiseasedStatLabel  = uilabel(app.StatsTab, 'Text', 'Diseased: -',         'Position', [10 115 170 20]);
            app.RejectedStatLabel  = uilabel(app.StatsTab, 'Text', 'Rejected: -',         'Position', [195 115 170 20]);
            app.SprayedStatLabel   = uilabel(app.StatsTab, 'Text', 'Sprayed: -',          'Position', [10 85  170 20]);
            app.MissionStatLabel   = uilabel(app.StatsTab, 'Text', 'Mission: -', ...
                'Position', [10 55 350 20], 'FontWeight', 'bold');

            % --- Tab 2: Severity (Section 14 - HEURISTIC ONLY) ---
            app.SeverityTab = uitab(app.StatsTabGroup, 'Title', 'Severity');

            app.SeverityAxes = uiaxes(app.SeverityTab, 'Position', [10 50 350 150]);
            app.SeverityBarHandle = bar(app.SeverityAxes, ...
                categorical({'Healthy','Mild','Moderate','Severe'}, ...
                            {'Healthy','Mild','Moderate','Severe'}), ...
                [0 0 0 0]);
            app.SeverityBarHandle.FaceColor = 'flat';
            app.SeverityBarHandle.CData = [0.2 0.8 0.2; 1 0.85 0.2; 1 0.5 0; 0.75 0.1 0.1];
            ylabel(app.SeverityAxes, 'Plants');
            title(app.SeverityAxes, 'Severity Breakdown', 'Interpreter', 'none');

            app.MildCountLabel     = uilabel(app.SeverityTab, 'Text', 'Mild: -',     'Position', [10 28 110 20]);
            app.ModerateCountLabel = uilabel(app.SeverityTab, 'Text', 'Moderate: -', 'Position', [130 28 110 20]);
            app.SevereCountLabel   = uilabel(app.SeverityTab, 'Text', 'Severe: -',   'Position', [250 28 110 20]);

            app.SeverityDisclaimerLabel = uilabel(app.SeverityTab, ...
                'Text', 'Heuristic estimate from model confidence only - NOT a validated measurement (see calculateSeverity.m).', ...
                'Position', [10 4 350 22], 'FontColor', [0.65 0.1 0.1], 'FontSize', 10, ...
                'WordWrap', 'on');
        end
    end
end
