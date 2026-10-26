function tests = HardwareProfileTest
%HARDWAREPROFILETEST Versioned hardware profiles with provenance (manual M5 / Phase 7).
%   Default profile == config.m; switching changes only the listed parameters and is
%   reversible; uncited / out-of-range profiles are rejected; feasibility warnings fire.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    tc.TestData.tmp = tempname; mkdir(tc.TestData.tmp);
end

function teardownOnce(tc)
    rmdir(tc.TestData.tmp, 's');
end

function testDefaultProfileEqualsConfig(tc)
    [ids, ~] = hardwareProfileList();
    verifyEqual(tc, ids{1}, 'assumedDefault');
    c0 = config();
    [c1, ch] = applyHardwareProfile(c0, 'assumedDefault');
    verifyTrue(tc, isequaln(c1, c0), 'assumedDefault.json drifted from config.m');
    verifyEqual(tc, height(ch), 0);
    p = loadHardwareProfile('assumedDefault');
    verifyTrue(tc, all(strcmp({p.params.sourceType}, 'synthetic')), 'the default profile must be labelled synthetic');
end

function testSwitchOnlyListedAndReversible(tc)
    f = writeProfile(tc, 'testHeavy', {'payload.tankCapacity_L', 6, 'synthetic', ''; 'energy.battery_Wh', 600, 'synthetic', ''});
    c0 = config();
    [c1, ch] = applyHardwareProfile(c0, f);
    verifyEqual(tc, sort(cellstr(ch.key)), sort({'payload.tankCapacity_L'; 'energy.battery_Wh'}));
    verifyEqual(tc, c1.enhancements.payload.tankCapacity_L, 6);
    c1b = c1; c1b.enhancements.payload.tankCapacity_L = c0.enhancements.payload.tankCapacity_L;
    c1b.enhancements.energy.battery_Wh = c0.enhancements.energy.battery_Wh;
    verifyTrue(tc, isequaln(c1b, c0), 'a parameter outside the profile changed');
    verifyTrue(tc, isequaln(applyHardwareProfile(c1, 'assumedDefault'), c0), 'switching back did not restore the defaults');
end

function testProvenanceEnforced(tc)
    f = writeProfile(tc, 'noCite', {'payload.dryMass_kg', 9, 'manufacturer', ''});
    verifyError(tc, @() loadHardwareProfile(f), 'hardwareProfile:uncited');
    f = writeProfile(tc, 'outOfRange', {'payload.dryMass_kg', 900, 'synthetic', ''});
    verifyError(tc, @() loadHardwareProfile(f), 'hardwareProfile:range');
    f = writeProfile(tc, 'badKey', {'payload.warpDrive', 1, 'synthetic', ''});
    verifyError(tc, @() loadHardwareProfile(f), 'hardwareProfile:unknownParameter');
    f = writeProfile(tc, 'cited', {'payload.dryMass_kg', 9, 'manufacturer', 'Datasheet X, table 2, accessed 2026-10-11'});
    p = loadHardwareProfile(f);
    verifyEqual(tc, p.provenance, '1 manufacturer, 0 literature, 0 synthetic');
    verifyError(tc, @() loadHardwareProfile('doesNotExist'), 'hardwareProfile:notFound');
end

function testFeasibilityWarnings(tc)
    c = config();
    verifyEmpty(tc, checkProfileFeasibility(c), 'the default design should pass the sanity checks');
    c.enhancements.dynamics.thrustToWeightFull = 1.1;
    c.enhancements.energy.battery_Wh = 30;
    w = checkProfileFeasibility(c);
    verifyTrue(tc, any(contains(w, 'thrust/weight')));
    verifyTrue(tc, any(contains(w, 'endurance')));
end

function testPipelineUnknownProfileFailsClosed(tc)
    pc = pipelineDefaults(); pc.scenario.hardwareProfile = 'notAProfile';
    [ok, errs] = validatePipeline(pc);
    verifyFalse(tc, ok);
    verifyTrue(tc, any(contains(errs, 'UNAVAILABLE')));
    verifyError(tc, @() resolvePipeline(pc), 'resolvePipeline:invalid');
end

function testDefaultMissionUnchanged(tc)
    G = load(fullfile(tc.TestData.p, 'golden', 'legacy_mission_golden.mat'));
    r = runPipeline(pipelineDefaults());
    run = r.run; run.name = G.baseline.run.name;
    verifyTrue(tc, isequaln(run, G.baseline.run));
    verifyEqual(tc, r.info.hardwareProvenance, 'synthetic (config.m defaults)');
end

function f = writeProfile(tc, id, rows)
    P = struct('key', rows(:, 1), 'value', rows(:, 2), 'unit', '-', 'sourceType', rows(:, 3), ...
        'citation', rows(:, 4), 'range', {[0 1000]});
    for i = 1:numel(P)
        if strcmp(P(i).key, 'payload.dryMass_kg'), P(i).range = [3 25]; end
    end
    J = struct('schemaVersion', 1, 'id', id, 'version', '0.1', 'label', id, 'description', 'unit test', 'parameters', P);
    f = fullfile(tc.TestData.tmp, [id '.json']);
    fid = fopen(f, 'w'); fprintf(fid, '%s', jsonencode(J)); fclose(fid);
end
