function tests = PipelineBuilderTest
%PIPELINEBUILDERTEST Manual pipeline builder (manual V1 section 2).
%   Legacy selection reproduces the legacy mission; every selectable option changes the
%   ENGINE (not only a label); unavailable options fail closed; saved-model modes;
%   section 2.4 manual run sequence; UI flow (run, pending, compare, export, replay).
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    pc = pipelineDefaults();
    pc.scenario.wind.enabled = true; pc.scenario.gust_mps = 0.3; pc.scenario.valveDelay_s = 0.5;
    pc.pipeline.controller = 'pid';
    tc.TestData.scn = pc;                       % disturbed scenario where every stage can matter
    tc.TestData.ref = runPipeline(pc);
end

function testLegacyReproducesGolden(tc)
    [cfg, ~] = resolvePipeline(pipelineDefaults());
    verifyTrue(tc, isequaln(cfg, applyPreset(config(), 'Baseline')), 'legacy pipeline does not resolve to the legacy cfg');
    G = load(fullfile(tc.TestData.p, 'golden', 'legacy_mission_golden.mat'));
    r = runPipeline(pipelineDefaults());
    run = r.run; run.name = G.baseline.run.name;
    verifyTrue(tc, isequaln(run, G.baseline.run), 'legacy pipeline run differs from the golden baseline');
end

function testManualRunSequence(tc)
    % section 2.4: PID+NN+none -> change ONLY compensation -> change ONLY controller -> legacy again
    pc = tc.TestData.scn; pc.scenario.valveDelay_s = 0; pc.scenario.gust_mps = 0.5;
    a = runPipeline(pc);
    pcB = pc; pcB.pipeline.sprayCompensation = 'wind';
    b = runPipeline(pcB);
    verifyTrue(tc, isequaln(a.run.log1, b.run.log1), 'changing only compensation must not change the survey flight');
    verifyFalse(tc, isequaln(a.run.releasePts, b.run.releasePts), 'compensation did not move the release points');
    verifyNotEqual(tc, a.metrics.spray.targetDepositionPct, b.metrics.spray.targetDepositionPct);
    pcC = pcB; pcC.pipeline.controller = 'purePursuit';
    c = runPipeline(pcC);
    verifyFalse(tc, isequaln(b.run.log1.truePos, c.run.log1.truePos), 'changing only the controller did not change the trajectory');
    verifyEqual(tc, a.scenarioHash, c.scenarioHash);
    G = load(fullfile(tc.TestData.p, 'golden', 'legacy_mission_golden.mat'));
    r = runPipeline(pipelineDefaults()); run = r.run; run.name = G.baseline.run.name;
    verifyTrue(tc, isequaln(run, G.baseline.run), 'restoring the legacy selection did not reproduce the baseline');
end

function testEveryOptionChangesEngine(tc)
    R = pipelineRegistry();
    ref = tc.TestData.ref; base = tc.TestData.scn;
    [cfgRef] = resolvePipeline(base);
    for stage = {'localization', 'controller', 'routing', 'sprayCompensation', 'kernel'}
        T = R.(stage{1});
        for k = 1:height(T)
            if ~T.available(k) || strcmp(T.id{k}, base.pipeline.(stage{1})), continue; end
            pc = base; pc.pipeline.(stage{1}) = T.id{k};
            cfg = resolvePipeline(pc);
            r = runPipeline(pc);
            verifyFalse(tc, isequaln(cfg, cfgRef), sprintf('%s=%s: cfg unchanged (label-only option)', stage{1}, T.id{k}));
            changed = ~isequaln(r.run.log1, ref.run.log1) || ~isequaln(r.run.legLogs, ref.run.legLogs) || ~isequaln(r.run.grid, ref.run.grid);
            verifyTrue(tc, changed, sprintf('%s=%s: mission identical to the reference (label-only option)', stage{1}, T.id{k}));
        end
    end
end

