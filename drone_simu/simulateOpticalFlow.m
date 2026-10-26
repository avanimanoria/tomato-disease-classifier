function flow = simulateOpticalFlow(drone, prevDrone, dt)
%SIMULATEOPTICALFLOW  SIMULATED SENSOR INPUT — stands in for a downward
%   optical-flow camera module used for GPS-denied velocity estimation.
%
%   flow = simulateOpticalFlow(drone, prevDrone, dt) returns an estimated
%   horizontal ground velocity [vx, vy] derived from the true simulated
%   position change, with noise added. Real hardware would compute this
%   from pixel displacement between camera frames; this function gives
%   the rest of the system the same output shape (flow.velocity) so a
%   real optical-flow driver can be swapped in later.

    noiseVel = 0.03; % m/s simulated noise

    if dt <= 0
        dt = 0.1;
    end

    trueVelXY = (drone.pos(1:2) - prevDrone.pos(1:2)) / dt;
    flow.velocity  = trueVelXY + noiseVel * randn(1,2); % [vx, vy]
    flow.quality   = 1.0; % 0-1, simulated confidence of the flow estimate
    flow.timestamp = drone.missionTime;
end
