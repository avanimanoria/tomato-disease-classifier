function m = advMass(world, cfg)
%ADVMASS Current take-off mass, kg = dry mass + liquid in the tank.
    P = cfg.enhancements.payload;
    m = P.dryMass_kg + world.adv.liquid_L * P.liquidDensity_kgL;
end
