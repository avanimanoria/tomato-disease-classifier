%% STAGE 2 TEST SCRIPT
% Tests: continuous drone movement along the zig-zag path (no teleporting)
% + simulated IMU / optical flow / LiDAR / compass.
%
% HOW TO RUN:
%   1. Make sure config.m, generateField.m, generatePlants.m,
%      generateZigZagPath.m, initDrone.m, simulateDrone.m,
%      simulateIMU.m, simulateOpticalFlow.m, simulateLiDAR.m,
%      simulateCompass.m are ALL in the same folder.
%   2. Open this file and press F5, or type: main_stage2
%
% WHAT YOU SHOULD SEE:
%   - A figure with the field, plants, and full zig-zag path drawn once.
%   - A red drone marker that moves smoothly (not jumping) along the
%     zig-zag path in small steps.
%   - Console printout every ~2 seconds of mission time showing the
%     drone's position, distance travelled, and simulated sensor values.
%   - "MISSION COMPLETE" printed once the drone reaches the final point.

clear; clc; close all;

cfg       = config();
fieldInfo = generateField(cfg);
plants    = generatePlants(cfg, fieldInfo);
path      = generateZigZagPath(cfg, fieldInfo);
drone     = initDrone(cfg, path);
drone.state = "ZIGZAG_SEARCH";

%% Set up the figure once
figure('Name','Stage 2: Continuous Drone Movement');
hold on; grid on; axis equal;
xlabel('X (m)'); ylabel('Y (m)');
xlim([-1, cfg.fieldLength+1]);
ylim([-1, cfg.fieldWidth+1]);
title('Stage 2: Drone flying the zig-zag path (GPS-DENIED, local coords)');

rectangle('Position',[0 0 cfg.fieldLength cfg.fieldWidth], 'EdgeColor','k','LineWidth',1.5);
scatter(plants.X, plants.Y, 20, 'g', 'filled');
plot(path(:,1), path(:,2), 'b--', 'LineWidth',1.0);

droneMarker = plot(drone.pos(1), drone.pos(2), 'ro', 'MarkerSize',10, 'MarkerFaceColor','r');
droneTrail  = animatedline('Color','r','LineWidth',1.0);
addpoints(droneTrail, drone.pos(1), drone.pos(2));

statusText = title(''); % placeholder, updated in loop below

%% Simulation loop
missionDone = false;
lastPrintTime = -inf;
printInterval = 2.0; % seconds of mission time between console printouts

while ~missionDone
    [drone, sensors, missionDone] = simulateDrone(drone, path, cfg);

    % --- update plot ---
    set(droneMarker, 'XData', drone.pos(1), 'YData', drone.pos(2));
    addpoints(droneTrail, drone.pos(1), drone.pos(2));
    title(sprintf('Row %d/%d | t=%.1fs | dist=%.1fm | state=%s', ...
        drone.currentRow, fieldInfo.numRows, drone.missionTime, ...
        drone.distanceTravelled, drone.state));
    drawnow limitrate;

    % --- periodic console printout of sensors ---
    if drone.missionTime - lastPrintTime >= printInterval
        lastPrintTime = drone.missionTime;
        fprintf(['t=%.1fs | pos=[%.2f, %.2f, %.2f] | speed=%.1fm/s | ' ...
                 'heading=%.0fdeg | lidarAlt=%.2fm | flowVel=[%.2f,%.2f]\n'], ...
            drone.missionTime, drone.pos(1), drone.pos(2), drone.pos(3), ...
            drone.speed, sensors.compass.heading, sensors.lidar.altitude, ...
            sensors.flow.velocity(1), sensors.flow.velocity(2));
    end
end

fprintf('\nMISSION COMPLETE\n');
fprintf('Total distance travelled: %.2f m (estimated path length was %.2f m)\n', ...
    drone.distanceTravelled, fieldInfo.estimatedPathLength);
fprintf('Total mission time: %.1f s\n', drone.missionTime);
