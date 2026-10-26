function cfg = applyAdvancedDerived(cfg)
%APPLYADVANCEDDERIVED Parameters that become functions of flight altitude (enhancement 'perception').
%
%   perception ON:
%     flightAltitude      = perception.altitude_m
%     cameraFovRadius     = altitude * tand(cameraHalfFOV_deg)       (footprint grows with height)
%     spray.releaseHeight = altitude - canopyHeight_m (min 0.2 m)    (higher -> more drift, wider spray)
%     detect.pDetectDiseased scaled by exp(-max(0, altitude - detectRefAltitude_m) / detectAltitudeScale_m)
%       (coarser ground resolution above the reference altitude)
%   Defaults (2 m, atand(0.3), 1 m canopy) reproduce the original 0.6 m footprint and
%   1.0 m release height. With perception OFF nothing is changed.

    if ~advOn(cfg, 'perception'), return; end
    P = cfg.enhancements.perception;
    alt = P.altitude_m;
    cfg.flightAltitude = alt;
    cfg.cameraFovRadius = alt * tand(P.cameraHalfFOV_deg);
    cfg.internal2.spray.releaseHeight = max(0.2, alt - P.canopyHeight_m);
    cfg.internal2.detect.pDetectDiseased = cfg.internal2.detect.pDetectDiseased ...
        * exp(-max(0, alt - P.detectRefAltitude_m) / P.detectAltitudeScale_m);
end
