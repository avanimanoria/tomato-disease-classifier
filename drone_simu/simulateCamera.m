function camera = simulateCamera(drone, cfg)
%SIMULATECAMERA Compute the downward camera's ground footprint (Section 9).
%
%   camera = simulateCamera(drone, cfg) returns the circular ground
%   coverage area directly below the drone. Only plants inside this
%   footprint are considered "visible" and eligible for image analysis.

    camera.center = drone.pos(1:2);      % [X, Y] center of view on ground
    camera.radius = cfg.cameraFovRadius; % meters
end
