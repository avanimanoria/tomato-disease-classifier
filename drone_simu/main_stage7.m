%% STAGE 7 TEST SCRIPT
% Tests: sprayTarget.m + findNearestPathPoint.m + returnToPath.m, layered
% on top of the Stage 6 target queue / approach / confirmation pipeline.
%
% HOW TO RUN:
%   1. Make sure sprayTarget.m, findNearestPathPoint.m, returnToPath.m,
%      main_stage7.m are in your project folder along with everything
%      from Stages 1-6.
%   2. Type: main_stage7
%
% WHAT YOU SHOULD SEE:
%   PHASE 1: same zig-zag sweep as before, building the target queue.
%
%   PHASE 2 (extended): for each target -
%     - approach (yellow line drone -> target)
%     - confirm (second image re-check)
%     - IF CONFIRMED: simulated spray (console prints Pump ON/OFF),
%       plant turns BLACK on the map (sprayed), THEN the drone returns
%       to the nearest point on the zig-zag path (yellow line drone ->
%       path point this time, not the original target)
%     - IF REJECTED: no spray, plant turns back to green, no return
%       leg needed (never left final position from the approach)
%
%   Ends with a full mission summary including total distance travelled
%   and a spray-status breakdown, plus a reminder that duplicate-spray
%   protection is active (Section 26).

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
figure('Name','Stage 7: Spray + Return-to-Path', 'Position',[100 100 1100 550]);

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
returnLine   = plot(axMap, nan, nan, 'm-', 'LineWidth', 1.5);

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

                newRow = {plants.ID(idx), plants.X(idx), plants.Y(idx), ...
                          result.confidence, result.severity, drone.missionTime, "PENDING"};
                targetQueue = [targetQueue; newRow]; %#ok<AGROW>
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

fprintf('Sweep complete. %d targets queued.\n\n', height(targetQueue));

%% PHASE 2: approach, confirm, spray, return-to-path
fprintf('--- PHASE 2: APPROACH + CONFIRM + SPRAY + RETURN ---\n');
confirmedCount = 0;
rejectedCount = 0;
sprayedCount = 0;

for t = 1:height(targetQueue)
    targetID = targetQueue.PlantID(t);
    targetXY = [targetQueue.X(t), targetQueue.Y(t)];
    plantIdx = find(plants.ID == targetID, 1);

    % --- APPROACH ---
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

    % --- CONFIRM ---
    drone.state = "CONFIRMATION";
    [confirmed, result2] = confirmTarget(plants.ImagePath(plantIdx), cfg);

    img2 = loadPlantImage(plants.ImagePath(plantIdx));
    set(hImg, 'CData', img2);

    if confirmed
        targetQueue.Status(t) = "CONFIRMED";
        plants.Confidence(plantIdx) = result2.confidence;
        plants.Severity(plantIdx)   = result2.severity;
        confirmedCount = confirmedCount + 1;
        fprintf('%s CONFIRMED diseased (%.1f%%, severity %.0f [%s])\n', ...
            targetID, result2.confidence, result2.severity, result2.severityLabel);

        % --- SPRAY (Section 20) ---
        drone.state = "SPRAYING";
        fprintf('Spraying %s:\n', targetID);
        plants = sprayTarget(plants, plantIdx, cfg);
        sprayedCount = sprayedCount + 1;
        plantColors(plantIdx,:) = [0 0 0]; % black = sprayed
        set(hPlants, 'CData', plantColors);
        title(axImg, sprintf('%s SPRAYED | %.1f%% | Sev %.0f', ...
            targetID, result2.confidence, result2.severity));

        % --- RETURN TO PATH (Section 21) ---
        drone.state = "RETURN_TO_PATH";
        [nearestPoint, resumeIdx] = findNearestPathPoint(drone.pos, path);
        fprintf('Returning to nearest path point (%.1f, %.1f)...\n', ...
            nearestPoint(1), nearestPoint(2));

        reached = false;
        while ~reached
            [drone, reached] = returnToPath(drone, nearestPoint, cfg);
            set(droneMarker, 'XData', drone.pos(1), 'YData', drone.pos(2));
            set(returnLine, 'XData', [drone.pos(1), nearestPoint(1)], 'YData', [drone.pos(2), nearestPoint(2)]);
            title(axMap, sprintf('PHASE 2: RETURNING TO PATH | t=%.1fs', drone.missionTime));
            drawnow limitrate;
        end
        set(returnLine, 'XData', nan, 'YData', nan);
        drone.pathIndex = resumeIdx - 1; % resume mission bookkeeping
        drone.state = "ZIGZAG_SEARCH";

    else
        targetQueue.Status(t) = "REJECTED";
        plants.State(plantIdx)   = "HEALTHY";
        plants.Disease(plantIdx) = "HEALTHY";
        plantColors(plantIdx,:) = [0.2 0.8 0.2];
        rejectedCount = rejectedCount + 1;
        fprintf('%s REJECTED - second look says HEALTHY, not spraying\n', targetID);
        title(axImg, sprintf('%s REJECTED (was false positive)', targetID));
        set(hPlants, 'CData', plantColors);
    end
end

fprintf('\n=====================================================================\n');
fprintf('MISSION COMPLETE\n');
fprintf('Healthy (first pass)  : %d\n', healthyCount);
fprintf('Diseased (first pass) : %d\n', diseasedCount);
fprintf('Targets confirmed     : %d\n', confirmedCount);
fprintf('Targets rejected      : %d\n', rejectedCount);
fprintf('Plants sprayed        : %d\n', sprayedCount);
fprintf('Total distance        : %.1f m\n', drone.distanceTravelled);
fprintf('Total mission time    : %.1f s\n', drone.missionTime);
fprintf('=====================================================================\n');
fprintf('Duplicate-spray protection is active in sprayTarget.m (Section 26).\n');
