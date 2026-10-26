function ok = testDashboardV2(projDir)
%TESTDASHBOARDV2 Headless checks for the V2 dashboard (milestones 1 and 2).
%   Proves: the dashboard only manipulates cfg and replays engine output unchanged;
%   Mission mode never reads hidden plant labels; displayed quantities are prefix-valid;
%   geometry controls invalidate the field while mission settings do not.
    addpath(projDir);
    ok = true;
    function check(cond, msg)
        if cond, fprintf('  PASS  %s\n', msg); else, fprintf('  FAIL  %s\n', msg); ok = false; end
    end

    fprintf('--- helpers ---\n');
    T = scenarioPresets();
    for i = 1:height(T)
        check(strcmp(matchPreset(T.wind(i), T.pid(i), T.comp(i)), char(T.name(i))), ['matchPreset ' char(T.name(i))]);
    end
    check(strcmp(matchPreset(true, false, true), 'Custom'), 'matchPreset wind+comp (no PID) = Custom');
    check(strcmp(presetUiName('No wind + PID'), 'Baseline + PID') && strcmp(presetUiName('Disturbed'), 'Disturbed'), 'presetUiName');
    check(isequal(fieldShapeToPolygon('Trapezoid', struct('bottom', 30, 'top', 18, 'height', 14)), config().internal2.field.polygon), ...
        'default trapezoid == config polygon');

    defaults = struct('windSpeed', 2.0, 'windDirDeg', 90, 'routing', 'nearestNeighbour', 'droneSpeed', 1.5, ...
        'rowSpacing', 2, 'plantSpacing', 0.5, 'shape', 'Trapezoid', 'rect', struct('length', 30, 'width', 14), ...
        'trap', struct('bottom', 30, 'top', 18, 'height', 14), 'rowStyle', 'Curved');
    for i = 1:height(T)
        s = defaults; s.wind = T.wind(i); s.pid = T.pid(i); s.comp = T.comp(i);
        ref = applyPreset(config(), char(T.name(i)));
        check(isequaln(uiToConfig(s), ref), ['uiToConfig == applyPreset cfg: ' char(T.name(i))]);
    end
    s = defaults; s.wind = true; s.pid = false; s.comp = true;
    check(isequaln(uiToConfig(s), applyPreset(config(), struct('wind', 1, 'pid', 0, 'comp', 1))), 'arbitrary combo via struct');
    try, s2 = defaults; s2.wind = false; s2.pid = false; s2.comp = false; s2.droneSpeed = 9; uiToConfig(s2); check(false, 'range check');
    catch ME, check(strcmp(ME.identifier, 'uiToConfig:invalid'), 'out-of-range input rejected'); end

    fprintf('--- information boundary: Mission-mode source scan ---\n');
    missionFiles = {'AgriculturalDroneDashboardV2.m', 'missionTimeline.m', 'missionStateAt.m', 'missionSummary.m', ...
        'uiToConfig.m', 'matchPreset.m', 'presetUiName.m', 'fieldShapeToPolygon.m'};
    forbidden = {'TrueDisease', 'isTruePositive', 'detectU', 'detectPlants', 'perceptionMetrics', 'sprayMetrics', ...
        'computeInternal2Metrics', 'plantDose', 'treatedTrue', 'nDiseased'};
    for i = 1:numel(missionFiles)
        src = fileread(fullfile(projDir, missionFiles{i}));
        hit = forbidden(cellfun(@(t) contains(src, t), forbidden));
        check(isempty(hit), sprintf('%s reads no ground-truth/evaluation symbol %s', missionFiles{i}, strjoin(hit, ',')));
    end

    fprintf('--- app: presets / custom ---\n');
    app = AgriculturalDroneDashboardV2('Visible', 'off', 'AutoPlay', false);
    cleanup = onCleanup(@() delete(app));
    check(strcmp(app.PresetDropDown.Value, 'Baseline'), 'initial preset Baseline');
    app.PresetDropDown.Value = 'Disturbed'; app.PresetDropDown.ValueChangedFcn([], []);
    check(app.WindCheck.Value && ~app.PidCheck.Value && ~app.CompCheck.Value, 'Disturbed sets wind ON, PID OFF, comp OFF');
    app.PidCheck.Value = true; app.PidCheck.ValueChangedFcn([], []);
    check(strcmp(app.PresetDropDown.Value, 'Navigation Corrected'), 'Disturbed + PID ON -> Navigation Corrected (matches preset)');
    app.setSwitches(true, false, true);
    check(strcmp(app.PresetDropDown.Value, 'Custom'), 'wind ON + comp ON, PID OFF -> Custom');
    app.setSwitches(false, true, false);
    check(strcmp(app.PresetDropDown.Value, 'Baseline + PID'), 'wind OFF + PID ON shown as "Baseline + PID"');
    app.setSwitches(false, false, true);
    check(strcmp(app.PresetDropDown.Value, 'Custom') && app.CompCheck.Value && ~app.WindCheck.Value, 'wind OFF + compensation ON is a valid Custom combination');

    fprintf('--- app: field generation, console silence, invalidation ---\n');
    app.setSwitches(false, false, false);
    out = evalc('app.generateField();');
    check(strcmp(app.mode, 'READY') && ~isempty(app.field), 'field generated -> READY');
    check(~contains(lower(out), 'diseased'), 'generateField prints nothing about disease to the console');
    cfgRef = applyPreset(config(), 'Baseline');
    fRef = quietField(cfgRef);
    check(isequaln(app.field, fRef), 'app field == engine field for default geometry');

    fieldBefore = app.field;
    app.WindCheck.Value = true; app.WindCheck.ValueChangedFcn([], []);
    app.PidCheck.Value = true; app.PidCheck.ValueChangedFcn([], []);
    app.CompCheck.Value = true; app.CompCheck.ValueChangedFcn([], []);
    app.RoutingDropDown.Value = 'fixedOrder';
    app.DroneSpeedEdit.Value = 1.2; app.PlaybackEdit.Value = 12;
    app.WindSpeedEdit.Value = 1.5; app.WindDirEdit.Value = 45;
    check(strcmp(app.mode, 'READY') && isequaln(app.field, fieldBefore), ...
        'wind/PID/compensation/routing/speeds/playback changes keep the field valid (no regeneration)');
    app.startMission();
    check(strcmp(app.mode, 'PLAYING') && strcmp(app.run.routes.routing, 'fixedOrder') && app.cfg.droneSpeed == 1.2 ...
        && app.cfg.internal2.wind.speed == 1.5 && app.cfg.internal2.wind.dirDeg == 45, 'those settings apply on the next START');
    app.resetMission();
    app.RoutingDropDown.Value = 'nearestNeighbour'; app.DroneSpeedEdit.Value = 1.5; app.WindSpeedEdit.Value = 2; app.WindDirEdit.Value = 90;
    app.setSwitches(false, false, false);

    geoCtl = {app.ShapeDropDown, 'Rectangle'; app.RectLengthEdit, 28; app.RectWidthEdit, 13; app.TrapBottomEdit, 28; ...
              app.TrapTopEdit, 16; app.TrapHeightEdit, 13; app.RowStyleDropDown, 'Straight'; app.RowSpacingEdit, 2.5; ...
              app.PlantSpacingEdit, 0.6};
    orig = cellfun(@(c) c.Value, geoCtl(:, 1), 'UniformOutput', false);
    for i = 1:size(geoCtl, 1)
        ctl = geoCtl{i, 1};
        app.generateField(); assert(strcmp(app.mode, 'READY'));
        ctl.Value = geoCtl{i, 2}; ctl.ValueChangedFcn([], []);
        check(strcmp(app.mode, 'NOFIELD') && isempty(app.field) && strcmp(app.StartButton.Enable, 'off'), ...
            sprintf('geometry control %d (%s) invalidates the field and disables START', i, class(ctl)));
        ctl.Value = orig{i}; ctl.ValueChangedFcn([], []);
        app.ShapeDropDown.Value = 'Trapezoid'; app.ShapeDropDown.ValueChangedFcn([], []);
    end
    app.generateField();
    check(strcmp(app.mode, 'READY'), 'regenerating after invalidation -> READY');

    fprintf('--- app: compute-then-replay equals experiment engine ---\n');
    cfgE = config(); cfgE.internal2.enabled = true;
    fieldE = quietField(cfgE);
    E = runExperimentE(cfgE, fieldE, false);
    names = {E.scn.name};
    for want = {'Disturbed', 'Fully Corrected'}
        i = find(strcmp(names, want{1}), 1);
        app.PresetDropDown.Value = presetUiName(want{1}); app.PresetDropDown.ValueChangedFcn([], []);
        app.generateField();
        app.startMission();
        check(strcmp(app.mode, 'PLAYING'), [want{1} ': START -> PLAYING']);
        check(isequaln(app.run, E.runs{i}), [want{1} ': app run is bit-identical to runExperimentE run']);
        check(strcmp(app.WindCheck.Enable, 'off') && strcmp(app.PresetDropDown.Enable, 'off') && strcmp(app.RoutingDropDown.Enable, 'off') ...
            && strcmp(app.RowSpacingEdit.Enable, 'off'), [want{1} ': configuration locked during replay']);
        app.tickOnce(50);
        check(strcmp(app.mode, 'PLAYING') && round(app.cursor) == 51, 'replay advances');
        app.pauseMission(); c0 = app.cursor; app.tickOnce(50);
        check(strcmp(app.mode, 'PAUSED') && app.cursor == c0, 'PAUSE freezes playback');
        app.resumeMission(); app.tickOnce(10);
        check(strcmp(app.mode, 'PLAYING') && app.cursor > c0, 'RESUME continues');
        app.stopMission();
        check(strcmp(app.mode, 'STOPPED') && strcmp(app.WindCheck.Enable, 'on'), 'STOP ends replay and unlocks configuration');
        app.resetMission();
        check(strcmp(app.mode, 'READY') && isempty(app.run), 'RESET -> READY, mission cleared');
    end

    fprintf('--- app: Mission-mode panels are prefix-valid ---\n');
    app.setSwitches(true, true, true);
    app.generateField(); app.startMission();
    tl = app.tl; run = app.run; fld = app.field;
    n1 = tl.n1;
    st = missionStateAt(tl, round(n1 / 2));
    check(st.sprayed == 0 && st.emitted_mL == 0 && st.pass2Distance == 0 && ~st.inPass2, 'Pass 1: no sprayed/emitted/route values yet');
    check(st.nObserved == nnz(tl.firstStep > 0 & tl.firstStep <= round(n1 / 2)) && st.nObserved < nnz(tl.firstStep > 0), ...
        'observed count is the prefix count (less than the final count mid-Pass 1)');
    midSpray = find(tl.stage == 4 & tl.sprayDone < tl.nTargets - 5, 1);
    stm = missionStateAt(tl, midSpray + 5);
    check(stm.sprayed < tl.nTargets && stm.emitted_mL < tl.sprayStepsCum(end) * tl.emitPerStep_mL, ...
        'mid-Pass 2: sprayed and emitted are below their final values');
    check(abs(tl.sprayStepsCum(end) * tl.emitPerStep_mL - run.grid.emitted) < 1e-9 && tl.sprayDone(end) == size(run.releasePts, 1), ...
        'replay-derived emitted volume and sprayed count equal the engine totals');
    check(abs((tl.cumDist(end) - tl.cumDist(n1)) - run.routes.actualDistance) < 0.2, 'Pass-2 route distance matches the engine measurement');
    [~, ~, fs] = detectPlants(fld, run.log1, app.cfg);      % engine/evaluation code may use it; Mission files may not
    check(isequal(fs, tl.firstStep), 'timeline observation steps equal the engine detection steps');
    check(isequal(find(tl.flagStep > 0), sort(run.targets.plantIdx(:))), 'flagged plants = engine detector output');
    tieOk = true;
    for s = unique(tl.firstStep(tl.firstStep > 0))'
        tieOk = tieOk && tl.obsPlant(s) == min(find(tl.firstStep == s));
    end
    check(tieOk, 'tie rule: several plants first seen at one step -> lowest plant row is shown');
    has = tl.obsPlant > 0;
    check(all(tl.firstStep(tl.obsPlant(has)) <= find(has)), 'observation card never shows a plant before it is observed');

    fprintf('--- app: hidden labels never influence Mission mode (perturbation) ---\n');
    ks = round(linspace(2, tl.N, 9));
    app.seek(1);
    before = captureUi(app, ks);
    fieldFlip = fld; fieldFlip.plants.TrueDisease(:) = "HEALTHY";
    runFlip = run; runFlip.targets.isTruePositive = ~run.targets.isTruePositive; runFlip.seen = ~run.seen;
    app.field = fieldFlip; app.run = runFlip;
    app.seek(1);
    after = captureUi(app, ks);
    check(isequaln(before, after), 'every label, colour and the summary are identical with ALL hidden labels altered');
    tlFlip = missionTimeline(app.cfg, fieldFlip, runFlip);
    check(isequaln(tlFlip, tl) && isequaln(missionSummary(tlFlip), missionSummary(tl)), 'timeline and summary are independent of hidden labels');
    app.field = fld; app.run = run;
    app.resetMission(); app.startMission();          % fresh replay (seek-to-end above left the app in DONE)

    fprintf('--- app: full replay + completion summary ---\n');
    app.seek(1);
    app.tickOnce(1e9);
    check(strcmp(app.mode, 'DONE') && round(app.cursor) == tl.N, 'replay runs to the end -> DONE');
    stF = missionStateAt(tl, tl.N);
    check(all(stF.flagged <= stF.observed), 'flagged plants are always observed plants');
    check(all(tl.firstStep(~stF.observed) == 0), 'plants never covered by the camera stay neutral to the end');
    txt = strjoin(string(app.SummaryRight.Text), ' ');
    sm = missionSummary(tl);
    check(contains(txt, sprintf('%d / %d', sm.plantsObserved, sm.plantsTotal)) && contains(txt, sprintf('sprayed %d', sm.targetsSprayed)), ...
        'completion summary shows the operational numbers');
    check(~contains(lower(txt), 'diseased') && ~contains(lower(txt), 'recall') && ~contains(lower(txt), 'true') && ~contains(lower(txt), 'missed') && ~contains(lower(txt), 'precision'), ...
        'completion summary contains no ground-truth evaluation wording');
    app.seek(1);
    txt1 = strjoin(string(app.SummaryRight.Text), ' ');
    check(~contains(txt1, 'Duration'), 'summary numbers are not shown before completion');
    app.seek(tl.N);
    check(strcmp(app.PhaseLabel.Text, 'MISSION COMPLETE'), 'phase banner at end');
    check(strcmp(app.TrPumpLabel.Text, 'Pump: OFF') && contains(app.ObsStateLabel.Text, 'complete'), 'pump is OFF and the card reads complete at mission end');

    fprintf('--- app: all 8 wind x PID x compensation UI mappings ---\n');
    cfgG = config(); cfgG.internal2.enabled = true;
    fG = quietField(cfgG);
    app.resetMission();
    app.generateField();
    nOK = 0;
    for w = 0:1
        for p = 0:1
            for c = 0:1
                if ~strcmp(app.mode, 'READY'), app.resetMission(); end
                app.setSwitches(w, p, c);
                lbl = matchPreset(w, p, c);
                labelOK = strcmp(app.PresetDropDown.Value, presetUiName(lbl));
                app.startMission();
                cD = applyPreset(config(), struct('wind', w, 'pid', p, 'comp', c));
                rD = runInternal2Scenario(cD, fG, lbl);
                same = isequaln(app.run, rD) && app.cfg.internal2.wind.enabled == logical(w) ...
                    && app.cfg.internal2.ctrl.enabled == logical(p) && app.cfg.internal2.spray.compensate == logical(c);
                check(labelOK && same, sprintf('wind %d PID %d comp %d: label "%s", app run == direct engine run', w, p, c, app.PresetDropDown.Value));
                nOK = nOK + (labelOK && same);
                app.stopMission();
            end
        end
    end
    check(nOK == 8, 'all 8 combinations map to the engine correctly');

    fprintf('--- app: Rectangle / Straight rows / alternate routing ---\n');
    app.resetMission();
    app.ShapeDropDown.Value = 'Rectangle'; app.ShapeDropDown.ValueChangedFcn([], []);
    app.RowStyleDropDown.Value = 'Straight'; app.RowStyleDropDown.ValueChangedFcn([], []);
    app.RoutingDropDown.Value = 'stage7Return';
    app.setSwitches(false, true, false);
    app.generateField();
    check(strcmp(app.mode, 'READY') && app.field.numRows >= 3, 'rectangle + straight rows generates');
    app.startMission();
    check(strcmp(app.mode, 'PLAYING') && strcmp(app.run.routes.routing, 'stage7Return'), 'stage7Return routing reaches the engine');
    app.tickOnce(1e9);
    check(strcmp(app.mode, 'DONE') && ~isempty(app.SummaryRight.Text), 'rectangle mission replays to completion');

    fprintf('%s\n', ternary(ok, 'DASHBOARD V2 MILESTONE-2 CHECKS: PASS', 'DASHBOARD V2 MILESTONE-2 CHECKS: FAIL'));
end

function snap = captureUi(app, ks)
%CAPTUREUI Everything the Mission screen shows at the given steps.
    snap = cell(numel(ks), 1);
    for i = 1:numel(ks)
        app.seek(ks(i));
        snap{i} = {app.PhaseLabel.Text, app.ObsPanel.Title, app.ObsIdLabel.Text, app.ObsPosLabel.Text, app.ObsStateLabel.Text, ...
            app.ObsDetLabel.Text, app.ObsCountLabel.Text, app.TrFlagLabel.Text, app.TrTargetLabel.Text, app.TrSprayedLabel.Text, ...
            app.TrRouteLabel.Text, app.TrPumpLabel.Text, app.TrEmitLabel.Text, app.SummaryLeft.Text, app.SummaryRight.Text, ...
            app.h.plants.CData, app.h.flag.XData, app.h.flag.YData};
    end
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end

function f = quietField(c)
    evalc('f = generateIrregularField(c);');
end
