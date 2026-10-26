function [pos, tau] = sampleReference(ref, s)
%SAMPLEREFERENCE Position and unit tangent of a reference at arclength s.
%   s is clamped to [0, ref.len]. At the end, the last segment's tangent is
%   returned.

    s = min(max(s, 0), ref.len);
    nSeg = size(ref.segTau, 1);

    if ref.len <= 0
        pos = ref.pts(1, :);
        tau = ref.segTau(1, :);
        return;
    end

    idx = find(ref.cs <= s, 1, 'last');
    idx = min(idx, nSeg);
    segLen = ref.cs(idx+1) - ref.cs(idx);
    frac = (s - ref.cs(idx)) / segLen;
    pos = ref.pts(idx, :) + frac * (ref.pts(idx+1, :) - ref.pts(idx, :));
    tau = ref.segTau(idx, :);
end
