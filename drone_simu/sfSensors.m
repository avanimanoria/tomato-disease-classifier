function meas = sfSensors(posTrue, vTrue, aTrue, cfg, k, landmarks)
%SFSENSORS Synthetic sensor measurements for the 'sensorFusion' estimator (truth used HERE only).
%
%   meas = sfSensors(posTrue, vTrue, aTrue, cfg, k, landmarks)
%
%   Frame: planar world frame (x east, y north), metres / seconds. Yaw is assumed known, so
%   body-frame sensors are expressed directly in the world frame (limitation).
%     accel   IMU accelerometer, every step (10 Hz): true accel + constant unknown bias
%             (seeded direction) + white noise
%     flow    optical-flow ground velocity, every step: true velocity x (1 + scaleError) + noise;
%             flowValid = false with probability flowDropoutProb (dropout)
%     ranges  LiDAR ranges to KNOWN landmarks = the field corner posts (polygon vertices),
%             at lidarRate_Hz, only for posts within lidarRange_m; + white noise
%   Independent seeded streams (advNoise seeds +3..+8). All values are [ASSUMED] placeholders.
    L = cfg.enhancements.localization;
    dt = cfg.dt;
    b = advNoise(L.seed + 3, 1); b = b / max(norm(b), eps);
    meas.accel = aTrue + L.imuAccelBias_mps2 * b + L.imuAccelNoise_mps2 * advNoise(L.seed + 4, k);
    u = advNoise(L.seed + 8, k);
    thr = sqrt(2) * erfinv(1 - 2 * L.flowDropoutProb);        % P(N(0,1) > thr) = dropout probability
    meas.flowValid = u(1) < thr;
    meas.flow = vTrue * (1 + L.scaleError) + L.flowVelNoise_mps * advNoise(L.seed + 5, k);
    period = max(1, round(1 / (L.lidarRate_Hz * dt)));
    meas.ranges = zeros(0, 1); meas.landmarkIdx = zeros(0, 1);
    if mod(k, period) == 0 && ~isempty(landmarks)
        d = vecnorm(landmarks - posTrue, 2, 2);
        vis = find(d <= L.lidarRange_m);
        nz = [advNoise(L.seed + 6, k), advNoise(L.seed + 7, k), advNoise(L.seed + 9, k)];
        for j = 4:ceil(numel(vis) / 2), nz = [nz, advNoise(L.seed + 100 + j, k)]; end %#ok<AGROW> fields with > 6 posts
        meas.ranges = d(vis) + L.lidarNoise_m * nz(1:numel(vis))';
        meas.landmarkIdx = vis;
    end
    meas.landmarks = landmarks;
end
