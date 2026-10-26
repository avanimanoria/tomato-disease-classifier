function tests = TruthFirewallTest
%TRUTHFIREWALLTEST Truth is used only to generate sensors and to score - never by the estimator,
%   controller or planner when localization.mode = 'sensorFusion' (manual Phase 4).
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    c = applyPreset(config(), 'Fully Corrected');
    c.enhancements.enableAdvancedPhysics = true;
    c.enhancements.localization.enabled = true;
    c.enhancements.localization.mode = 'sensorFusion';
    f = quietField(c);
    tc.TestData.cfg = c; tc.TestData.field = f;
    tc.TestData.run = runInternal2Scenario(c, f, 'sf');
end

function testEstimateIgnoresTruePosition(tc)
    c = tc.TestData.cfg;
    w.pos = [3 4]; w.adv = initAdvancedWorld(struct('pos', [3 4]), c).adv;
    w.adv.sf.x(1:2) = [10; 11];
    e1 = getEstimatedState(w, c);
    w.pos = [-50 70];                                   % move the TRUE drone; estimator state unchanged
    e2 = getEstimatedState(w, c);
    verifyEqual(tc, e1.pos, [10 11]);
    verifyEqual(tc, e2.pos, e1.pos);
    verifyEqual(tc, e2.source, "EKF_SENSOR_FUSION");
end

function testEstimatorHasNoTruthInput(tc)
    verifyEqual(tc, nargin('sensorFusionStep'), 3);     % (sf, meas, cfg)
    src = fileread(which('sensorFusionStep'));
    code = regexprep(src, '%[^\n]*', '');              % strip comments
    verifyEmpty(tc, regexp(code, '\<(world|truePos|posTrue|vTrue|aTrue)\>', 'once'));
end

function testControllerReadsEstimateOnly(tc)
    code = regexprep(fileread(which('flyReference')), '%[^\n]*', '');
    verifyNotEmpty(tc, regexp(code, 'est\s*=\s*getEstimatedState\(world', 'once'));
    verifyEmpty(tc, regexp(code, 'Controller\([^)]*world\.pos', 'once'), 'controller must not receive world.pos');
end

function testEstimatorIsAccurateAndConsistentEnough(tc)
    A = tc.TestData.run.advanced;
    verifyLessThan(tc, A.estErrRMS_m, 0.2);
    verifyGreaterThan(tc, A.estErrRMS_m, 0);            % it is a real estimate, not truth
    verifyLessThan(tc, A.estNEES, 10);                  % ideal ~2; documented as mildly overconfident
    verifyLessThan(tc, A.sensorFusion.rejectionPct, 5);
    verifyGreaterThan(tc, A.sensorFusion.rangeUpdates, 0);
    verifyGreaterThan(tc, A.sensorFusion.flowDropouts, 0);
end

function testGeolocatedTargetsUseEstimate(tc)
    c = tc.TestData.cfg; c.enhancements.localization.geolocateTargets = 1;
    r = runInternal2Scenario(c, tc.TestData.field, 'geo');
    r0 = tc.TestData.run;
    verifyEqual(tc, r.targets.plantIdx, r0.targets.plantIdx);      % same plants flagged (scoring by identity)
    verifyEqual(tc, r.targets.XYtrue, r0.targets.XY);
    verifyGreaterThan(tc, max(vecnorm(r.targets.XY - r.targets.XYtrue, 2, 2)), 0);
    verifyTrue(tc, isequaln(r.log1, r0.log1));                      % Pass 1 untouched
end

function testGeolocationOffByDefault(tc)
    verifyEqual(tc, config().enhancements.localization.geolocateTargets, 0);
    verifyFalse(tc, isfield(tc.TestData.run.targets, 'XYtrue'));
    pc = pipelineDefaults();
    verifyFalse(tc, pc.pipeline.geolocateTargets);
end

function testPipelineWiresGeolocation(tc)
    pc = pipelineDefaults(); pc.pipeline.localization = 'sensorFusion'; pc.pipeline.geolocateTargets = true;
    cfg = resolvePipeline(pc);
    verifyEqual(tc, cfg.enhancements.localization.mode, 'sensorFusion');
    verifyEqual(tc, cfg.enhancements.localization.geolocateTargets, 1);
    pc.pipeline.localization = 'groundTruthOracle';
    [~, ~, warns] = validatePipeline(pc);
    verifyTrue(tc, any(contains(warns, 'no effect')));
end

function testProxyIsLabelled(tc)
    R = pipelineRegistry();
    T = R.localization;
    verifyEqual(tc, T.status{strcmp(T.id, 'errorModel')}, 'proxy');
    verifyTrue(tc, T.available(strcmp(T.id, 'sensorFusion')));
end

function f = quietField(c)
    evalc('f = generateIrregularField(c);');
end
