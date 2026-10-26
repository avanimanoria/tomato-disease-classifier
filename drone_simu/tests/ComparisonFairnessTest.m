function tests = ComparisonFairnessTest
%COMPARISONFAIRNESSTEST Paired runs share field, disease truth, wind/gust trace, start state
%   and sensor seeds; an unpaired comparison is refused unless explicitly overridden.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    pc = pipelineDefaults();
    pc.scenario.wind.enabled = true; pc.scenario.gust_mps = 0.4;
    pc.scenario.physics.payload = true; pc.scenario.physics.energy = true;
    pc.pipeline.controller = 'pid'; pc.pipeline.localization = 'kalman';
    a = runPipeline(pc);
    pc2 = pc; pc2.pipeline.controller = 'purePursuit'; pc2.pipeline.routing = 'nearestNeighbour2opt';
    b = runPipeline(pc2);
    tc.TestData.a = a; tc.TestData.b = b;
end

function testSameScenario(tc)
    a = tc.TestData.a; b = tc.TestData.b;
    verifyEqual(tc, a.scenarioHash, b.scenarioHash);
    verifyTrue(tc, isequaln(a.field, b.field), 'different field or disease ground truth');
    t = 0:0.5:120;
    wa = cell2mat(arrayfun(@(x) windVector(a.cfg, x), t', 'UniformOutput', false));
    wb = cell2mat(arrayfun(@(x) windVector(b.cfg, x), t', 'UniformOutput', false));
    verifyTrue(tc, isequal(wa, wb), 'different wind / gust traces');
    verifyEqual(tc, a.cfg.enhancements.localization.seed, b.cfg.enhancements.localization.seed);
    verifyEqual(tc, a.run.log1.advLiquid(1), b.run.log1.advLiquid(1), 'different initial tank');
    verifyEqual(tc, a.run.log1.advEnergy(1), b.run.log1.advEnergy(1), 'different initial battery state');
    verifyEqual(tc, a.run.log1.truePos(1, :), b.run.log1.truePos(1, :), 'different start position');
end

function testPairedTable(tc)
    T = comparePipelineRuns({tc.TestData.a, tc.TestData.b});
    verifyEqual(tc, T.Properties.Description, 'PAIRED (identical scenario)');
    verifyTrue(tc, ismember('Run2_minus_Run1', T.Properties.VariableNames));
end

function testUnpairedRefused(tc)
    pc = tc.TestData.a.pc; pc.scenario.field.seed = 43;
    c = runPipeline(pc);
    verifyError(tc, @() comparePipelineRuns({tc.TestData.a, c}), 'comparePipelineRuns:unpaired');
    T = comparePipelineRuns({tc.TestData.a, c}, true);
    verifyEqual(tc, T.Properties.Description, 'UNPAIRED - scenarios differ');
end
