function sf = sensorFusionInit(pos0, cfg)
%SENSORFUSIONINIT Initial EKF state: the known take-off point, at rest, unknown accelerometer bias.
    sb = max(cfg.enhancements.localization.imuAccelBias_mps2, 1e-3);
    sf.x = [pos0(:); 0; 0; 0; 0];
    sf.P = diag([0.05^2, 0.05^2, 0.05^2, 0.05^2, sb^2, sb^2]);
    sf.nisSum = 0; sf.nisN = 0;
    sf.nFlow = 0; sf.nRange = 0; sf.nRejected = 0; sf.nDropout = 0;
end
