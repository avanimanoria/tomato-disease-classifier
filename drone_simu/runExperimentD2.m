function res = runExperimentD2(cfg, field)
%RUNEXPERIMENTD2 Experiment D2: spray compensation with an IMPERFECT wind estimate.
%
%   res = runExperimentD2(cfg, field)
%
%   Same spray-only setup as Experiment D (hover over every truly diseased plant,
%   no navigation/detector/randomness; physics untouched). The TRUE wind drives
%   the spray cloud; the compensator uses the ESTIMATE  What = alpha * W
%   (alpha = cfg.internal2.spray.windEstimateScale, swept here):
%     alpha = 0 no compensation | <1 underestimate | 1 perfect | >1 overestimate.
%   Swept over alpha (cfg.experiments.D2.alphas) x the Experiment-D wind speeds.
%
%   Primary outputs: residualOffset_m = |true drift + compensation| (where the
%   spray centre lands relative to the plant) -> targetDepositionPct, with
%   offTargetPct secondary. treatedTrue/treatmentSuccess are kept in the table
%   but are a thresholded, assumption-sensitive metric and not the headline.
%   Because drift and compensation are both linear in wind, residual =
%   |1 - alpha| * driftDistance. residualAlongWind_m is signed: > 0 means the
%   spray lands downwind of the plant (under-compensation), < 0 upwind.

    alphas = cfg.experiments.D2.alphas(:)';
    winds  = cfg.experiments.D.windSpeeds(:)';
    S = cfg.internal2.spray;
    idx = frozenTargetOrder(field);
    P = field.plants;
    XY = [P.X(idx), P.Y(idx)];

    rows = {};
    for a = alphas
        for ws = winds
            c = applyScenario(cfg, true, false, true, ws);
            c.internal2.spray.windEstimateScale = a;
            [~, drift, compVec] = sprayContext(c);
            release = XY + compVec;
            grid = initDepositionGrid(c, field);
            for j = 1:size(release, 1)
                grid = depositSpray(grid, release(j, :), drift, S.flowRate * S.duration, c);
            end
            sm = sprayMetrics(c, field, grid, idx);
            resid = drift + compVec;
            if norm(drift) > 0
                along = dot(resid, drift / norm(drift));
            else
                along = 0;
            end
            rows{end+1, 1} = struct( ... %#ok<AGROW>
                'windEstimateScale', a, 'windSpeed_mps', ws, ...
                'driftDistance_m', norm(drift), ...
                'compensationOffset_m', norm(compVec), ...
                'residualOffset_m', norm(resid), ...
                'residualAlongWind_m', along, ...
                'targetDepositionPct', sm.targetDepositionPct, ...
                'offTargetPct', sm.offTargetPct, ...
                'onHealthyPct', sm.onHealthyPct, ...
                'onOtherGroundPct', sm.onOtherGroundPct, ...
                'meanTargetDoseFraction', sm.meanTargetDoseFraction, ...
                'useful_mL', sm.useful_mL, 'emitted_mL', sm.emitted_mL, ...
                'treatedTrue', sm.treatedTrue, 'treatmentSuccess', sm.treatmentSuccess, ...
                'healthyPlantsHit', sm.healthyPlantsHit);
        end
    end
    res.table = struct2table(vertcat(rows{:}));
    res.settings = cfg.experiments.D2;
    res.footprintRadius_m = S.releaseHeight * tand(S.nozzleHalfAngle);
    res.canopyRadius_m = cfg.internal2.metrics.canopyRadius;

    % consistency with Experiment D (same code path): alpha = 1 must equal D's compensated
    % rows and alpha = 0 its uncompensated rows, bit for bit.
    D = runExperimentD(cfg, field);
    ok = true;
    for k = 1:height(D.table)
        a = double(D.table.compensated(k));
        if ~any(alphas == a), continue; end
        m = res.table.windEstimateScale == a & res.table.windSpeed_mps == D.table.windSpeed_mps(k);
        ok = ok && isequaln(res.table.useful_mL(m), D.table.useful_mL(k)) ...
                && isequaln(res.table.targetDepositionPct(m), D.table.targetDepositionPct(k));
    end
    res.consistentWithD = ok;
    res.determinismOK = ok;
end
