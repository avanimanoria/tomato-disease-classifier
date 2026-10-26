function grid = advActuatedDeposition(grid, cfg, legLogs, finalWorld)
%ADVACTUATEDDEPOSITION Pass-2 deposition with spray-valve delay (enhancement 'actuation').
%
%   The valve is COMMANDED open during every treatment dwell (phase 3 of target legs).
%   Without lag compensation the liquid actually flows valveDelay_s LATER: the first part
%   of the dwell is lost and spraying continues while the drone flies away (trailing
%   deposit). With lagCompensation = 1 the command is issued valveDelay_s early (during
%   the settle phase, which must be at least as long as the delay), so the physical flow
%   coincides with the dwell. Deposition does not feed back into the flight, so it is
%   evaluated after the flight from the logged states; with zero delay it reproduces the
%   in-flight deposition step for step.
%
%   grid.lagDisplacement_m: mean distance between where each spray step was commanded and
%   where it actually came out (actuator timing error, m).
    A = cfg.enhancements.actuation;
    S = cfg.internal2.spray;
    dt = cfg.dt;
    vol = S.flowRate * dt;

    pos = []; t = []; ph = []; mass = []; isT = [];
    for j = 1:numel(legLogs)
        L = legLogs{j};
        n = numel(L.t);
        pos = [pos; L.truePos]; t = [t; L.t]; ph = [ph; L.phase]; mass = [mass; L.advMass]; %#ok<AGROW>
        isT = [isT; repmat(~isnan(L.targetIdx), n, 1)]; %#ok<AGROW>
    end
    N = numel(t);
    % state AFTER each step (where the in-flight dwell function deposits)
    posN = [pos(2:end, :); finalWorld.pos];
    tN = [t(2:end); finalWorld.time];
    mN = [mass(2:end); advMass(finalWorld, cfg)];

    cmd = find(isT & ph == 3);
    d = round(A.valveDelay_s / dt);
    if A.lagCompensation, d = 0; end
    act = cmd + d;

    disp_ = zeros(numel(cmd), 1);
    if ~isfield(grid, 'evaporated_mL'), grid.evaporated_mL = 0; end
    for i = 1:numel(cmd)
        k = act(i);
        if k <= N
            p = posN(k, :); tk = tN(k); mk = mN(k);
        else                                       % flow continues after the last logged step: drone holds
            p = finalWorld.pos; tk = finalWorld.time + (k - N) * dt; mk = advMass(finalWorld, cfg);
        end
        wv = windVector(cfg, tk);
        [dr, ev] = advancedDrift(cfg, wv, mk);
        grid = advDepositKernel(grid, p, dr, vol * (1 - ev), cfg, wv);
        grid.emitted = grid.emitted + vol * ev;
        grid.evaporated_mL = grid.evaporated_mL + vol * ev;
        disp_(i) = norm(p - posN(cmd(i), :));
    end
    grid.lagDisplacement_m = mean([0; disp_]);
    if ~isempty(disp_), grid.lagDisplacement_m = mean(disp_); end
end
