function [driftDisplay, compVec] = advSprayPlan(cfg, world)
%ADVSPRAYPLAN Planned spray drift and upwind compensation for advanced runs.
%
%   The compensator knows only the MEAN wind (scaled by windEstimateScale), not the
%   gusts, and plans with the take-off mass of Pass 2. driftDisplay is the drift at
%   the mean wind (for display); the deposited drift is recomputed every spray step
%   from the instantaneous wind and current mass (advDeposit).
    W = cfg.internal2.wind;
    S = cfg.internal2.spray;
    if W.enabled
        wMean = W.speed * [cosd(W.dirDeg), sind(W.dirDeg)];
    else
        wMean = [0 0];
    end
    m = advMass(world, cfg);
    driftDisplay = advancedDrift(cfg, wMean, m);
    if S.compensate
        compVec = -advancedDrift(cfg, S.windEstimateScale * wMean, m);
    else
        compVec = [0 0];
    end
end
