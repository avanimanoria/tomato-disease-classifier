function compass = simulateCompass(drone, prevDrone)
%SIMULATECOMPASS  SIMULATED SENSOR INPUT — stands in for a magnetometer
%   used to estimate drone heading without GPS.
%
%   compass = simulateCompass(drone, prevDrone) estimates heading (in
%   degrees, 0 = +X axis, counter-clockwise positive) from the direction
%   of travel between two timesteps, plus small noise. Real hardware
%   would read the magnetic field directly; this keeps the same
%   interface (compass.heading) so a real magnetometer driver can be
%   swapped in later.

    noiseHeading = 1.0; % degrees simulated noise

    delta = drone.pos(1:2) - prevDrone.pos(1:2);
    if norm(delta) < 1e-6
        heading = drone.lastHeading; % no movement: keep previous heading
    else
        heading = atan2d(delta(2), delta(1));
    end

    compass.heading   = mod(heading + noiseHeading * randn(), 360);
    compass.timestamp = drone.missionTime;
end
