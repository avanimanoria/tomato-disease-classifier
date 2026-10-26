function path = generateZigZagPath(cfg, fieldInfo)
%GENERATEZIGZAGPATH Build the boustrophedon (zig-zag) waypoint list.
%   (Section 6)
%
%   path = generateZigZagPath(cfg, fieldInfo) returns an Nx3 matrix of
%   [X, Y, Z] CORNER waypoints only. Stage 2 will interpolate small
%   steps between these corners so the drone moves continuously instead
%   of teleporting (Section 7).

    numRows = fieldInfo.numRows;
    L = cfg.fieldLength;
    Z = cfg.flightAltitude;

    waypoints = zeros(numRows*2, 3);
    wIdx = 1;

    for r = 0:(numRows-1)
        yPos = r * cfg.rowSpacing;
        if mod(r,2) == 0
            % even row: sweep forward, X: 0 -> L
            xStart = 0; xEnd = L;
        else
            % odd row: sweep backward, X: L -> 0
            xStart = L; xEnd = 0;
        end

        waypoints(wIdx,:)   = [xStart, yPos, Z];
        waypoints(wIdx+1,:) = [xEnd,   yPos, Z];
        wIdx = wIdx + 2;
    end

    path = waypoints;
end
