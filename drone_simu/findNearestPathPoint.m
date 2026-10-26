function [nearestPoint, resumeIdx] = findNearestPathPoint(dronePos, path)
%FINDNEARESTPATHPOINT Find the closest point ON the zig-zag path
%   (Section 21) - NOT just the closest corner waypoint, but the closest
%   point along the path's actual line segments, so the drone rejoins
%   the mission at a sensible spot rather than an arbitrary corner.
%
%   [nearestPoint, resumeIdx] = findNearestPathPoint(dronePos, path)
%   returns:
%     nearestPoint - [X, Y, Z] closest point on the path
%     resumeIdx    - the path row index the drone should head toward
%                    NEXT once it rejoins (i.e. set
%                    drone.pathIndex = resumeIdx - 1 before resuming
%                    simulateDrone, since simulateDrone always targets
%                    path(drone.pathIndex + 1, :))

    p = dronePos(1:2);
    bestDist = inf;
    nearestPoint = path(1,:);
    resumeIdx = 1;

    for i = 1:(size(path,1) - 1)
        a = path(i, 1:2);
        b = path(i+1, 1:2);
        ab = b - a;
        abLenSq = dot(ab, ab);

        if abLenSq < 1e-9
            t = 0;
        else
            t = dot(p - a, ab) / abLenSq;
            t = max(0, min(1, t)); % clamp to the segment
        end

        candidate2D = a + t * ab;
        d = norm(p - candidate2D);

        if d < bestDist
            bestDist = d;
            nearestPoint = [candidate2D, path(i,3)];
            resumeIdx = i + 1; % continue toward the END of this segment
        end
    end
end
