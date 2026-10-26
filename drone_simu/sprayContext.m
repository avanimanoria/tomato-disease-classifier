function [windVel, driftTrue, compVec] = sprayContext(cfg)
%SPRAYCONTEXT Wind, true spray drift and the compensation offset for cfg.
%   windVel   [wx wy] m/s (zero when wind disabled)
%   driftTrue displacement of the spray cloud centre, m (sprayDriftVector)
%   compVec   offset ADDED to a target to get the release point: the negative
%             drift predicted from the drone's wind estimate
%             (windEstimateScale * windVel), or [0 0] when not compensating.
%   Shared by the integrated mission and the spray-only experiment so both use
%   one definition of drift and compensation.

    S = cfg.internal2.spray;
    windVel   = windVector(cfg, 0);
    driftTrue = sprayDriftVector(cfg, windVel);
    if S.compensate
        compVec = -sprayDriftVector(cfg, S.windEstimateScale * windVel);
    else
        compVec = [0 0];
    end
end
