%% STAGE 5 TEST SCRIPT
% Tests: calculateSeverity.m layered on top of the Stage 4 disease
% detection pipeline.
%
% HOW TO RUN:
%   1. Make sure calculateSeverity.m and main_stage5.m are in your
%      project folder along with everything from Stages 1-4.
%   2. Type: main_stage5
%
% WHAT YOU SHOULD SEE:
%   - A clear disclaimer banner printed at the start explaining severity
%     is a heuristic, not a validated measurement (see calculateSeverity.m
%     for the full explanation).
%   - Same two-panel view as Stage 4, but the right panel and console
%     now also show a severity value/label for diseased plants.
%   - Ends with a breakdown of Mild/Moderate/Severe counts alongside the
%     healthy/diseased totals.

clear; clc; close all;

cfg       = config();
fieldInfo = generateField(cfg);
plants    = generatePlants(cfg, fieldInfo);
path      = generateZigZagPath(cfg, fieldInfo);
drone     = initDrone(cfg, path);
drone.state = "ZIGZAG_SEARCH";

generateDemoImages(cfg, plants); % skipped if real images already assigned

fprintf('=====================================================================\n');
if cfg.USE_REAL_MODEL
    fprintf('*** REAL ML MODE ***\n');
else
    fprintf('*** DEMO MODE (random predictions) ***\n');
end
fprintf(['SEVERITY NOTE: severity values below are a HEURISTIC ESTIMATE based\n' ...
         'on model confidence only. This dataset has no severity ground truth,\n' ...
         'so these numbers are NOT a scientifically validated measurement.\n' ...
         'See calculateSeverity.m for full explanation.\n']);
fprintf('=====================================================================\n\n');

%% Set up the figure once
figure('Name','Stage 5: Disease + Heuristic Severity', 'Position',[100 100 1100 550]);

axMap = subplot(1,2,1);
hold(axMap,'on'); grid(axMap,'on'); axis(axMap,'equal');
xlabel(axMap,'X (m)'); ylabel(axMap,'Y (m)');
xlim(axMap,[-1, cfg.fieldLength+1]);
ylim(axMap,[-1, cfg.fieldWidth+1]);

rectangle(axMap, 'Position',[0 0 cfg.fieldLength cfg.fieldWidth], 'EdgeColor','k','LineWidth',1.5);
plot(axMap, path(:,1), path(:,2), 'b--', 'LineWidth',1.0);

plantColors = repmat([0.6 0.6 0.6], height(plants), 1);
hPlants = scatter(axMap, plants.X, plants.Y, 25, plantColors, 'filled');

droneMarker = plot(axMap, drone.pos(1), drone.pos(2), 'ro', 'MarkerSize',10, 'MarkerFaceColor','r');

theta = linspace(0, 2*pi, 40);
camCircle = plot(axMap, drone.pos(1)+cfg.cameraFovRadius*cos(theta), ...
                          drone.pos(2)+cfg.cameraFovRadius*sin(theta), ...
                          'c-', 'LineWidth',1.2);

axImg = subplot(1,2,2);
hImg = imshow(zeros(32,32,3,'uint8'), 'Parent', axImg);
titleImg = title(axImg, 'No plant analysed yet');

%% Simulation loop
missionDone = false;
healthyCount = 0;
diseasedCount = 0;
mildCount = 0;
moderateCount = 0;
severeCount = 0;

while ~missionDone
    [drone, sensors, missionDone] = simulateDrone(drone, path, cfg); %#ok<ASGLU>

    camera = simulateCamera(drone, cfg);
    newlyVisible = getVisiblePlants(plants, camera);

    if ~isempty(newlyVisible)
        for k = 1:numel(newlyVisible)
            idx = newlyVisible(k);
            img = loadPlantImage(plants.ImagePath(idx));

            result = detectDisease(img, cfg);
            result = calculateSeverity(result); % <-- Stage 5 addition

            plants.State(idx)      = result.label;
            plants.Disease(idx)    = result.label;
            plants.Confidence(idx) = result.confidence;
            plants.Severity(idx)   = result.severity;

            if result.label == "DISEASED"
                diseasedCount = diseasedCount + 1;
                markerColor = [0.85 0.1 0.1];

                if result.severity < 30
                    mildCount = mildCount + 1;
                elseif result.severity < 70
                    moderateCount = moderateCount + 1;
                else
                    severeCount = severeCount + 1;
                end

                fprintf('%s -> %s (%.1f%%) | Severity: %.0f/100 [%s]\n', ...
                    plants.ID(idx), result.label, result.confidence, ...
                    result.severity, result.severityLabel);
            else
                healthyCount = healthyCount + 1;
                markerColor = [0.2 0.8 0.2];
                fprintf('%s -> %s (%.1f%%)\n', plants.ID(idx), result.label, result.confidence);
            end
            plantColors(idx,:) = markerColor;
        end

        lastIdx = newlyVisible(end);
        lastImg = loadPlantImage(plants.ImagePath(lastIdx));
        set(hImg, 'CData', lastImg);
        title(axImg, sprintf('%s | %s (%.1f%%) | Sev: %.0f [%s]', ...
            plants.ID(lastIdx), plants.Disease(lastIdx), plants.Confidence(lastIdx), ...
            plants.Severity(lastIdx), 'heuristic'));

        set(hPlants, 'CData', plantColors);
    end

    set(droneMarker, 'XData', drone.pos(1), 'YData', drone.pos(2));
    set(camCircle, 'XData', drone.pos(1)+cfg.cameraFovRadius*cos(theta), ...
                    'YData', drone.pos(2)+cfg.cameraFovRadius*sin(theta));
    title(axMap, sprintf('Row %d/%d | t=%.1fs | healthy=%d diseased=%d', ...
        drone.currentRow, fieldInfo.numRows, drone.missionTime, healthyCount, diseasedCount));
    drawnow limitrate;
end

fprintf('\nMISSION COMPLETE\n');
fprintf('Healthy plants   : %d\n', healthyCount);
fprintf('Diseased plants  : %d\n', diseasedCount);
fprintf('  Mild (heuristic)    : %d\n', mildCount);
fprintf('  Moderate (heuristic): %d\n', moderateCount);
fprintf('  Severe (heuristic)  : %d\n', severeCount);
fprintf('\nReminder: severity numbers are a heuristic proxy from model\n');
fprintf('confidence only, NOT a scientifically validated measurement.\n');
