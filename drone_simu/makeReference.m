function ref = makeReference(pts)
%MAKEREFERENCE Build a polyline reference with arclength parametrisation.
%   ref = makeReference(pts) where pts is Nx2 [X Y]. Consecutive duplicate
%   points are dropped. A degenerate (zero-length) reference is kept as two
%   identical points with ref.len = 0 and tangent [1 0].
%
%   Fields: pts (Mx2), cs (Mx1 cumulative arclength), len, segTau (M-1 x 2
%   unit tangents).

    pts = pts(:, 1:2);
    if size(pts,1) > 1
        keep = [true; vecnorm(diff(pts,1,1), 2, 2) > 1e-9];
        pts = pts(keep, :);
    end
    if size(pts,1) < 2
        pts = [pts(1,:); pts(1,:)];
        ref.pts = pts;
        ref.cs = [0; 0];
        ref.len = 0;
        ref.segTau = [1 0];
        return;
    end

    d = diff(pts, 1, 1);
    segLen = vecnorm(d, 2, 2);
    ref.pts = pts;
    ref.cs = [0; cumsum(segLen)];
    ref.len = ref.cs(end);
    ref.segTau = d ./ segLen;
end
