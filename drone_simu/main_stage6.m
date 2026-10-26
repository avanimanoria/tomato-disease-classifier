%% STAGE 6 TEST SCRIPT
% Tests: target queue construction during the zig-zag sweep, followed by
% target approach (navigateToTarget.m) and second-image confirmation
% (confirmTarget.m) for every queued target.
%
% HOW TO RUN:
%   1. Make sure navigateToTarget.m, confirmTarget.m, main_stage6.m are
%      in your project folder along with everything from Stages 1-5.
%   2. Type: main_stage6
%
% WHAT YOU SHOULD SEE:
%   PHASE 1 (familiar from Stage 5): drone sweeps the field, plants
%   turn red/green, console prints each detection. Diseased plants are
%   ALSO added to a target queue (not sprayed yet - no pump in this
%   stage).
%
%   PHASE 2 (NEW): once the sweep finishes, the drone visits each
%   queued target ONE AT A TIME - a yellow line is drawn from the drone
%   to the target while it approaches, then a second image is loaded
%   and re-analysed. Console prints CONFIRMED or REJECTED for each
%   target. Confirmed targets turn purple on the map; rejected ones
%   turn back to green (corrected to healthy).
%
%   Ends with a summary: how many targets were confirmed vs rejected.

clear; clc; close all;

cfg       = config();
fieldInfo = generateField(cfg);
plants    = generatePlants(cfg, fieldInfo);
path      = generateZigZagPath(cfg, fieldInfo);
drone     = initDrone(cfg, path);
drone.state = "ZIGZAG_SEARCH";

generateDemoImages(cfg, plants);

fprintf('=====================================================================\n');
if cfg.USE_REAL_MODEL
    fprintf('*** REAL ML MODE ***\n');
else
    fprintf('*** DEMO MODE (random predictions) ***\n');
end
fprintf('=====================================================================\n\n');

%% Set up the figure once
figure('Name','Stage 6: Target Queue + Approach + Confirmation', 'Position',[100 100 1100 550]);

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

approachLine = plot(axMap, nan, nan, 'y-', 'LineWidth', 1.5);

axImg = subplot(1,2,2);
hImg = imshow(zeros(32,32,3,'uint8'), 'Parent', axImg);
titleImg = title(axImg, 'No plant analysed yet');

%% PHASE 1: zig-zag sweep, build target queue
targetQueue = table('Size',[0 7], ...
    'VariableTypes', {'string','double','double','double','double','double','string'}, ...
    'VariableNames', {'PlantID','X','Y','FirstConfidence','FirstSeverity','DetectionTime','Status'});

missionDone = false;
healthyCount = 0;
diseasedCount = 0;

fprintf('--- PHASE 1: ZIGZAG SWEEP ---\n');
while ~missionDone
    [drone, sensors, missionDone] = simulateDrone(drone, path, cfg); %#ok<ASGLU>

    camera = simulateCamera(drone, cfg);
    newlyVisible = getVisiblePlants(plants, camera);

    if ~isempty(newlyVisible)
        for k = 1:numel(newlyVisible)
            idx = newlyVisible(k);
            img = loadPlantImage(plants.ImagePath(idx));

            result = detectDisease(img, cfg);
            result = calculateSeverity(result);

            plants.State(idx)      = result.label;
            plants.Disease(idx)    = result.label;
            plants.Confidence(idx) = result.confidence;
            plants.Severity(idx)   = result.severity;

            if result.label == "DISEASED"
                diseasedCount = diseasedCount + 1;
                plantColors(idx,:) = [0.85 0.1 0.1];

                % Add to target queue (Section 16/17)
                newRow = {plants.ID(idx), plants.X(idx), plants.Y(idx), ...
                          result.confidence, result.severity, drone.missionTime, "PENDING"};
                targetQueue = [targetQueue; newRow]; %#ok<AGROW>

                fprintf('%s -> DISEASED (%.1f%%) | added to target queue\n', ...
                    plants.ID(idx), result.confidence);
            else
                healthyCount = healthyCount + 1;
                plantColors(idx,:) = [0.2 0.8 0.2];
            end
        end
        set(hPlants, 'CData', plantColors);
    end

    set(droneMarker, 'XData', drone.pos(1), 'YData', drone.pos(2));
    set(camCircle, 'XData', drone.pos(1)+cfg.cameraFovRadius*cos(theta), ...
                    'YData', drone.pos(2)+cfg.cameraFovRadius*sin(theta));
    title(axMap, sprintf('PHASE 1: SWEEP | Row %d/%d | t=%.1fs | targets queued=%d', ...
        drone.currentRow, fieldInfo.numRows, drone.missionTime, height(targetQueue)));
    drawnow limitrate;