function testUnavailableFailClosed(tc)
    bad = {'perception', 'cnn'; 'coverage', 'polygonDecomposition'; 'routing', 'riskAware'; ...
           'sprayCompensation', 'uncertaintyAware'; 'kernel', 'calibrated'};
    R = pipelineRegistry();
    for i = 1:size(bad, 1)
        T = R.(bad{i, 1});
        if T.available(strcmp(T.id, bad{i, 2})), continue; end      % becomes available once implemented
        pc = pipelineDefaults(); pc.pipeline.(bad{i, 1}) = bad{i, 2};
        [ok, errs] = validatePipeline(pc);
        verifyFalse(tc, ok, [bad{i, 2} ' accepted']);
        verifyTrue(tc, any(contains(errs, 'UNAVAILABLE')), [bad{i, 2} ': no UNAVAILABLE message']);
        verifyError(tc, @() resolvePipeline(pc), 'resolvePipeline:invalid');
    end
    verifyError(tc, @() perceptionCNNAdapter([], [], config()), 'perceptionCNNAdapter:unavailable');
end

function testSavedModelModes(tc)
    S = load(fullfile(tc.TestData.p, 'results', 'benchmark', 'benchmark.mat'));
    pc = tc.TestData.scn; pc.mode = 'bestFixed';
    r = runPipeline(pc);
    verifyEqual(tc, string(sprintf('%s', r.pc.pipeline.controller)), "purePursuit");
    verifyEqual(tc, r.pc.pipeline.sprayCompensation, 'windLag');
    verifyTrue(tc, contains(r.warnings{1}, char(S.B.selection.bestFixed)));
    pcOff = pipelineDefaults(); pcOff.mode = 'scenarioSelector';
    verifyError(tc, @() runPipeline(pcOff), 'runPipeline:selectorOutOfScope');
    pcSel = tc.TestData.scn; pcSel.mode = 'scenarioSelector'; pcSel.scenario.wind.speed = 2.5;
    pcSel.scenario.gust_mps = 0; pcSel.scenario.valveDelay_s = 0; pcSel.pipeline.localization = 'kalman';
    r2 = runPipeline(pcSel);
    verifyTrue(tc, contains(r2.warnings{1}, 'SCENARIO SELECTOR'));
    pcO = tc.TestData.scn; pcO.mode = 'oracle';
    r3 = runPipeline(pcO);
    verifyEqual(tc, height(r3.oracleCandidates), 6);
    verifyEqual(tc, r3.metrics.spray.targetDepositionPct, max(r3.oracleCandidates.targetDepositionPct));
end

function testUiFlow(tc)
    app = AgriculturalDroneDashboardV2('Visible', 'off', 'AutoPlay', false);
    cl = onCleanup(@() delete(app));
    api = app.PipelineView;
    verifyTrue(tc, isequaln(api.getPc(), pipelineDefaults()), 'builder does not start at the legacy selection');
    api.setPc(tc.TestData.scn);
    r1 = api.runSelected();
    verifyNotEmpty(tc, r1);
    verifyTrue(tc, startsWith(api.ui.pending.Text, 'Up to date'));
    dd = api.ui.sprayCompensation; dd.Value = 'wind'; dd.ValueChangedFcn(dd, struct('Value', 'wind'));
    verifyTrue(tc, startsWith(api.ui.pending.Text, 'Pending changes'), 'no pending-changes notice after an edit');
    w = warning('off', 'pipelineBuilder:alert');
    pdd = api.ui.perception; pdd.Value = 'cnn'; pdd.ValueChangedFcn(pdd, struct('Value', 'cnn'));
    warning(w);
    verifyEqual(tc, api.ui.perception.Value, 'parametric', 'an UNAVAILABLE method was accepted by the UI');
    r2 = api.compareWith();
    verifyNotEmpty(tc, r2);
    s = api.state();
    verifyEqual(tc, numel(s.compare), 2);
    verifyTrue(tc, contains(api.ui.cmpInfo.Text, 'PAIRED'));
    tmp = tempname; mkdir(tmp);
    w = warning('off', 'pipelineBuilder:alert');
    d = api.exportRun(tmp);
    warning(w);
    for fn = {'config.json', 'run_info.json', 'metrics.csv', 'comparison.csv'}
        verifyTrue(tc, isfile(fullfile(d, fn{1})), ['export missing ' fn{1}]);
    end
    app.replayExternalRun(s.last);
    verifyEqual(tc, app.mode, 'PLAYING');
    app.tickOnce(1e9);
    verifyEqual(tc, app.mode, 'DONE');
    api.resetLegacy();
    verifyTrue(tc, isequaln(api.getPc(), pipelineDefaults()));
    rmdir(tmp, 's');
end
