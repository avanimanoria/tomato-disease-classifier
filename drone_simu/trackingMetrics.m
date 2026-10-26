function s = trackingMetrics(cross, posErr)
%TRACKINGMETRICS Path-following statistics. Two DISTINCT quantities:
%
%   cross  : signed cross-track error, m = distance from the TRUE position to
%            the active segment of the reference polyline. Measures alignment
%            with the intended coverage trajectory (rows, curves and turns).
%            -> crossRMSE, crossMeanAbs, crossMaxAbs
%   posErr : Euclidean distance to the TIME-INDEXED reference point, m. Also
%            contains along-track (timing) error, so it behaves differently
%            from cross-track around turns and curved rows.
%            -> posRMSE, posMax
%
%   Both are always reported; neither is a substitute for the other.

    if isempty(cross)
        s = struct('crossRMSE', NaN, 'crossMeanAbs', NaN, 'crossMaxAbs', NaN, ...
                   'posRMSE', NaN, 'posMax', NaN);
        return;
    end
    s.crossRMSE    = sqrt(mean(cross.^2));
    s.crossMeanAbs = mean(abs(cross));
    s.crossMaxAbs  = max(abs(cross));
    s.posRMSE      = sqrt(mean(posErr.^2));
    s.posMax       = max(posErr);
end
