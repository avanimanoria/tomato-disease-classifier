function [drift, evapFrac, fallTime] = advancedDrift(cfg, windVel, mass_kg)
%ADVANCEDDRIFT Spray-cloud displacement with the optional atmosphere model.
%
%   [drift, evapFrac, fallTime] = advancedDrift(cfg, windVel, mass_kg)
%
%   atmosphere OFF: the original sprayDriftVector (constant fall speed), evapFrac = 0.
%   atmosphere ON : one representative droplet (diameter = dropletVMD_um) falls from
%     releaseHeight with
%       fall speed  = terminal velocity(d) [drag balance, Schiller-Naumann Cd]
%                     + downwashFactor * rotor induced velocity sqrt(m g / (2 rho A))
%                       (heavier drone -> stronger downwash -> faster descent)
%       evaporation d^2(t) = d0^2 - 80 * DeltaT * t   (um^2, s; classic rule of thumb),
%                     DeltaT = dry-bulb - wet-bulb temperature (Stull 2011 wet-bulb fit)
%     drift = driftFactor * wind * fall time; evapFrac = droplet mass lost before landing
%     (1 if it evaporates completely). A single droplet size stands in for the
%     spectrum; no turbulence diffusion, no wind shear. [ASSUMED] parameters.

    S = cfg.internal2.spray;
    if ~advOn(cfg, 'atmosphere')
        drift = sprayDriftVector(cfg, windVel);
        evapFrac = 0;
        fallTime = S.releaseHeight / S.dropletFallSpeed;
        return;
    end
    A = cfg.enhancements.atmosphere;
    rhoA = cfg.enhancements.dynamics.airDensity_kgm3;
    dT = max(0, A.temperature_C - wetBulbStull(A.temperature_C, A.relHumidity_pct));
    vi = sqrt(mass_kg * 9.81 / (2 * rhoA * cfg.enhancements.energy.rotorDiskArea_m2));
    vDown = A.downwashFactor * vi;

    d0 = A.dropletVMD_um;
    d2 = d0^2;
    z = S.releaseHeight;
    t = 0;
    h = 0.005;
    while z > 0 && d2 > 25                       % below ~5 um the droplet is treated as gone
        v = terminalVelocity(sqrt(d2) * 1e-6, rhoA) + vDown;
        z = z - v * h;
        t = t + h;
        d2 = d2 - 80 * dT * h;
        if t > 60, break; end                     % safety cap
    end
    if z > 0
        evapFrac = 1;
    else
        evapFrac = 1 - (sqrt(max(d2, 0)) / d0)^3;
    end
    drift = S.driftFactor * windVel * t;
    fallTime = t;
end

function v = terminalVelocity(d, rhoA)
%TERMINALVELOCITY Water droplet terminal velocity, m/s (d in m), Schiller-Naumann drag.
    mu = 1.81e-5; rhoW = 1000; g = 9.81;
    v = rhoW * g * d^2 / (18 * mu);               % Stokes start
    for i = 1:40
        Re = max(rhoA * v * d / mu, 1e-9);
        Cd = 24 / Re * (1 + 0.15 * Re^0.687);
        vNew = sqrt(4 * g * d * rhoW / (3 * Cd * rhoA));
        if abs(vNew - v) < 1e-7, v = vNew; break; end
        v = 0.5 * (v + vNew);
    end
end

function Tw = wetBulbStull(T, RH)
%WETBULBSTULL Wet-bulb temperature (C) from air temperature (C) and RH (%), Stull (2011).
    Tw = T * atan(0.151977 * (RH + 8.313659)^0.5) + atan(T + RH) - atan(RH - 1.676331) ...
        + 0.00391838 * RH^1.5 * atan(0.023101 * RH) - 4.686035;
end
