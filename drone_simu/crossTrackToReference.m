function [cross, dist] = crossTrackToReference(ref, p, s, window)
%CROSSTRACKTOREFERENCE Signed cross-track error of point p to the active
%   part of a reference polyline.
%
%   [cross, dist] = crossTrackToReference(ref, p, s, window)
%   Only segments overlapping the arclength window [s-window, s+window]
%   are considered, so a drone that has drifted toward a neighbouring row
%   is still measured against the row it is SUPPOSED to be on.
%   cross > 0 means p is to the LEFT of the reference direction of travel.
%   dist = abs(cross) for the closest projection (distance to the segment).

    nSeg = size(ref.segTau, 1);
    if ref.len <= 0
        d = p(:)' - ref.pts(1, :);
        cross = 0;
        dist = norm(d);
        return;
    end

    segStart = ref.cs(1:nSeg);
    segEnd   = ref.cs(2:nSeg+1);
    cand = find(segEnd >= s - window & segStart <= s + window);
    if isempty(cand)
        cand = (1:nSeg)';
    end

    bestDist = inf;
    cross = 0;
    for k = cand'
        a = ref.pts(k, :);
        b = ref.pts(k+1, :);
        ab = b - a;
        t = dot(p(:)' - a, ab) / dot(ab, ab);
        t = min(max(t, 0), 1);
        q = a + t * ab;
        dd = norm(p(:)' - q);
        if dd < bestDist
            bestDist = dd;
            tau = ref.segTau(k, :);
            nrm = [-tau(2), tau(1)];
            cross = dot(p(:)' - q, nrm);
        end
    end
    dist = bestDist;
end
