function tests = MetricDenominatorTest
%METRICDENOMINATORTEST Metric definitions are stable and never divide by zero.
%   targetDepositionPct = 100 * spray on truly diseased canopies / emitted spray
%   offTargetPct        = 100 - targetDepositionPct = onHealthyPct + onOtherGroundPct
%   treatmentSuccess    = treated truly diseased plants / all truly diseased plants
%   recall              = TP / truly diseased; precision = TP / (TP + FP)
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    c = applyPreset(config(), 'Fully Corrected');
    evalc('f = generateIrregularField(c);');
    tc.TestData.c = c; tc.TestData.f = f;
    tc.TestData.r = runInternal2Scenario(c, f, 'x');
end

function testDefinitions(tc)
    m = computeInternal2Metrics(tc.TestData.c, tc.TestData.f, tc.TestData.r);
    s = m.spray;
    verifyEqual(tc, s.targetDepositionPct, 100 * s.useful_mL / s.emitted_mL, 'AbsTol', 1e-9);
    verifyEqual(tc, s.offTargetPct, 100 - s.targetDepositionPct, 'AbsTol', 1e-9);
    verifyEqual(tc, s.onHealthyPct + s.onOtherGroundPct, s.offTargetPct, 'AbsTol', 1e-9);
    verifyEqual(tc, s.treatmentSuccess, s.treatedTrue / m.perception.nDiseased, 'AbsTol', 1e-12);
    p = m.perception;
    verifyEqual(tc, p.recall, p.TP / p.nDiseased, 'AbsTol', 1e-12);
    verifyEqual(tc, p.precision, p.TP / (p.TP + p.FP), 'AbsTol', 1e-12);
end

function testZeroDenominators(tc)
    c = tc.TestData.c; f = tc.TestData.f;
    g = initDepositionGrid(c, f);                       % nothing emitted
    s = sprayMetrics(c, f, g, zeros(0, 1));
    vals = [s.targetDepositionPct, s.offTargetPct, s.treatmentSuccess, s.meanTargetDoseFraction, s.deliveryOfDetected];
    verifyTrue(tc, all(isfinite(vals) | isnan(vals)), 'Inf produced by a zero denominator');
    verifyFalse(tc, any(isinf(vals)));
    seen = false(height(f.plants), 1);
    tg = struct('plantIdx', zeros(0, 1), 'ID', strings(0, 1), 'XY', zeros(0, 2), 'detectTime', zeros(0, 1), 'isTruePositive', false(0, 1));
    pm = perceptionMetrics(f, seen, tg);
    verifyFalse(tc, any(isinf([pm.recall, pm.precision])));
    verifyTrue(tc, isnan(safeDiv(1, 0)), 'safeDiv: empty denominator must be NaN (visible), not 0 or Inf');
end
