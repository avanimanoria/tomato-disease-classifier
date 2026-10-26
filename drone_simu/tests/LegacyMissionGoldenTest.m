function tests = LegacyMissionGoldenTest
%LEGACYMISSIONGOLDENTEST Legacy missions reproduce the frozen golden runs exactly.
%   Original four scenarios (compareGolden), Experiment E (compareE) and the Phase-0
%   snapshot golden/legacy_mission_golden.mat (baseline, disturbed, fully corrected,
%   rectangle + straight + stage7Return, advanced mode with every feature).
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
end

function testOriginalFourScenarios(tc)
    p = tc.TestData.p;
    evalc('ok = compareGolden(p, fullfile(p, ''golden'', ''internal2_E_golden.mat''));');
    verifyTrue(tc, ok, 'compareGolden reported a difference');
end

function testExperimentE(tc)
    p = tc.TestData.p;
    evalc('ok = compareE(p, fullfile(p, ''golden'', ''experimentE_prerefactor.mat''));');
    verifyTrue(tc, ok, 'compareE reported a difference');
end

function testPhase0Snapshot(tc)
    G = load(fullfile(tc.TestData.p, 'golden', 'legacy_mission_golden.mat'));
    for nm = {'baseline', 'disturbed', 'fullyCorrected', 'rectStraight', 'advancedAll'}
        g = G.(nm{1});
        evalc('f = generateIrregularField(g.cfg);');
        verifyTrue(tc, isequaln(f, g.field), [nm{1} ': field changed']);
        r = runInternal2Scenario(g.cfg, f, 'golden');
        verifyTrue(tc, isequaln(r, g.run), [nm{1} ': run changed']);
        if isfield(r, 'cfgEffective'), ce = r.cfgEffective; else, ce = g.cfg; end
        verifyTrue(tc, isequaln(computeInternal2Metrics(ce, f, r), g.metrics), [nm{1} ': metrics changed']);
    end
end
