function tests = ExperimentFAuditTest
%EXPERIMENTFAUDITTEST Frozen Experiment F reconciles exactly and shows no train/test leakage.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    evalc('A = auditExperimentF(tc.TestData.p);');
    tc.TestData.A = A;
end

function testCountsReconcile(tc)
    c = tc.TestData.A.counts;
    verifyEqual(tc, c.total, 623);
    verifyEqual(tc, c.total, c.reportedTotal);
    verifyEqual(tc, [c.routing, c.pipeline, c.altKernel, c.ablation], [35 432 144 12]);
    verifyEqual(tc, c.replicatesPerCell, 1);
end

function testNoLeakage(tc)
    A = tc.TestData.A;
    verifyTrue(tc, A.bestFixedMatches, 'best fixed is not reproducible from TRAIN rows only');
    verifyTrue(tc, A.selectorMatchesTrainOnly, 'selector choices are not reproducible from TRAIN rows only');
    verifyTrue(tc, A.pairingComplete, 'a (field, condition) cell is missing configurations');
end

function testFrozenRunIsProtected(tc)
    verifyError(tc, @() runExperimentF(), 'runExperimentF:frozen');
end
