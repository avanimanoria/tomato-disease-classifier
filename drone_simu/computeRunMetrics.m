function T = computeRunMetrics(res)
%COMPUTERUNMETRICS Per-run metric table (Group, Metric, Value, Unit) for one pipeline run.
%
%   Evaluation view: uses ground truth for scoring (detector precision/recall, treated
%   diseased plants, deposition on truly diseased canopies, estimator error). Never fed back
%   into a mission. Metrics that do not apply to the run are NaN with a note in Unit.
    m = res.metrics; r = res.run; f = res.field; c = res.cfg;
    p = m.perception; s = m.spray;
    rows = {};
    add('Perception', 'Plants observed', p.nSeen, 'plants');
    add('Perception', 'Plants observed', 100 * p.observationRate, '% of all plants');
    add('Perception', 'Targets flagged (TP + FP)', p.TP + p.FP, 'plants');
    add('Perception', 'Detector precision', 100 * nz(p.precision), '%');
    add('Perception', 'Detector recall', 100 * nz(p.recall), '% of truly diseased');
    pr = nz(p.precision); rc = nz(p.recall);
    add('Perception', 'Detector F1', 100 * safeDiv(2 * pr * rc, pr + rc), '%');
    add('Perception', 'Diseased plants missed (FN)', p.FN, 'plants');
    cv = coverageMetrics(f, c, r);
    add('Coverage', 'Plants imaged (recall)', cv.plantRecall_pct, '% of all plants');
    add('Coverage', 'Field area imaged', cv.areaCoverage_pct, '% of free area');
    add('Coverage', 'Missed area', cv.missedArea_m2, 'm^2');
    add('Coverage', 'Planned survey length', cv.plannedLength_m, 'm');
    add('Coverage', 'Turns (> 45 deg)', cv.turns, 'turns');
    add('Coverage', 'Cells', cv.nCells, 'cells');
    add('Coverage', 'Survey boundary / obstacle violation', cv.boundaryViolation_pct, '% of Pass-1 steps');
    add('Coverage', 'Obstacle incursion (both passes)', cv.obstacleIncursion_pct, '% of steps');
    add('Coverage', 'Planned path feasible', cv.plannedFeasible, '1 = inside free field');
    add('Coverage', 'Planned min clearance', cv.minClearance_m, 'm (0 if infeasible)');
    add('Navigation', 'Survey cross-track RMSE', m.survey.crossRMSE, 'm');
    add('Navigation', 'Survey max deviation', m.survey.crossMaxAbs, 'm');
    add('Navigation', 'Transit cross-track RMSE', m.transit.crossRMSE, 'm');
    allPos = [r.log1.truePos; cell2mat(cellfun(@(L) L.truePos, r.legLogs(:), 'UniformOutput', false))];
    add('Navigation', 'Time outside field boundary', 100 * mean(~inpolygon(allPos(:, 1), allPos(:, 2), f.polygon(:, 1), f.polygon(:, 2))), '% of steps');
    if isfield(r, 'advanced') && advOn(c, 'localization')
        add('Localization', 'Estimate error RMSE', r.advanced.estErrRMS_m, 'm');
        add('Localization', 'Estimate error max', r.advanced.estErrMax_m, 'm');
        add('Localization', 'NEES (consistency, ~2 ideal)', r.advanced.estNEES, '-');
    else
        add('Localization', 'Estimate error RMSE', 0, 'm (ground-truth oracle)');
    end
    add('Treatment', 'Diseased plants treated', s.treatedTrue, 'plants');
    add('Treatment', 'Treatment success', 100 * s.treatmentSuccess, '% of truly diseased');
    add('Treatment', 'Healthy plants sprayed', s.healthyPlantsHit, 'plants');
    add('Spray', 'Target deposition', s.targetDepositionPct, '% of emitted');
    add('Spray', 'Off-target deposition', s.offTargetPct, '% of emitted');
    [XX, YY] = meshgrid(r.grid.xv, r.grid.yv);
    inF = inpolygon(XX, YY, f.polygon(:, 1), f.polygon(:, 2));
    add('Spray', 'Deposited outside field', 100 * safeDiv(sum(r.grid.mass(~inF)), r.grid.emitted), '% of emitted');
    add('Spray', 'Liquid emitted', s.emitted_mL / 1000, 'L');
    if isfield(r, 'advanced')
        add('Spray', 'Evaporated', r.advanced.evaporatedPct, '% of emitted');
        add('Spray', 'Valve-delay displacement', r.advanced.lagDisplacement_m, 'm');
        add('Resources', 'Refill trips', r.advanced.refills, 'trips');
    end
    rt = r.routes;
    switch rt.routing
        case 'fixedOrder', g = rt.detOrderLength;
        case 'nearestNeighbour', g = rt.nnLength;
        case 'stage7Return', g = rt.stage7Length;
        otherwise, g = rt.advancedLength;
    end
    add('Routing', 'Planned (geometric) Pass-2 route', g, 'm');
    add('Routing', 'Flown Pass-2 distance', rt.actualDistance, 'm');
    add('Resources', 'Mission time', r.finalWorld.time, 's');
    add('Resources', 'Survey (Pass 1) distance', m.pass1.distance, 'm');
    if isfield(r, 'advanced') && advOn(c, 'energy')
        add('Resources', 'Energy used', r.advanced.energy_Wh, 'Wh');
        add('Resources', 'Battery left', r.advanced.batteryLeftPct, '%');
        feas = r.advanced.batteryLeftPct >= c.enhancements.energy.reservePct;
        add('Feasibility', 'Battery reserve respected', double(feas), '1 = yes');
    else
        add('Resources', 'Energy used', NaN, 'Wh (energy model off)');
    end
    add('Feasibility', 'Mission completed', 1, '1 = yes');
    add('Compute', 'Simulation wall time', res.wallTime_s, 's');
    T = cell2table(rows, 'VariableNames', {'Group', 'Metric', 'Value', 'Unit'});

    function add(g, n, v, u)
        rows(end+1, :) = {string(g), string(n), double(v), string(u)};
    end
end

function v = nz(x)
    if isnan(x), v = 0; else, v = x; end
end
