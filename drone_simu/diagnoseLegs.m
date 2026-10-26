function D = diagnoseLegs(cfg, field, routing, speedFactor)
%DIAGNOSELEGS Per-leg decomposition of flown vs geometric distance for one Pass-2 strategy
%   on the frozen all-diseased target set. Diagnostic only: changes nothing.
%   Per leg: geometric length (actual leg start -> leg end), integration steps,
%   measured distance (steps*v*dt), excess. Summary splits approach vs return and
%   separates (a) step quantization from (b) start-position carry-over vs the
%   release-point prediction of routeLengths.
    cfg.internal2.enabled = true;
    cfg.internal2.treat.routing = routing;
    cfg.internal2.treat.speedFactor.(routing) = speedFactor;
    P = field.plants; idx = frozenTargetOrder(field);
    t = struct('plantIdx', idx, 'ID', P.ID(idx), 'XY', [P.X(idx), P.Y(idx)], ...
        'detectTime', zeros(numel(idx), 1), 'isTruePositive', true(numel(idx), 1));
    run = runInternal2Scenario(cfg, field, routing, struct('targets', t));
    step = cfg.droneSpeed * speedFactor * cfg.dt;
    n = numel(run.legLogs);
    kind = strings(n, 1); geom = zeros(n, 1); steps = zeros(n, 1);
    for j = 1:n
        L = run.legLogs{j};
        steps(j) = nnz(L.phase == 1);
        p0 = L.estPos(1, :);
        if isnan(L.targetIdx)
            kind(j) = "return";
            q = findNearestPathPoint([run.releasePts(run.legLogs{j-1}.targetIdx, :), 0], field.surveyPath3);
            p1 = q(1:2);
        else
            kind(j) = "approach";
            p1 = run.releasePts(L.targetIdx, :);
        end
        geom(j) = norm(p1 - p0);
    end
    meas = steps * step;
    D.legs = table((1:n)', kind, geom, steps, meas, meas - geom, ...
        'VariableNames', {'leg', 'kind', 'geometric_m', 'steps', 'measured_m', 'overshoot_m'});
    pred = run.routes.(struct('fixedOrder', 'detOrderLength', 'nearestNeighbour', 'nnLength', 'stage7Return', 'stage7Length').(routing));
    D.step_m = step;
    D.maxQuantizationPerLeg_m = step;
    D.totalMeasured = run.routes.actualDistance;
    D.sumMeasuredLegs = sum(meas);
    D.sumGeomLegs = sum(geom);
    D.predictedRelease = pred;
    D.totalDiscrepancy = D.totalMeasured - pred;
    D.quantization = sum(meas - geom);
    D.carryOver = sum(geom) - pred;
    for k = ["approach", "return"]
        m = kind == k;
        D.(k) = struct('nLegs', nnz(m), 'geometric', sum(geom(m)), 'measured', sum(meas(m)), 'excess', sum(meas(m) - geom(m)), ...
            'maxOvershoot', max([0; meas(m) - geom(m)]), 'minOvershoot', min([0; meas(m) - geom(m)]));
    end
    fprintf('%-18s sf=%.1f step=%.3f | legs %d | measured %.3f (sum legs %.3f) | predicted(release) %.3f | discrepancy %.3f\n', ...
        routing, speedFactor, step, n, D.totalMeasured, D.sumMeasuredLegs, pred, D.totalDiscrepancy);
    fprintf('   (a) quantization  sum(measured_leg - geom_leg) = %.3f  [approach %.3f over %d legs, return %.3f over %d legs; per-leg range %.3f..%.3f, bound step=%.3f]\n', ...
        D.quantization, D.approach.excess, D.approach.nLegs, D.return.excess, D.return.nLegs, ...
        min(D.legs.overshoot_m), max(D.legs.overshoot_m), step);
    fprintf('   (b) start carry-over  sum(geom_legs) - predicted = %.3f\n', D.carryOver);
    fprintf('   (a)+(b) = %.3f vs discrepancy %.3f (residual %.2e)\n', D.quantization + D.carryOver, D.totalDiscrepancy, D.totalDiscrepancy - D.quantization - D.carryOver);
end
