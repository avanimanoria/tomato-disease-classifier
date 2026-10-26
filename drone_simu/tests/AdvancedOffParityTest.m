function tests = AdvancedOffParityTest
%ADVANCEDOFFPARITYTEST All optional features disabled == legacy behaviour (bit-identical).
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    base = applyPreset(config(), 'Fully Corrected');
    evalc('f = generateIrregularField(base);');
    tc.TestData.base = base; tc.TestData.field = f;
    tc.TestData.ref = runInternal2Scenario(base, f, 'x');
end

function testDefaultsAreOff(tc)
    c = config();
    verifyFalse(tc, c.enhancements.enableAdvancedPhysics);
    verifyFalse(tc, c.enhancements.enableAdvancedRouting);
    for f = advFeatures(), verifyFalse(tc, c.enhancements.(f{1}).enabled, f{1}); end
    verifyEqual(tc, c.internal2.treat.routing, 'nearestNeighbour');
end

function testFeaturesTickedMasterOff(tc)
    c = tc.TestData.base;
    for f = advFeatures(), c.enhancements.(f{1}).enabled = true; end
    c.enhancements.localization.mode = 'kalman'; c.enhancements.guidance.mode = 'purePursuit';
    verifyTrue(tc, isequaln(runInternal2Scenario(c, tc.TestData.field, 'x'), tc.TestData.ref));
end

function testMasterOnNothingSelected(tc)
    c = tc.TestData.base; c.enhancements.enableAdvancedPhysics = true;
    verifyTrue(tc, isequaln(runInternal2Scenario(c, tc.TestData.field, 'x'), tc.TestData.ref));
end

function testAdvancedRoutingFlagAlone(tc)
    c = tc.TestData.base; c.enhancements.enableAdvancedRouting = true;
    verifyTrue(tc, isequaln(runInternal2Scenario(c, tc.TestData.field, 'x'), tc.TestData.ref));
end

function testDashboardDefaultStart(tc)
    app = AgriculturalDroneDashboardV2('Visible', 'off', 'AutoPlay', false);
    cl = onCleanup(@() delete(app));
    app.generateField(); app.startMission();
    evalc('f = generateIrregularField(applyPreset(config(), ''Baseline''));');
    r = runInternal2Scenario(applyPreset(config(), 'Baseline'), f, 'Baseline');
    verifyTrue(tc, isequaln(app.run, r), 'dashboard default START differs from the legacy engine run');
end
