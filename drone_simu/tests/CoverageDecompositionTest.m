function tests = CoverageDecompositionTest
%COVERAGEDECOMPOSITIONTEST Pass-1 'polygonDecomposition' coverage (manual M3 / Phase 5).
%   Baseline unchanged; convex field yields the same valid path; concave field and obstacle
%   paths stay in the free field and terminate; an infeasible field fails instead of clipping.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
end

function testDefaultFieldUnchanged(tc)
    c = config();
    verifyEqual(tc, c.internal2.coverage.method, 'boustrophedon');
    verifyFalse(tc, c.internal2.field.keepAllRuns);
    verifyEmpty(tc, c.internal2.field.obstacles);
    f = quietField(applyPreset(c, 'Baseline'));
    verifyFalse(tc, any(isfield(f, {'obstacles', 'rowSweep', 'coverage'})), 'legacy field gained new fields');
end

function testConvexSameAsBoustrophedon(tc)
    for shape = {'Trapezoid', 'Rectangle'}
        c = applyPreset(config(), 'Baseline');
        c.internal2.field.polygon = fieldShapeToPolygon(shape{1}, struct('length', 30, 'width', 14, 'bottom', 30, 'top', 18, 'height', 14));
        f0 = quietField(c);
        c.internal2.coverage.method = 'polygonDecomposition';
        f1 = quietField(c);
        verifyEqual(tc, f1.coverage.nCells, 1);
        verifyEqual(tc, f1.surveyRef.pts, f0.surveyRef.pts, 'AbsTol', 1e-12, [shape{1} ': convex path differs']);
        verifyTrue(tc, isequaln(f1.plants, f0.plants));
    end
end

function testConcaveStaysInside(tc)
    c = uField(true);
    c.internal2.coverage.method = 'polygonDecomposition';
    f = quietField(c);
    verifyGreaterThanOrEqual(tc, f.coverage.nCells, 2);
    verifyTrue(tc, allFree(f.surveyRef.pts, f.polygon, {}), 'decomposition path leaves the concave field');
    verifyGreaterThanOrEqual(tc, f.coverage.minClearance_m, 0.9 * c.internal2.coverage.clearance_m);
    verifyTrue(tc, coversEveryRow(f), 'some row piece is not flown');
    % the legacy joined-rows path on the same field crosses the notch (why the alternative exists)
    c.internal2.coverage.method = 'boustrophedon';
    f0 = quietField(c);
    verifyFalse(tc, allFree(f0.surveyRef.pts, f0.polygon, {}));
    verifyTrue(tc, isequaln(f0.plants, f.plants), 'coverage method must not change the plants');
end

function testObstacleAvoided(tc)
    c = applyPreset(config(), 'Baseline');
    c.internal2.field.keepAllRuns = true;
    c.internal2.field.obstacles = obstaclePreset('pond', c.internal2.field.polygon);
    c.internal2.coverage.method = 'polygonDecomposition';
    f = quietField(c);
    verifyTrue(tc, allFree(f.surveyRef.pts, f.polygon, f.obstacles), 'path enters the obstacle');
    Q = f.obstacles{1};
    verifyFalse(tc, any(inpolygon(f.plants.X, f.plants.Y, Q(:, 1), Q(:, 2))), 'plants inside the obstacle');
    verifyTrue(tc, coversEveryRow(f));
end

function testInfeasibleFailsClosed(tc)
    c = applyPreset(config(), 'Baseline');
    c.internal2.field.polygon = fieldShapeToPolygon('Rectangle', struct('length', 30, 'width', 14));
    c.internal2.field.keepAllRuns = true;
    c.internal2.field.obstacles = {[14 -1; 16 -1; 16 15; 14 15]};       % a wall across the whole field
    c.internal2.coverage.method = 'polygonDecomposition';
    verifyError(tc, @() quietField(c), 'planCoverageDecomposition:infeasible');
end

