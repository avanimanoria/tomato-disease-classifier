function [drone, sensors, missionDone] = simulateDrone(drone, path, cfg)
%SIMULATEDRONE Advance the drone by ONE timestep (Section 7).
%
%   [drone, sensors, missionDone] = simulateDrone(drone, path, cfg)
%   moves the drone a small distance (speed * dt) toward the next
%   zig-zag waypoint, instead of teleporting between corners. Call this
%   once per timestep from a loop or a timer callback.
%
%   Returns:
%     drone       - updated drone struct
%     sensors     - struct with simulated IMU / optical flow / LiDAR /
%                   compass readings for this timestep
%     missionDone - true once the drone has reached the final waypoint

    prevDrone = drone;
    dt = cfg.dt;
    missionDone = false;

    numWaypoints = size(path,1);

    if drone.pathIndex >= numWaypoints
        % Already at the final waypoint - nothing more to do.
        missionDone = true;
        sensors = packageSensors(drone, prevDrone, dt);
        return;
    end

    target = path(drone.pathIndex + 1, :);
    toTarget = target - drone.pos;
    dist2D = norm(toTarget(1:2)); % altitude assumed constant during search

    stepDist = drone.speed * dt;

    if dist2D <= stepDist || dist2D < 1e-6
        % Reached (or overshoot-would-pass) this waypoint: snap to it.
        moved = norm(drone.pos(1:2) - target(1:2));
        drone.pos = target;
        drone.pathIndex = drone.pathIndex + 1;
        drone.currentRow = ceil(drone.pathIndex / 2);
    else
        dirUnit = toTarget(1:2) / dist2D;
        drone.pos(1:2) = drone.pos(1:2) + dirUnit * stepDist;
        moved = stepDist;
    end

    drone.distanceTravelled = drone.distanceTravelled + moved;
    drone.missionTime = drone.missionTime + dt;

    if drone.pathIndex >= numWaypoints
        missionDone = true;
        drone.state = "MISSION_COMPLETE";
    end

    % ---- heading update (used by simulateCompass) ----
    delta = drone.pos(1:2) - prevDrone.pos(1:2);
    if norm(delta) > 1e-6
        drone.lastHeading = atan2d(delta(2), delta(1));
    end

    sensors = packageSensors(drone, prevDrone, dt);
end

function sensors = packageSensors(drone, prevDrone, dt)
    sensors.imu      = simulateIMU(drone, prevDrone, dt);
    sensors.flow     = simulateOpticalFlow(drone, prevDrone, dt);
    sensors.lidar    = simulateLiDAR(drone);
    sensors.compass  = simulateCompass(drone, prevDrone);
end
