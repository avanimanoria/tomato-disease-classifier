%% STAGE 3 TEST SCRIPT
% Tests: virtual downward camera -> field-of-view visibility detection
% -> actual image file loading for newly-visible plants.
%
% HOW TO RUN:
%   1. Make sure ALL previous files (Stage 1 + Stage 2) plus these NEW
%      Stage 3 files are in the same AgriculturalDroneSimulation folder:
%        simulateCamera.m, getVisiblePlants.m, loadPlantImage.m,
%        generateDemoImages.m, main_stage3.m
%   2. Open this file and press F5, or type: main_stage3
%
% WHAT YOU SHOULD SEE:
%   - Console message generating ~246 placeholder plant images the
%     FIRST time you run this (skipped on later runs).
%   - LEFT panel: field + plants + path + drone, same as Stage 2, PLUS
%     a light blue circle around the drone showing the camera's field
%     of view, PLUS plants changing color from green (NOT_SEEN) to
%     blue (SEEN) as the drone flies over them.
%   - RIGHT panel: the actual image of whichever plant was most
%     recently loaded, with its Plant ID and coordinates as the title.
%   - Console printout whenever new plants enter view, e.g.:
%       "t=2.1s | 3 new plant(s) visible: P003, P004, P005"
%   - Ends with MISSION COMPLETE and a count of how many plants were
%     actually seen (should be less than or equal to total plants,
%     since the camera footprint is narrower than full row coverage
%     unless cfg.cameraFovRadius is large enough).

clear; clc; close all;

cfg       = config();
fieldInfo = generateField(cfg);
plants    = generatePlants(cfg, fieldInfo);
path      = generateZigZagPath(cfg, fieldInfo);
drone     = initDrone(cfg, path);
drone.state = "ZIGZAG_SEARCH";

% Make sure every plant has an image file to load (placeholder for now).
generateDemoImages(cfg, plants);

%% Set up the figure once
figure('Name','Stage 3: Camera FOV + Image Loading', 'Position',[100 100 1100 550]);

% --- LEFT: field map ---
axMap = subplot(1,2,1);
hold(axMap,'on'); grid(axMap,'on'); axis(axMap,'equal');
xlabel(axMap,'X (m)'); ylabel(axMap,'Y (m)');
xlim(axMap,[-1, cfg.fieldLength+1]);
ylim(axMap,[-1, cfg.fieldWidth+1]);

rectangle(axMap, 'Position',[0 0 cfg.fieldLength cfg.fieldWidth], 'EdgeColor','k','LineWidth',1.5);
plot(axMap, path(:,1), path(:,2), 'b--', 'LineWidth',1.0);

plantColors = repmat([0.2 0.8 0.2], height(plants), 1); % green = NOT_SEEN
hPlants = scatter(axMap, plants.X, plants.Y, 25, plantColors, 'filled');

droneMarker = plot(axMap, drone.pos(1), drone.pos(2), 'ro', 'MarkerSize',10, 'MarkerFaceColor','r');

% camera FOV circle (light blue), updated every frame
theta = linspace(0, 2*pi, 40);
camCircle = plot(axMap, drone.pos(1)+cfg.cameraFovRadius*cos(theta), ...
                          drone.pos(2)+cfg.cameraFovRadius*sin(theta), ...
                          'c-', 'LineWidth',1.2);

titleMap = title(axMap, '');

% --- RIGHT: current camera image ---
axImg = subplot(1,2,2);
hImg = imshow(zeros(32,32,3,'uint8'), 'Parent', axImg);
titleImg = title(axImg, 'No plant seen yet');

%% Simulation loop
missionDone = false;
lastPrintTime = -inf;
printInterval = 2.0;
seenCount = 0;

while ~missionDone
    [drone, sensors, missionDone] = simulateDrone(drone, path, cfg); %#ok<ASGLU>

    % --- camera + visibility (Stage 3 core logic) ---
    camera = simulateCamera(drone, cfg);
    newlyVisible = getVisiblePlants(plants, camera);

    if ~isempty(newlyVisible)
        idNames = strjoin(cellstr(plants.ID(newlyVisible)), ', ');
        fprintf('t=%.1fs | %d new plant(s) visible: %s\n', ...
            drone.missionTime, numel(newlyVisible), idNames);

        for k = 1:numel(newlyVisible)
            idx = newlyVisible(k);
            img = loadPlantImage(plants.ImagePath(idx)); % ACTUAL file load
            plants.State(idx) = "SEEN";
            seenCount = seenCount + 1;
        end

        % show the most recently loaded plant's image on the right panel
        lastIdx = newlyVisible(end);
        lastImg = loadPlantImage(plants.ImagePath(lastIdx));
        set(hImg, 'CData', lastImg);
        title(axImg, sprintf('Plant: %s | Coords: (%.1f, %.1f)', ...
            plants.ID(lastIdx), plants.X(lastIdx), plants.Y(lastIdx)));

        % update plant marker colors: SEEN -> blue
        plantColors(newlyVisible,:) = repmat([0.15 0.35 0.9], numel(newlyVisible), 1);
        set(hPlants, 'CData', plantColors);
    end

    % --- update drone + camera circle on map ---
    set(droneMarker, 'XData', drone.pos(1), 'YData', drone.pos(2));
    set(camCircle, 'XData', drone.pos(1)+cfg.cameraFovRadius*cos(theta), ...
                    'YData', drone.pos(2)+cfg.cameraFovRadius*sin(theta));
    title(axMap, sprintf('Row %d/%d | t=%.1fs | seen=%d/%d', ...
        drone.currentRow, fieldInfo.numRows, drone.missionTime, ...
        seenCount, fieldInfo.totalPlants));
    drawnow limitrate;

    if drone.missionTime - lastPrintTime >= printInterval && isempty(newlyVisible)
        lastPrintTime = drone.missionTime; % keep periodic heartbeat even with no new plants
    end
end

fprintf('\nMISSION COMPLETE\n');
fprintf('Plants seen: %d / %d\n', seenCount, fieldInfo.totalPlants);
