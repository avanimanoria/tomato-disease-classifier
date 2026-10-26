%% STAGE 4 TEST SCRIPT
% Tests: detectDisease.m running in DEMO MODE, fully wired into the
% camera -> visibility -> image -> ML pipeline built in Stage 3.
%
% HOW TO RUN:
%   1. Make sure ALL previous files (Stages 1-3) plus these NEW Stage 4
%      files are in the same AgriculturalDroneSimulation folder:
%        createDatasetFolders.m, detectDisease.m, loadDiseaseModel.m,
%        evaluateDiseaseModel.m, trainDiseaseModel.m, main_stage4.m
%   2. Open this file and press F5, or type: main_stage4
%
% WHAT YOU SHOULD SEE:
%   - Console banner confirming "DEMO MODE" is active.
%   - LEFT panel: same field/camera view as Stage 3, but now plant dots
%     turn GREEN (healthy) or RED (diseased) instead of just blue.
%   - RIGHT panel: the loaded image plus the ML prediction, confidence,
%     and coordinates for the most recently analysed plant.
%   - Console prints each analysed plant's prediction, e.g.:
%       "P005 -> DISEASED (84.2%)"
%   - Ends with MISSION COMPLETE and a healthy/diseased count summary.
%
% NOTE: predictions are RANDOM in Demo Mode (no real model yet) - this
% only proves the pipeline wiring works. Real predictions arrive once
% you run trainDiseaseModel.m on your actual dataset and set
% cfg.USE_REAL_MODEL = true in config.m.

clear; clc; close all;

cfg       = config();
fieldInfo = generateField(cfg);
plants    = generatePlants(cfg, fieldInfo);
path      = generateZigZagPath(cfg, fieldInfo);
drone     = initDrone(cfg, path);
drone.state = "ZIGZAG_SEARCH";

generateDemoImages(cfg, plants);

if cfg.USE_REAL_MODEL
    fprintf('*** REAL ML MODE ***\n');
else
    fprintf('*** DEMO MODE (random predictions - no trained model used) ***\n');
end

%% Set up the figure once
figure('Name','Stage 4: Disease Detection Pipeline', 'Position',[100 100 1100 550]);

axMap = subplot(1,2,1);
hold(axMap,'on'); grid(axMap,'on'); axis(axMap,'equal');
xlabel(axMap,'X (m)'); ylabel(axMap,'Y (m)');
xlim(axMap,[-1, cfg.fieldLength+1]);
ylim(axMap,[-1, cfg.fieldWidth+1]);

rectangle(axMap, 'Position',[0 0 cfg.fieldLength cfg.fieldWidth], 'EdgeColor','k','LineWidth',1.5);
plot(axMap, path(:,1), path(:,2), 'b--', 'LineWidth',1.0);

plantColors = repmat([0.6 0.6 0.6], height(plants), 1); % gray = NOT_SEEN
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

while ~missionDone
    [drone, sensors, missionDone] = simulateDrone(drone, path, cfg); %#ok<ASGLU>

    camera = simulateCamera(drone, cfg);
    newlyVisible = getVisiblePlants(plants, camera);

    if ~isempty(newlyVisible)
        for k = 1:numel(newlyVisible)
            idx = newlyVisible(k);
            img = loadPlantImage(plants.ImagePath(idx));

            result = detectDisease(img, cfg); % <-- Stage 4 core call

            plants.State(idx)      = result.label;   % "HEALTHY" or "DISEASED"
            plants.Disease(idx)    = result.label;
            plants.Confidence(idx) = result.confidence;

            if result.label == "DISEASED"
                diseasedCount = diseasedCount + 1;
                markerColor = [0.85 0.1 0.1]; % red
            else
                healthyCount = healthyCount + 1;
                markerColor = [0.2 0.8 0.2]; % green
            end
            plantColors(idx,:) = markerColor;

            fprintf('%s -> %s (%.1f%%)\n', plants.ID(idx), result.label, result.confidence);
        end

        lastIdx = newlyVisible(end);
        lastImg = loadPlantImage(plants.ImagePath(lastIdx));
        set(hImg, 'CData', lastImg);
        title(axImg, sprintf('Plant: %s | %s (%.1f%%) | (%.1f, %.1f)', ...
            plants.ID(lastIdx), plants.Disease(lastIdx), plants.Confidence(lastIdx), ...
            plants.X(lastIdx), plants.Y(lastIdx)));

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
fprintf('Healthy plants  : %d\n', healthyCount);
fprintf('Diseased plants : %d\n', diseasedCount);
fprintf('Total analysed  : %d / %d\n', healthyCount+diseasedCount, fieldInfo.totalPlants);
