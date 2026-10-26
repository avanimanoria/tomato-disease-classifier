function tests = SeedReproducibilityTest
%SEEDREPRODUCIBILITYTEST Same configuration + seeds -> identical run; each seed is tracked.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    c = applyPreset(config(), 'Fully Corrected');
    c.enhancements.enableAdvancedPhysics = true;
    c.enhancements.gusts.enabled = true;
    c.enhancements.localization.enabled = true; c.enhancements.localization.mode = 'kalman';
    tc.TestData.c = c;
end

function testIdenticalRepeat(tc)
    c = tc.TestData.c;
    evalc('f = generateIrregularField(c);');
    verifyTrue(tc, isequaln(runInternal2Scenario(c, f, 'x'), runInternal2Scenario(c, f, 'x')));
end

function testFieldSeedChangesGroundTruth(tc)
    c1 = tc.TestData.c; c2 = c1; c2.internal2.seed = c1.internal2.seed + 1;
    evalc('f1 = generateIrregularField(c1); f2 = generateIrregularField(c2);');
    verifyFalse(tc, isequal(f1.plants.TrueDisease, f2.plants.TrueDisease));
    evalc('f1b = generateIrregularField(c1);');
    verifyTrue(tc, isequaln(f1, f1b));
end

function testGustSeedChangesWindTrace(tc)
    c1 = tc.TestData.c; c2 = c1; c2.enhancements.gusts.seed = c1.enhancements.gusts.seed + 1;
    t = 0:0.5:60;
    w1 = cell2mat(arrayfun(@(x) windVector(c1, x), t', 'UniformOutput', false));
    w2 = cell2mat(arrayfun(@(x) windVector(c2, x), t', 'UniformOutput', false));
    w1b = cell2mat(arrayfun(@(x) windVector(c1, x), t', 'UniformOutput', false));
    verifyFalse(tc, isequal(w1, w2));
    verifyTrue(tc, isequal(w1, w1b));
end

function testLocalizationSeedTracked(tc)
    c1 = tc.TestData.c; c2 = c1; c2.enhancements.localization.seed = c1.enhancements.localization.seed + 10;
    evalc('f = generateIrregularField(c1);');
    r1 = runInternal2Scenario(c1, f, 'x'); r2 = runInternal2Scenario(c2, f, 'x');
    verifyNotEqual(tc, r1.advanced.estErrRMS_m, r2.advanced.estErrRMS_m);
end
