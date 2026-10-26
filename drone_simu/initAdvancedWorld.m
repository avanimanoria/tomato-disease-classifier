function world = initAdvancedWorld(world, cfg)
%INITADVANCEDWORLD Add the optional advanced-physics state to the world struct.
%   Called only when advOn(cfg, 'any'). The drone takes off with a full tank.
    E = cfg.enhancements;
    a.payloadOn = advOn(cfg, 'payload');      % liquid level falls while spraying (else constant, full)
    a.locOn     = advOn(cfg, 'localization'); % estimate = truth + modelled odometry error
    a.vel       = [0 0];                       % true ground velocity, m/s
    a.liquid_L  = E.payload.tankCapacity_L;
    a.energy_J  = 0;
    a.estErr    = [0 0];                       % estimate minus truth, m
    a.lastFix   = 0;                           % time of the last absolute position fix, s
    a.refills   = 0;
    a.estPos    = world.pos;                   % estimator state (imuDeadReckoning / flowOdometry / kalman)
    a.estVel    = [0 0];
    a.P         = 0;                           % KF position variance per axis, m^2
    a.vPrev     = [0 0];                       % previous true velocity (accelerometer model)
    if a.locOn && strcmp(E.localization.mode, 'sensorFusion')     % fields exist ONLY for this mode
        a.landmarks = zeros(0, 2);             % known landmark positions (set by runSurveyPass)
        a.sf = sensorFusionInit(world.pos, cfg);   % EKF starts at the known take-off point
    end
    world.adv = a;
end
