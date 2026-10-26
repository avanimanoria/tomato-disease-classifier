function warns = checkProfileFeasibility(cfg)
%CHECKPROFILEFEASIBILITY Physical sanity checks of the hardware parameters in cfg.enhancements.
%   Hover power from momentum theory (the same model as the 'energy' feature):
%     P = (m g)^1.5 / sqrt(2 rho A) / efficiency + avionics, at full tank.
%   Warnings: thrust/weight at full tank < 1.3 (no control margin); usable endurance at full
%   tank < 5 min; liquid mass > 1.5 x dry mass; disk loading > 400 N/m^2.
    E = cfg.enhancements; g = 9.81;
    m = E.payload.dryMass_kg + E.payload.tankCapacity_L * E.payload.liquidDensity_kgL;
    A = E.energy.rotorDiskArea_m2; rho = E.dynamics.airDensity_kgm3;
    P = (m * g)^1.5 / sqrt(2 * rho * A) / E.energy.efficiency + E.energy.avionics_W;
    endur = E.energy.battery_Wh * (1 - E.energy.reservePct / 100) / P * 60;
    warns = {};
    if E.dynamics.thrustToWeightFull < 1.3
        warns{end+1} = sprintf('thrust/weight at full tank %.2f < 1.3: no manoeuvre / gust margin', E.dynamics.thrustToWeightFull);
    end
    if endur < 5
        warns{end+1} = sprintf('usable hover endurance at full tank %.1f min < 5 min (hover power %.0f W)', endur, P);
    end
    if E.payload.tankCapacity_L * E.payload.liquidDensity_kgL > 1.5 * E.payload.dryMass_kg
        warns{end+1} = 'liquid payload exceeds 1.5 x dry mass: check the maximum take-off mass';
    end
    if m * g / A > 400
        warns{end+1} = sprintf('disk loading %.0f N/m^2 > 400: unusually high for a multirotor', m * g / A);
    end
end
