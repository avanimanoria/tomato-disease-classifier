function world = stepVehicleAdvanced(world, vCmd, windVel, cfg)
%STEPVEHICLEADVANCED One timestep with the optional advanced vehicle models.
%
%   Called by stepVehicle only when world.adv exists (advOn(cfg,'any')).
%
%   dynamics ON : point mass with first-order velocity tracking and physical wind drag
%                   a_cmd  = (vCmd - v) / tau, |a_cmd| <= a_max(m)
%                   a_max  = g * sqrt((T_max / (m g))^2 - 1)   (horizontal accel at full thrust,
%                            T_max = thrustToWeightFull * m_full * g)
%                   a_drag = -0.5 rho CdA |v - w| (v - w) / m   (replaces the lumped windCoupling)
%                 so a lighter drone (emptier tank) is pushed harder by the same wind.
%   dynamics OFF: the original kinematic model v = vCmd + windCoupling * w (same arithmetic).
%   energy ON   : P = (m g)^1.5 / sqrt(2 rho A) / eta   (momentum-theory hover power)
%                   + 0.5 rho CdA |v - w|^3 / eta + avionics; energy += P dt.
%   localization ON: estimate error = random walk + odometry scale error along the motion,
%                 reset to a small fix noise every fixInterval_s (absolute fix, e.g. landmark).
%   All parameters are [ASSUMED] placeholders (config.m, cfg.enhancements).

    E = cfg.enhancements;
    dt = cfg.dt;
    g = 9.81;
    a = world.adv;
    m = advMass(world, cfg);
    rho = E.dynamics.airDensity_kgm3;

    if advOn(cfg, 'dynamics')
        D = E.dynamics;
        mFull = E.payload.dryMass_kg + E.payload.tankCapacity_L * E.payload.liquidDensity_kgL;
        Tmax = D.thrustToWeightFull * mFull * g;
        aMax = g * sqrt(max((Tmax / (m * g))^2 - 1, 0));
        aCmd = (vCmd - a.vel) / D.velTimeConstant_s;
        na = norm(aCmd);
        if na > aMax, aCmd = aCmd * (aMax / na); end
        vAir = a.vel - windVel;
        aDrag = -0.5 * rho * D.dragArea_m2 * norm(vAir) * vAir / m;
        a.vel = a.vel + (aCmd + aDrag) * dt;
        vTrue = a.vel;
    else
        vTrue = vCmd + cfg.internal2.vehicle.windCoupling * windVel;
        a.vel = vTrue;
    end

    if advOn(cfg, 'energy')
        En = E.energy;
        vAir = vTrue - windVel;
        P = (m * g)^1.5 / sqrt(2 * rho * En.rotorDiskArea_m2) / En.efficiency ...
            + 0.5 * rho * E.dynamics.dragArea_m2 * norm(vAir)^3 / En.efficiency + En.avionics_W;
        a.energy_J = a.energy_J + P * dt;
    end

    newPos = world.pos + vTrue * dt;
    if a.locOn
        L = E.localization;
        k = round(world.time / dt) + 1;
        fixDue = world.time + dt - a.lastFix >= L.fixInterval_s;
        switch L.mode
            case 'errorModel'          % original enhancement: error random walk + scale error + resets
                a.estErr = a.estErr + L.randomWalk_m_sqrt_s * sqrt(dt) * advNoise(L.seed, k) + L.scaleError * vTrue * dt;
                if fixDue
                    a.estErr = L.fixNoise_m * advNoise(L.seed + 1, k);
                    a.lastFix = world.time + dt;
                end
            case 'imuDeadReckoning'    % weak baseline: double-integrate a noisy, biased accelerometer
                b = advNoise(L.seed + 3, 1); b = b / max(norm(b), eps);
                aMeas = (vTrue - a.vPrev) / dt + L.imuAccelBias_mps2 * b + L.imuAccelNoise_mps2 * advNoise(L.seed + 2, k);
                a.estVel = a.estVel + aMeas * dt;
                a.estPos = a.estPos + a.estVel * dt;
                a.estErr = a.estPos - newPos;
            case {'flowOdometry', 'kalman'}   % optical-flow velocity integration (+ KF update on absolute fixes)
                vMeas = vTrue * (1 + L.scaleError) + L.flowVelNoise_mps * advNoise(L.seed + 2, k);
                a.estPos = a.estPos + vMeas * dt;
                a.P = a.P + (L.flowVelNoise_mps * dt)^2 + (L.scaleError * norm(vTrue) * dt)^2;
                if strcmp(L.mode, 'kalman') && fixDue
                    z = newPos + L.fixNoise_m * advNoise(L.seed + 1, k);
                    K = a.P / (a.P + L.fixNoise_m^2);
                    a.estPos = a.estPos + K * (z - a.estPos);
                    a.P = (1 - K) * a.P;
                    a.lastFix = world.time + dt;
                end
                a.estErr = a.estPos - newPos;
            case 'sensorFusion'        % EKF: sensors generated from truth (sfSensors), estimator sees measurements only
                meas = sfSensors(newPos, vTrue, (vTrue - a.vPrev) / dt, cfg, k, a.landmarks);
                a.sf = sensorFusionStep(a.sf, meas, cfg);
                a.estPos = a.sf.x(1:2)';
                a.estErr = a.estPos - newPos;           % evaluation only (logged), never used by the estimator
                a.P = trace(a.sf.P(1:2, 1:2)) / 2;
            otherwise
                error('stepVehicleAdvanced:badLocMode', 'Unknown localization mode "%s".', L.mode);
        end
    end
    a.vPrev = vTrue;

    world.pos = newPos;
    world.distance = world.distance + norm(vTrue) * dt;
    world.time = world.time + dt;
    world.adv = a;
end
