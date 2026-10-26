function [drone, reached] = returnToPath(drone, targetPoint, cfg)
%RETURNTOPATH Move the drone ONE timestep back toward the nearest point
%   on the zig-zag path after spraying (Section 21).
%
%   [drone, reached] = returnToPath(drone, targetPoint, cfg) reuses the
%   same step-by-step movement as navigateToTarget.m. Kept as its own
%   file (rather than just calling navigateToTarget directly everywhere)
%   so the return-to-path behavior has one clear place to change later -
%   e.g. if you later want the return leg to fly at normal search speed
%   instead of the slower target-approach speed.

    [drone, reached] = navigateToTarget(drone, targetPoint(1:2), cfg);
end