end

fprintf('\nSweep complete. %d targets queued.\n\n', height(targetQueue));

%% PHASE 2: visit each queued target, approach, confirm
fprintf('--- PHASE 2: TARGET APPROACH + CONFIRMATION ---\n');
confirmedCount = 0;
rejectedCount = 0;

for t = 1:height(targetQueue)
    targetID = targetQueue.PlantID(t);
    targetXY = [targetQueue.X(t), targetQueue.Y(t)];
    plantIdx = find(plants.ID == targetID, 1);

    fprintf('\nApproaching %s at (%.1f, %.1f)...\n', targetID, targetXY(1), targetXY(2));
    drone.state = "TARGET_APPROACH";

    reached = false;
    while ~reached
        [drone, reached] = navigateToTarget(drone, targetXY, cfg);

        set(droneMarker, 'XData', drone.pos(1), 'YData', drone.pos(2));
        set(approachLine, 'XData', [drone.pos(1), targetXY(1)], 'YData', [drone.pos(2), targetXY(2)]);
        title(axMap, sprintf('PHASE 2: APPROACHING %s | t=%.1fs', targetID, drone.missionTime));
        drawnow limitrate;
    end
    set(approachLine, 'XData', nan, 'YData', nan);

    drone.state = "CONFIRMATION";
    [confirmed, result2] = confirmTarget(plants.ImagePath(plantIdx), cfg);

    img2 = loadPlantImage(plants.ImagePath(plantIdx));
    set(hImg, 'CData', img2);

    if confirmed
        targetQueue.Status(t) = "CONFIRMED";
        plants.Confidence(plantIdx) = result2.confidence;
        plants.Severity(plantIdx)   = result2.severity;
        plantColors(plantIdx,:) = [0.6 0 0.6]; % purple = confirmed target
        confirmedCount = confirmedCount + 1;

        fprintf('%s CONFIRMED diseased (%.1f%%, severity %.0f [%s])\n', ...
            targetID, result2.confidence, result2.severity, result2.severityLabel);
        title(axImg, sprintf('%s CONFIRMED | %.1f%% | Sev %.0f', ...
            targetID, result2.confidence, result2.severity));
    else
        targetQueue.Status(t) = "REJECTED";
        plants.State(plantIdx)   = "HEALTHY";
        plants.Disease(plantIdx) = "HEALTHY";
        plantColors(plantIdx,:) = [0.2 0.8 0.2]; % back to green
        rejectedCount = rejectedCount + 1;

        fprintf('%s REJECTED - second look says HEALTHY, not spraying\n', targetID);
        title(axImg, sprintf('%s REJECTED (was false positive)', targetID));
    end

    set(hPlants, 'CData', plantColors);
    drawnow limitrate;
end

fprintf('\n=====================================================================\n');
fprintf('MISSION COMPLETE (Stage 6 - no spraying yet, that is Stage 7)\n');
fprintf('Healthy (first pass)  : %d\n', healthyCount);
fprintf('Diseased (first pass) : %d\n', diseasedCount);
fprintf('Targets confirmed     : %d\n', confirmedCount);
fprintf('Targets rejected      : %d\n', rejectedCount);
fprintf('=====================================================================\n');
disp(targetQueue);

%% QUICK SEVERITY SUMMARY CHART (preview only - the full live dashboard
%  with all stats panels is built in Stage 8)
confirmedRows = targetQueue.Status == "CONFIRMED";
sevValues = plants.Severity(ismember(plants.ID, targetQueue.PlantID(confirmedRows)));

mildN     = sum(sevValues < 30);
moderateN = sum(sevValues >= 30 & sevValues < 70);
severeN   = sum(sevValues >= 70);

figure('Name','Severity Summary (preview)', 'Position',[150 150 420 380]);
b = bar([healthyCount, mildN, moderateN, severeN]);
b.FaceColor = 'flat';
b.CData = [0.2 0.8 0.2; 1 0.85 0.2; 1 0.5 0; 0.75 0.1 0.1];
set(gca, 'XTickLabel', {'Healthy','Mild','Moderate','Severe'});
ylabel('Number of plants');
title({'Field Severity Summary (heuristic)', ...
    sprintf('%d healthy | %d mild | %d moderate | %d severe', ...
    healthyCount, mildN, moderateN, severeN)});
grid on;
