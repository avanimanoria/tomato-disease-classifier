function res = runExperimentD(cfg, field)
%RUNEXPERIMENTD Experiment D: spray-only wind sweep, uncompensated vs compensated.
%
%   res = runExperimentD(cfg, field)
%
%   The drone hovers EXACTLY at the release point of every truly diseased
%   plant (frozenTargetOrder): the plant itself, or the plant shifted upwind
%   by the compensation offset. No navigation, no PID, no detector, no
%   random numbers - only the spray model is under test. Each (wind speed,
%   compensation) condition accumulates all targets on one grid, as in the
%   integrated mission, and is scored with sprayMetrics.
%
%   The MODELLED spray drift distance (m) is recorded for every wind speed
%   (driftDistance_m) together with the residual offset between where the
%   spray lands and the target (residualOffset_m = |drift + compensation|).
%   Because wind-to-drift is an assumed parameter chain, drift distance - not
%   wind speed - is the physically interpretable x-variable of these results.
%
%   One spray event is deposited as a single call with volume flowRate*duration
%   (identical to the mission's duration/dt steps for a stationary nozzle);
%   res.hoverEquivalenceRelErr verifies this against the step loop.

    E = cfg.experiments.D;
    S = cfg.internal2.spray;
    idx = frozenTargetOrder(field);
    P = field.plants;
    XY = [P.X(idx), P.Y(idx)];

    rows = {};
    for comp = [false true]
        for ws = E.windSpeeds(:)'
            c = applyScenario(cfg, true, false, comp, ws);
            [~, drift, compVec] = sprayContext(c);
            release = XY + compVec;

            grid = initDepositionGrid(c, field);
            for j = 1:size(release, 1)
                grid = depositSpray(grid, release(j, :), drift, S.flowRate * S.duration, c);
            end
            sm = sprayMetrics(c, field, grid, idx);

            rows{end+1, 1} = struct( ... %#ok<AGROW>
                'windSpeed_mps', ws, ...
                'compensated', double(comp), ...
                'driftDistance_m', norm(drift), ...
                'compensationOffset_m', norm(compVec), ...
                'residualOffset_m', norm(drift + compVec), ...
                'footprintRadius_m', S.releaseHeight * tand(S.nozzleHalfAngle), ...
                'canopyRadius_m', cfg.internal2.metrics.canopyRadius, ...
                'nTargets', numel(idx), ...
                'treatedTrue', sm.treatedTrue, ...
                'treatmentSuccess', sm.treatmentSuccess, ...
                'meanTargetDoseFraction', sm.meanTargetDoseFraction, ...
                'targetDepositionPct', sm.targetDepositionPct, ...
                'offTargetPct', sm.offTargetPct, ...
                'onHealthyPct', sm.onHealthyPct, ...
                'onOtherGroundPct', sm.onOtherGroundPct, ...
                'healthyPlantsHit', sm.healthyPlantsHit, ...
                'emitted_mL', sm.emitted_mL, ...
                'useful_mL', sm.useful_mL, ...
                'wasted_mL', sm.wasted_mL);
        end
    end
    res.table = struct2table(vertcat(rows{:}));
    res.settings = E;
    res.targetPlantIdx = idx;
    res.hoverEquivalenceRelErr = hoverEquivalence(cfg, field, XY(1, :));
    res.determinismOK = rerunMatches(cfg, field, idx, XY, res.table);
end

function relErr = hoverEquivalence(cfg, field, xy)
%HOVEREQUIVALENCE Single deposit call vs the mission's per-step dwell loop.
    S = cfg.internal2.spray;
    c = applyScenario(cfg, true, false, false, cfg.internal2.wind.speed);
    [~, drift] = sprayContext(c);
    gA = depositSpray(initDepositionGrid(c, field), xy, drift, S.flowRate * S.duration, c);
    gB = initDepositionGrid(c, field);
    nSteps = round(S.duration / c.dt);
    for k = 1:nSteps
        gB = depositSpray(gB, xy, drift, S.flowRate * c.dt, c);
    end
    relErr = max(abs(gA.mass(:) - gB.mass(:))) / max(gA.mass(:));
end

function ok = rerunMatches(cfg, field, idx, XY, T)
%RERUNMATCHES Re-run the last (compensated, largest wind) condition and compare.
    S = cfg.internal2.spray;
    ws = cfg.experiments.D.windSpeeds(end);
    c = applyScenario(cfg, true, false, true, ws);
    [~, drift, compVec] = sprayContext(c);
    grid = initDepositionGrid(c, field);
    for j = 1:size(XY, 1)
        grid = depositSpray(grid, XY(j, :) + compVec, drift, S.flowRate * S.duration, c);
    end
    sm = sprayMetrics(c, field, grid, idx);
    sel = T.compensated == 1 & T.windSpeed_mps == ws;
    ok = isequal(T.useful_mL(sel), sm.useful_mL) && isequal(T.treatedTrue(sel), sm.treatedTrue);
end
