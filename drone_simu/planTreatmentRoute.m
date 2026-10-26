function [order, totalLength] = planTreatmentRoute(startXY, points)
%PLANTREATMENTROUTE Nearest-neighbour visiting order for Pass 2.
%
%   [order, totalLength] = planTreatmentRoute(startXY, points)
%   Greedy: from the current position always go to the closest unvisited
%   point (ties -> lowest index). Straight-line legs, no return-to-path.
%   Not optimal (no 2-opt in Internal-2); points is Mx2.

    M = size(points, 1);
    order = zeros(M, 1);
    totalLength = 0;
    if M == 0, return; end

    remaining = true(M, 1);
    cur = startXY(:)';
    for k = 1:M
        d = vecnorm(points - cur, 2, 2);
        d(~remaining) = inf;
        [dmin, j] = min(d);
        order(k) = j;
        totalLength = totalLength + dmin;
        remaining(j) = false;
        cur = points(j, :);
    end
end
