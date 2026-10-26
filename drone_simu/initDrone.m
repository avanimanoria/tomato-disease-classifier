function drone = initDrone(cfg, path)
%INITDRONE Create the initial drone state struct (Section 30).
%
%   drone = initDrone(cfg, path) sets the drone at the first waypoint of
%   the zig-zag path, ready to start the mission.

    drone.pos          = path(1,:);   % [X, Y, Z] local coordinates
    drone.speed        = cfg.droneSpeed;
    drone.currentRow   = 1;
    drone.pathIndex    = 1;           % index of the NEXT waypoint we're heading to
    drone.distanceTravelled = 0;
    drone.missionTime  = 0;
    drone.lastHeading  = 0;
    drone.state        = "IDLE";      % state machine, Section 25
end
