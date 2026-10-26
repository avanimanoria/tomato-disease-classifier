%% NON-GPS POSITION ESTIMATOR VALIDATION
% Demonstrates that estimatePosition.m can RECONSTRUCT the drone's
% position using ONLY noisy simulated sensor readings (IMU + optical
% flow) - it is given the true position once at takeoff, then never
% again. This is the test that actually supports a "non-GPS
% localization" claim, as opposed to just labeling ground-truth data.
%
% HOW TO RUN: type main_positionEstimator
%
% WHAT YOU SHOULD SEE:
%   - Console: RMS and max position error in meters.
%   - A figure: top plot shows the TRUE flight path (blue) vs the
%     ESTIMATED path reconstructed from sensors only (red dashed) -
%     these should track closely but not perfectly, since the sensors
%     are noisy. Bottom plot shows estimation error over time.

clear; clc; close all;

cfg       = config();
fieldInfo = generateField(cfg);
path      = generateZigZagPath(cfg, fieldInfo);
drone     = initDrone(cfg, path);
drone.state = "ZIGZAG_SEARCH";

est = initPositionEstimator(drone.pos(1:2)); % known starting point only

truePosHistory = [];
estPosHistory  = [];
timeHistory    = [];

missionDone = false;
while ~missionDone
    [drone, sensors, missionDone] = simulateDrone(drone, path, cfg);
    [est, estimatedPos] = estimatePosition(est, sensors, cfg.dt);

    truePosHistory = [truePosHistory; drone.pos(1:2)]; %#ok<AGROW>
    estPosHistory  = [estPosHistory;  estimatedPos];   %#ok<AGROW>
    timeHistory    = [timeHistory;    drone.missionTime]; %#ok<AGROW>
end

errorPerStep = sqrt(sum((truePosHistory - estPosHistory).^2, 2));
rmsError = sqrt(mean(errorPerStep.^2));
maxError = max(errorPerStep);

fprintf('--- NON-GPS POSITION ESTIMATOR RESULTS ---\n');
fprintf('RMS position error: %.3f m\n', rmsError);
fprintf('Max position error: %.3f m\n', maxError);
fprintf(['(The estimator was given the true position only once, at\n' ...
         ' takeoff. Everything else above was reconstructed purely\n' ...
         ' from noisy simulated IMU + optical flow readings.)\n']);

figure('Name', 'Non-GPS Position Estimator Validation');

subplot(2,1,1);
hold on; grid on; axis equal;
plot(truePosHistory(:,1), truePosHistory(:,2), 'b-', 'LineWidth', 1.5, ...
    'DisplayName', 'True position');
plot(estPosHistory(:,1), estPosHistory(:,2), 'r--', 'LineWidth', 1.2, ...
    'DisplayName', 'Estimated position (sensors only)');
xlabel('X (m)'); ylabel('Y (m)');
title('True vs Estimated Trajectory');
legend('Location', 'best');

subplot(2,1,2);
plot(timeHistory, errorPerStep, 'k-');
grid on;
xlabel('Mission time (s)'); ylabel('Position error (m)');
title(sprintf('Estimation Error Over Time (RMS = %.3f m)', rmsError));
