function [est, estimatedPos] = estimatePosition(est, sensors, dt)
%ESTIMATEPOSITION Fuse simulated IMU + optical flow readings into a 2D
%   position estimate using a linear Kalman filter - this is the actual
%   GPS-denied LOCALIZATION algorithm (Section 2 / Objective 2's
%   "localization mapping" requirement), as opposed to the earlier
%   simulateIMU/simulateOpticalFlow/etc. functions, which only generate
%   plausible noisy sensor DATA.
%
%   [est, estimatedPos] = estimatePosition(est, sensors, dt)
%
%   PREDICT step: propagates position/velocity forward using the IMU's
%   acceleration reading (sensors.imu.accel) as a control input.
%   CORRECT step: pulls the estimate toward the optical flow sensor's
%   measured velocity (sensors.flow.velocity), which does not drift the
%   way integrated-acceleration-only dead-reckoning would.
%
%   IMPORTANT: this function only ever sees sensors.imu and
%   sensors.flow - never the drone's true position. It genuinely
%   reconstructs position from noisy measurements, which is what makes
%   this a real (if simplified) non-GPS localization algorithm rather
%   than a label on top of ground truth.
%
%   LIMITATION: this is a constant-velocity linear KF for clarity and to
%   avoid requiring Sensor Fusion/Navigation Toolbox. A production
%   system would typically use a full EKF/UKF also fusing compass
%   heading and LiDAR altitude, and would model sensor bias drift.

    % ---- PREDICT: constant-velocity model, IMU acceleration as input ----
    A = [1 0 dt 0;
         0 1 0 dt;
         0 0 1 0;
         0 0 0 1];
    B = [0.5*dt^2 0;
         0        0.5*dt^2;
         dt       0;
         0        dt];
    u = sensors.imu.accel(1:2)'; % [ax; ay]

    Q = diag([0.01, 0.01, 0.05, 0.05]); % process noise (tune if needed)

    est.x = A * est.x + B * u;
    est.P = A * est.P * A' + Q;

    % ---- CORRECT: optical flow measures velocity directly ----
    H = [0 0 1 0;
         0 0 0 1];
    R = diag([0.05, 0.05]); % measurement noise, matches simulateOpticalFlow's noise scale
    z = sensors.flow.velocity'; % [vx; vy]

    innovation = z - H * est.x;
    S = H * est.P * H' + R;
    K = est.P * H' / S;

    est.x = est.x + K * innovation;
    est.P = (eye(4) - K * H) * est.P;

    estimatedPos = est.x(1:2)';
end
