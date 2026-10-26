function tests = ConfigRoundTripTest
%CONFIGROUNDTRIPTEST Save/load of pipeline configurations; unknown fields ignored safely.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    tc.TestData.dir = tempname; mkdir(tc.TestData.dir);
end

function teardownOnce(tc)
    rmdir(tc.TestData.dir, 's');
end

function testRoundTrip(tc)
    pc = pipelineDefaults();
    pc.mode = 'manual'; pc.pipeline.routing = 'antColony'; pc.pipeline.controller = 'purePursuit';
    pc.scenario.wind.enabled = true; pc.scenario.gust_mps = 0.4; pc.scenario.physics.energy = true;
    f = fullfile(tc.TestData.dir, 'a.json');
    savePipelineConfig(pc, f);
    [pc2, w] = loadPipelineConfig(f);
    verifyTrue(tc, isequaln(pc2, pc));
    verifyEmpty(tc, w);
    [h1, s1] = pipelineHash(pc); [h2, s2] = pipelineHash(pc2);
    verifyEqual(tc, h1, h2); verifyEqual(tc, s1, s2);
end

function testUnknownAndMissingFields(tc)
    in = struct('schemaVersion', 1, 'pipeline', struct('routing', 'nearestNeighbour2opt', 'futureStage', 'x'), 'extra', 5);
    [pc, w] = loadPipelineConfig(in);
    verifyEqual(tc, pc.pipeline.routing, 'nearestNeighbour2opt');
    verifyEqual(tc, pc.pipeline.controller, pipelineDefaults().pipeline.controller, 'missing field not defaulted');
    verifyTrue(tc, any(contains(w, 'futureStage')) && any(contains(w, 'extra')), 'unknown fields not reported');
    verifyFalse(tc, isfield(pc, 'extra'));
end

function testNoSchemaVersion(tc)
    [pc, w] = loadPipelineConfig(struct('mode', 'manual'));
    verifyEqual(tc, pc.schemaVersion, 1);
    verifyTrue(tc, any(contains(w, 'schemaVersion')));
    verifyTrue(tc, isequaln(rmfield(pc, 'mode'), rmfield(pipelineDefaults(), 'mode')));
end

function testLegacyFileRunsLegacy(tc)
    f = fullfile(tc.TestData.dir, 'legacy.json');
    savePipelineConfig(pipelineDefaults(), f);
    pc = loadPipelineConfig(f);
    verifyTrue(tc, isequaln(resolvePipeline(pc), applyPreset(config(), 'Baseline')));
end
