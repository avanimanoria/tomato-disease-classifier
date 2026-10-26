function sf = sensorFusionStep(sf, meas, cfg)
%SENSORFUSIONSTEP One EKF cycle of the 'sensorFusion' estimator. Uses ONLY sf and meas.
%
%   sf = sensorFusionStep(sf, meas, cfg)
%
%   State x = [px; py; vx; vy; bx; by] (world frame: m, m/s, accelerometer bias m/s^2), P (6x6).
%   Predict : p += v dt + 0.5 dt^2 (a_meas - b),  v += dt (a_meas - b),  b = b (random walk)
%             Q from accelerometer white noise and a small bias random walk.
%   Update 1: optical-flow velocity (linear, H = [0 I 0]) when valid;
%             R = sigma_f^2 + (scaleError |v|)^2 (the scale factor is not estimated -> inflated R)
%   Update 2: LiDAR range to each visible landmark (nonlinear, EKF linearisation
%             H = [(p - Lm)' / |p - Lm|, 0, 0, 0, 0]); sequential scalar updates
%   Innovation gating: NIS chi-square 99.9 % (2 dof 13.82, 1 dof 10.83); gated measurements are
%   rejected and counted. Covariance is symmetrised after each update.
%   No true state is an input of this function (truth firewall; tests/TruthFirewallTest).
    L = cfg.enhancements.localization;
    dt = cfg.dt;
    I2 = eye(2); Z2 = zeros(2);
    F = [I2, dt * I2, -0.5 * dt^2 * I2; Z2, I2, -dt * I2; Z2, Z2, I2];
    G = [0.5 * dt^2 * I2; dt * I2; Z2];
    x = F * sf.x + G * meas.accel(:);
    sbw = 1e-4;                                            % [ASSUMED] bias random walk, m/s^2 per sqrt(s)
    Q = G * G' * L.imuAccelNoise_mps2^2 + blkdiag(Z2, Z2, sbw^2 * dt * I2);
    P = F * sf.P * F' + Q;
    I6 = eye(6);
    if meas.flowValid
        H = [Z2, I2, Z2];
        R = (L.flowVelNoise_mps^2 + (L.scaleError * norm(x(3:4)))^2) * I2;
        y = meas.flow(:) - x(3:4);
        Sm = H * P * H' + R;
        nis = y' / Sm * y;
        sf.nisSum = sf.nisSum + nis; sf.nisN = sf.nisN + 1;
        if nis < 13.82
            K = P * H' / Sm;
            x = x + K * y; P = (I6 - K * H) * P;
            sf.nFlow = sf.nFlow + 1;
        else
            sf.nRejected = sf.nRejected + 1;
        end
    else
        sf.nDropout = sf.nDropout + 1;
    end
    for i = 1:numel(meas.ranges)
        Lm = meas.landmarks(meas.landmarkIdx(i), :);
        dp = x(1:2)' - Lm;
        rh = max(norm(dp), 1e-6);
        H = [dp / rh, 0, 0, 0, 0];
        y = meas.ranges(i) - rh;
        Sm = H * P * H' + L.lidarNoise_m^2;
        nis = y^2 / Sm;
        sf.nisSum = sf.nisSum + nis; sf.nisN = sf.nisN + 1;
        if nis < 10.83
            K = P * H' / Sm;
            x = x + K * y; P = (I6 - K * H) * P;
            sf.nRange = sf.nRange + 1;
        else
            sf.nRejected = sf.nRejected + 1;
        end
    end
    sf.x = x;
    sf.P = (P + P') / 2;
end
