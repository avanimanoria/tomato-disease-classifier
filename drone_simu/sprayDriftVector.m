function drift = sprayDriftVector(cfg, windVel)
%SPRAYDRIFTVECTOR Lateral displacement of the spray cloud centre, m.
%
%   drift = driftFactor * windVel * (releaseHeight / dropletFallSpeed)
%
%   i.e. droplets acquire a fraction of the wind velocity while settling
%   from nozzle height. SIMPLIFIED RELATIVE MODEL: constant fall speed, no
%   droplet-size distribution, no evaporation, no rotor downwash, no CFD.
%   releaseHeight, dropletFallSpeed and driftFactor are ASSUMED values
%   (config.m). Results are for comparing compensated vs uncompensated
%   spraying, not for predicting real deposition.

    S = cfg.internal2.spray;
    fallTime = S.releaseHeight / S.dropletFallSpeed;
    drift = S.driftFactor * windVel * fallTime;
end