function testMissionAndMetrics(tc)
    pc = pipelineDefaults(); pc.pipeline.controller = 'pid';
    pc.scenario.field.shape = 'UShape'; pc.scenario.field.keepAllRuns = true;
    a = runPipeline(pc);
    pc.pipeline.coverage = 'polygonDecomposition';
    b = runPipeline(pc);
    verifyEqual(tc, a.scenarioHash, b.scenarioHash, 'coverage is a pipeline choice: paired scenario');
    ca = coverageMetrics(a.field, a.cfg, a.run); cb = coverageMetrics(b.field, b.cfg, b.run);
    verifyEqual(tc, cb.plantRecall_pct, 100);
    verifyGreaterThanOrEqual(tc, cb.plantRecall_pct, ca.plantRecall_pct);
    verifyEqual(tc, cb.boundaryViolation_pct, 0);
    verifyEqual(tc, cb.plannedFeasible, 1);
    verifyEqual(tc, ca.plannedFeasible, 0);
    T = b.runMetrics;
    verifyTrue(tc, any(T.Group == "Coverage" & T.Metric == "Cells" & T.Value >= 2));
end

function testTreatmentLegsAvoidObstacle(tc)
    verifyFalse(tc, config().internal2.treat.freeSpaceLegs);
    pc = pipelineDefaults(); pc.pipeline.controller = 'pid';
    pc.scenario.field.shape = 'UShape'; pc.scenario.field.keepAllRuns = true; pc.scenario.field.obstacle = 'pond';
    a = runPipeline(pc);                                    % legacy straight legs on the same field
    pc.pipeline.coverage = 'polygonDecomposition';
    b = runPipeline(pc);
    verifyTrue(tc, b.cfg.internal2.treat.freeSpaceLegs);
    ca = coverageMetrics(a.field, a.cfg, a.run); cb = coverageMetrics(b.field, b.cfg, b.run);
    verifyGreaterThan(tc, ca.obstacleIncursion_pct, 0, 'scenario no longer exercises the obstacle');
    verifyEqual(tc, cb.obstacleIncursion_pct, 0, 'treatment legs entered the obstacle');
    verifyGreaterThan(tc, b.run.routes.freeSpaceDetours, 0);
    verifyEqual(tc, b.run.routes.freeSpaceBlocked, 0);
    verifyFalse(tc, isfield(a.run.routes, 'freeSpaceDetours'), 'legacy routes struct gained fields');
end

function testPipelineWiring(tc)
    R = pipelineRegistry();
    verifyTrue(tc, R.coverage.available(strcmp(R.coverage.id, 'polygonDecomposition')));
    pc = pipelineDefaults(); pc.pipeline.coverage = 'polygonDecomposition';
    pc.scenario.field.obstacle = 'pond';
    cfg = resolvePipeline(pc);
    verifyEqual(tc, cfg.internal2.coverage.method, 'polygonDecomposition');
    verifyNumElements(tc, cfg.internal2.field.obstacles, 1);
    [~, ~, w] = validatePipeline(pc);
    verifyTrue(tc, any(contains(w, 'shorter pieces')), 'no warning for dropped row pieces');
    pc = pipelineDefaults(); pc.pipeline.coverage = 'polygonDecomposition';
    [~, ~, w] = validatePipeline(pc);
    verifyTrue(tc, any(contains(w, 'same path as boustrophedon')));
    pc.scenario.field.shape = 'Hexagon';
    verifyFalse(tc, validatePipeline(pc));
end

function c = uField(keepAll)
    c = applyPreset(config(), 'Baseline');
    c.internal2.field.polygon = fieldShapeToPolygon('UShape', struct('length', 30, 'width', 14));
    c.internal2.field.keepAllRuns = keepAll;
end

function ok = coversEveryRow(f)
%COVERSEVERYROW Every row-piece point lies on the survey reference (within 1 cm).
    ok = true;
    S = f.surveyRef.pts;
    for r = 1:numel(f.rows)
        P = f.rows{r}([1 end], :);
        for i = 1:2, ok = ok && min(vecnorm(S - P(i, :), 2, 2)) < 0.01; end
    end
end

function ok = allFree(P, poly, obst)
    S = P(1, :);
    for i = 2:size(P, 1)
        n = max(1, ceil(norm(P(i, :) - P(i - 1, :)) / 0.05));
        S = [S; P(i - 1, :) + ((1:n)' / n) .* (P(i, :) - P(i - 1, :))]; %#ok<AGROW>
    end
    ok = all(inpolygon(S(:, 1), S(:, 2), poly(:, 1), poly(:, 2)));
    for o = 1:numel(obst), ok = ok && ~any(inpolygon(S(:, 1), S(:, 2), obst{o}(:, 1), obst{o}(:, 2))); end
end

function f = quietField(c)
    evalc('f = generateIrregularField(c);');
end
