function g = advDeposit(g, w, cfg)
%ADVDEPOSIT One spray timestep for advanced runs: instantaneous wind (incl. gusts), current mass.
%   Evaporated volume counts as emitted but is not deposited (g.evaporated_mL).
    S = cfg.internal2.spray;
    vol = S.flowRate * cfg.dt;
    [dr, ev] = advancedDrift(cfg, windVector(cfg, w.time), advMass(w, cfg));
    g = depositSpray(g, w.pos, dr, vol * (1 - ev), cfg);
    g.emitted = g.emitted + vol * ev;
    if ~isfield(g, 'evaporated_mL'), g.evaporated_mL = 0; end
    g.evaporated_mL = g.evaporated_mL + vol * ev;
end
