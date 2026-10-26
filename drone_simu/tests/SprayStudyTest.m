function tests = SprayStudyTest
%SPRAYSTUDYTEST Bounded UNCALIBRATED spray study (Phase 6) - saved outputs are consistent.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    p = testSetupPaths();
    tc.TestData.d = fullfile(p, 'results', 'spray_uncalibrated_v1');
end

function testOutputsPresentAndLabelled(tc)
    d = tc.TestData.d;
    for f = {'partA.csv', 'partB_engine.csv', 'partB_moving.csv', 'summary.md', 'manifest.json'}
        verifyTrue(tc, isfile(fullfile(d, f{1})), f{1});
    end
    verifyTrue(tc, contains(fileread(fullfile(d, 'summary.md')), 'UNCALIBRATED'));
    m = jsondecode(fileread(fullfile(d, 'manifest.json')));
    verifyTrue(tc, startsWith(m.calibration, 'UNCALIBRATED'));
end

function testLagCompensationRestoresZeroDelay(tc)
    E = readtable(fullfile(tc.TestData.d, 'partB_engine.csv'), 'TextType', 'string');
    for mode = ["stopped", "hover"]
        z = E.targetDeposition_pct(E.release == mode & E.valveDelay_s == 0);
        c = E.targetDeposition_pct(E.release == mode & E.lagCompensation == 1);
        verifyEqual(tc, c, repmat(z, size(c)), 'AbsTol', 1e-9, mode);
        u = E(E.release == mode & E.lagCompensation == 0, :);
        verifyTrue(tc, issorted(u.lagDisplacement_m), 'displacement grows with the delay');
    end
end

function testMovingReleaseMoreSensitive(tc)
    M = readtable(fullfile(tc.TestData.d, 'partB_moving.csv'));
    E = readtable(fullfile(tc.TestData.d, 'partB_engine.csv'), 'TextType', 'string');
    mv = M(M.speed_mps == 1.5, :);
    lossMove = mv.canopyCapture_pct(mv.valveDelay_s == 0) - mv.canopyCapture_pct(mv.valveDelay_s == 0.5 & mv.lagCompensation == 0);
    st = E(E.release == "stopped", :);
    lossStop = st.targetDeposition_pct(st.valveDelay_s == 0) - st.targetDeposition_pct(st.valveDelay_s == 0.5 & st.lagCompensation == 0);
    verifyGreaterThan(tc, lossMove, lossStop);
    verifyEqual(tc, M.canopyCapture_pct(M.lagCompensation == 1), ...
        arrayfun(@(v) M.canopyCapture_pct(M.speed_mps == v & M.valveDelay_s == 0), M.speed_mps(M.lagCompensation == 1)), 'AbsTol', 1e-9);
end

function testStudyRefusesOverwrite(tc)
    verifyError(tc, @() runSprayUncertaintyStudy(tc.TestData.d), 'runSprayUncertaintyStudy:exists');
end
