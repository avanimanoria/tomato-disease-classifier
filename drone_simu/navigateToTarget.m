function [drone, reached] = navigateToTarget(drone, targetXY, cfg)
%NAVIGATETOTARGET Move the drone ONE timestep toward an arbitrary target
%   position, leaving the normal zig-zag path (Section 18).
%
%   [drone, reached] = navigateToTarget(drone, targetXY, cfg) advances
%   the drone toward targetXY = [X, Y] at a REDUCED speed (per Section
%   18: "move slowly near the target"), returning reached = true once
%   it arrives.

    approachSpeed = cfg.droneSpeed * 0.6; % slower than normal search speed
    dt = cfg.dt;

    toTarget = targetXY(:)' - drone.pos(1:2);
    dist = norm(toTarget);
    stepDist = approachSpeed * dt;

    reached = false;

    if dist <= stepDist || dist < 0.05
        drone.pos(1:2) = targetXY(:)';
        moved = dist;
        reached = true;
    else
        dirUnit = toTarget / dist;
        drone.pos(1:2) = drone.pos(1:2) + dirUnit * stepDist;
        moved = stepDist;
    end

    drone.distanceTravelled = drone.distanceTravelled + moved;
    drone.missionTime = drone.missionTime + dt;
end
