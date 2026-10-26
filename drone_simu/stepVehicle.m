function world = stepVehicle(world, vCmd, windVel, cfg)
%STEPVEHICLE Advance the TRUE (world) drone state by one timestep.
%
%   Kinematic point mass: the commanded ground velocity vCmd is realised
%   exactly, and wind adds a velocity disturbance
%       v_true = vCmd + windCoupling * windVel
%   There is deliberately NO restoring term and NO position clamp (unlike
%   the dashboard's applyWeatherDrift): uncorrected error is free to grow.
%   windCoupling is an ASSUMED lumped parameter (see config.m).

    if isfield(world, 'adv')           % ENHANCEMENT (opt-in): advanced vehicle models
        world = stepVehicleAdvanced(world, vCmd, windVel, cfg);
        return;
    end
    dt = cfg.dt;
    vTrue = vCmd + cfg.internal2.vehicle.windCoupling * windVel;
    world.pos = world.pos + vTrue * dt;
    world.distance = world.distance + norm(vTrue) * dt;
    world.time = world.time + dt;
end
