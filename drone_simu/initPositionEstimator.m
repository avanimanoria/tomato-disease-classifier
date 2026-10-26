function est = initPositionEstimator(initialPos)
%INITPOSITIONESTIMATOR Initialize a linear Kalman filter for GPS-denied
%   2D position/velocity estimation.
%
%   est = initPositionEstimator(initialPos) where initialPos = [X, Y] is
%   the drone's KNOWN starting position (e.g. the takeoff point, (0,0),
%   which is a reasonable real-world assumption - the drone starts at a
%   known local origin). After this single initialization, the filter
%   never receives the true position again; estimatePosition.m must
%   reconstruct it purely from noisy sensor readings.
%
%   State vector: [x; y; vx; vy]

    est.x = [initialPos(1); initialPos(2); 0; 0];
    est.P = eye(4) * 0.1; % initial covariance (uncertainty)
end
