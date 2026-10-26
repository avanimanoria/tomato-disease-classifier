function r = routeLengths(startXY, pts, field, cfg)
%ROUTELENGTHS Distances/times of the three routing behaviours over ONE target set.
%
%   r = routeLengths(startXY, pts, field, cfg)
%
%   pts (Mx2) is visited by:
%     nn        nearest-neighbour order (planTreatmentRoute), straight legs
%     detOrder  the given row order of pts, straight legs, no return
%     stage7    given order, and after EACH target a return to the nearest point
%               of the survey path (findNearestPathPoint) before the next leg;
%               flown at cfg.internal2.metrics.stage7SpeedFactor * droneSpeed
%   plus the reference "repeat the whole survey". All are straight-line,
%   nominal geometric estimates: no wind, no hover/dwell time. Every
%   algorithm sees the identical pts and startXY.
%
%   Fields: nnOrder, nnLength, nnFlightTime, detOrderLength, detOrderFlightTime,
%   stage7Length, stage7FlightTime, fullSurveyLength, fullSurveyFlightTime.

    v = cfg.droneSpeed;
    [order, nnLen] = planTreatmentRoute(startXY, pts);

    r.nnOrder             = order;
    r.nnLength            = nnLen;
    r.nnFlightTime        = nnLen / v;
    r.detOrderLength      = chainLength(startXY, pts);
    r.detOrderFlightTime  = r.detOrderLength / v;
    r.stage7Length        = stage7Length(startXY, pts, field.surveyPath3);
    r.stage7FlightTime    = r.stage7Length / (cfg.internal2.metrics.stage7SpeedFactor * v);
    r.fullSurveyLength    = field.surveyRef.len;
    r.fullSurveyFlightTime = field.surveyRef.len / v;
end

function L = chainLength(startXY, pts)
%CHAINLENGTH Length of start -> pts(1) -> pts(2) -> ... (given order).
    L = 0;
    cur = startXY(:)';
    for j = 1:size(pts, 1)
        L = L + norm(pts(j, :) - cur);
        cur = pts(j, :);
    end
end

function L = stage7Length(startXY, pts, path3)
%STAGE7LENGTH Stage-7-style route: given order, and after EACH target return to
%   the nearest point on the survey path, then fly to the next target.
    L = 0;
    cur = startXY(:)';
    for j = 1:size(pts, 1)
        L = L + norm(pts(j, :) - cur);
        nearest = findNearestPathPoint([pts(j, :), 0], path3);
        L = L + norm(nearest(1:2) - pts(j, :));
        cur = nearest(1:2);
    end
end
