function ok = testAdvancedPhysics(projDir)
%TESTADVANCEDPHYSICS Optional advanced physics behind cfg.enhancements.enableAdvancedPhysics.
%   Mode A (switch off, or on with no feature) must equal the original exactly; each
%   feature on its own must behave physically sensibly and deterministically.
    addpath(projDir);
    ok = true;
    function check(cond, msg)
        if cond, fprintf('  PASS  %s\n', msg); else, fprintf('  FAIL  %s\n', msg); ok = false; end
    end
    feats = advFeatures();

    fprintf('--- Mode A: original behaviour preserved ---\n');
    c0 = config();
    check(~c0.enhancements.enableAdvancedPhysics && all(cellfun(@(f) ~c0.enhancements.(f).enabled, feats)), ...
        'master switch and every feature default to OFF');
    base = applyPreset(config(), 'Fully Corrected');
    fld = quietField(base);
    rBase = runInternal2Scenario(base, fld, 'x');
    cM = base; cM.enhancements.enableAdvancedPhysics = true;              % master on, nothing selected
    check(isequaln(runInternal2Scenario(cM, fld, 'x'), rBase), 'master ON with no feature enabled == original (bit-identical)');
    cF = base; for i = 1:numel(feats), cF.enhancements.(feats{i}).enabled = true; end   % features on, master off
    check(isequaln(runInternal2Scenario(cF, fld, 'x'), rBase), 'all features ticked but master OFF == original (bit-identical)');
    check(~isfield(rBase, 'advanced') && ~isfield(rBase.log1, 'advMass'), 'original runs carry no advanced fields');

    one = @(f) setFeat(base, f);
    mBase = computeInternal2Metrics(base, fld, rBase);

    fprintf('--- payload & tank ---\n');
    r = runInternal2Scenario(one('payload'), fld, 'x');
    A = r.advanced;
    nT = size(r.releasePts, 1);
    check(A.refills == ceil(nT * 0.05 / 2.0) - 1 + (mod(nT * 0.05, 2.0) == 0) * 0 && A.refills >= 1, ...
        sprintf('%d targets x 50 mL with a 2 L tank -> %d refill trip(s)', nT, A.refills));
    check(abs(A.pumped_L - nT * 0.05) < 1e-9, 'pumped volume = targets x dose');
    L = cell2mat(cellfun(@(x) x.advLiquid, [{r.log1}; r.legLogs], 'UniformOutput', false));
    dL = diff(L);
    check(all(dL <= 1e-12 | abs(dL - (2.0 - L(find(dL > 0, 1)))) < 1e-9 | dL > 0.1), 'tank level only falls, except at refills');
    check(abs(A.massStart_kg - 7.0) < 1e-12 && A.massEnd_kg < A.massStart_kg, 'mass starts at dry + full tank and falls');
    check(isequaln(r.log1.truePos, rBase.log1.truePos), 'payload alone (kinematic model) does not change the survey flight');

    fprintf('--- vehicle dynamics: lighter drone is pushed harder ---\n');
    cd1 = setFeat(applyPreset(config(), 'Disturbed'), 'dynamics');
    cHeavy = cd1; cHeavy.enhancements.payload.tankCapacity_L = 4.0;
    cLight = cd1; cLight.enhancements.payload.tankCapacity_L = 0.05;
    mH = computeInternal2Metrics(cHeavy, fld, runInternal2Scenario(cHeavy, fld, 'x'));
    mL = computeInternal2Metrics(cLight, fld, runInternal2Scenario(cLight, fld, 'x'));
    fprintf('        Disturbed (PID off): cross-track RMSE heavy (9 kg) %.3f m vs light (5.05 kg) %.3f m\n', mH.survey.crossRMSE, mL.survey.crossRMSE);
    check(mL.survey.crossRMSE > mH.survey.crossRMSE, 'same wind, lighter drone -> larger open-loop tracking error');
    cdp = setFeat(base, 'dynamics');
    mP = computeInternal2Metrics(cdp, fld, runInternal2Scenario(cdp, fld, 'x'));
    check(mP.survey.crossRMSE < 0.1, sprintf('with PID the dynamic model still tracks (RMSE %.3f m)', mP.survey.crossRMSE));

    fprintf('--- energy & battery ---\n');
    ce = setFeat(setFeat(base, 'energy'), 'payload');
    r = runInternal2Scenario(ce, fld, 'x');
    A = r.advanced;
    E = cell2mat(cellfun(@(x) x.advEnergy, [{r.log1}; r.legLogs], 'UniformOutput', false));
    t = cell2mat(cellfun(@(x) x.t, [{r.log1}; r.legLogs], 'UniformOutput', false));
    pw = diff(E) ./ diff(t);
    fprintf('        energy %.1f Wh = %.0f%% of %d Wh; mean power %.0f W; power first 10 s %.0f W, last 10 s %.0f W\n', ...
        A.energy_Wh, A.batteryUsedPct, c0.enhancements.energy.battery_Wh, A.meanPower_W, mean(pw(1:100)), mean(pw(end-99:end)));
    check(A.energy_Wh > 0 && all(diff(E) >= 0), 'energy is positive and only increases');
    check(mean(pw(end-99:end)) < mean(pw(1:100)), 'power falls as the tank empties (hover power ~ mass^1.5)');

    fprintf('--- wind gusts ---\n');
    cg = setFeat(base, 'gusts');
    tt = 0:0.1:2000;
    gw = cell2mat(arrayfun(@(x) windVector(cg, x), tt', 'UniformOutput', false));
    wm = base.internal2.wind.speed * [cosd(base.internal2.wind.dirDeg), sind(base.internal2.wind.dirDeg)];
    gr = std(gw - wm);
    fprintf('        gust RMS per axis over 2000 s: %.3f / %.3f m/s (target %.2f)\n', gr(1), gr(2), cg.enhancements.gusts.sigma_mps);
    check(all(abs(gr - 0.5) < 0.05) && norm(mean(gw) - wm) < 0.05, 'zero-mean gusts with the configured RMS');
    cgo = cg; cgo.internal2.wind.enabled = false;
    check(isequal(windVector(cgo, 12.3), [0 0]), 'no gusts when wind is off');
    r1 = runInternal2Scenario(cg, fld, 'x'); r2 = runInternal2Scenario(cg, fld, 'x');
    check(isequaln(r1, r2), 'gust runs are deterministic');

    fprintf('--- atmosphere: humidity, droplet size, downwash ---\n');
    ca = setFeat(base, 'atmosphere');
    [d1, e1] = advancedDrift(ca, [2 0], 7);
    cDry = ca; cDry.enhancements.atmosphere.relHumidity_pct = 20;
    [~, e2] = advancedDrift(cDry, [2 0], 7);
    cFine = ca; cFine.enhancements.atmosphere.dropletVMD_um = 100;
    [d3, e3] = advancedDrift(cFine, [2 0], 7);
    [d4] = advancedDrift(ca, [2 0], 5);
    fprintf('        250 um, RH 50%%: drift %.2f m, evaporated %.1f%% | RH 20%%: evaporated %.1f%% | 100 um: drift %.2f m, evaporated %.1f%% | lighter drone: drift %.2f m\n', ...
        norm(d1), 100*e1, 100*e2, norm(d3), 100*e3, norm(d4));
    check(e2 > e1, 'drier air -> more evaporation');
    check(norm(d3) > norm(d1) && e3 > e1, 'finer droplets -> more drift and more evaporation');
    check(norm(d4) > norm(d1), 'lighter drone -> weaker downwash -> more drift');
    r = runInternal2Scenario(ca, fld, 'x');
    check(r.advanced.evaporated_mL > 0 && abs(r.grid.emitted - r.advanced.pumped_L * 1000) < 1e-6, 'evaporated volume counted as emitted, not deposited');

    fprintf('--- perception & altitude ---\n');
    cp = setFeat(base, 'perception');
    c2 = applyAdvancedDerived(cp);
    check(abs(c2.cameraFovRadius - 0.6) < 1e-12 && abs(c2.internal2.spray.releaseHeight - 1.0) < 1e-12 ...
        && c2.internal2.detect.pDetectDiseased == base.internal2.detect.pDetectDiseased, 'default 2 m altitude reproduces the original footprint, release height and detection');
    cp4 = cp; cp4.enhancements.perception.altitude_m = 4;
    c4 = applyAdvancedDerived(cp4);
    fprintf('        4 m altitude: camera radius %.2f m, release height %.1f m, P(detect) %.3f\n', c4.cameraFovRadius, c4.internal2.spray.releaseHeight, c4.internal2.detect.pDetectDiseased);
    check(c4.cameraFovRadius > 0.6 && c4.internal2.spray.releaseHeight > 1 && c4.internal2.detect.pDetectDiseased < 0.95, 'higher -> wider footprint, higher release, lower detection');
    r4 = runInternal2Scenario(cp4, fld, 'x');
    check(isfield(r4, 'cfgEffective') && r4.cfgEffective.cameraFovRadius == c4.cameraFovRadius, 'derived values reach the engine (run.cfgEffective)');

    fprintf('--- localization error ---\n');
    cl = setFeat(base, 'localization');
    r = runInternal2Scenario(cl, fld, 'x');
    m = computeInternal2Metrics(cl, fld, r);
    fprintf('        estimate error RMS %.3f m (max %.3f); true cross-track RMSE %.3f m vs %.3f m with perfect position\n', ...
        r.advanced.estErrRMS_m, r.advanced.estErrMax_m, m.survey.crossRMSE, mBase.survey.crossRMSE);
    check(r.advanced.estErrRMS_m > 0 && m.survey.crossRMSE > mBase.survey.crossRMSE, 'odometry error degrades true tracking');
    ee = vecnorm(r.log1.advEstErr, 2, 2);
    fixK = round(cl.enhancements.localization.fixInterval_s / cl.dt);
    check(ee(fixK + 2) < ee(fixK - 1), 'absolute fix resets the error');

    fprintf('--- safety advisories ---\n');
    cs = setFeat(setFeat(base, 'safety'), 'gusts');
    cs.enhancements.safety.maxSprayWind_mps = 1.0;
    r = runInternal2Scenario(cs, fld, 'x');
    check(any(contains(r.advanced.advisories, 'Sprayed in wind')), 'spraying above the wind limit is reported');
    rNo = runInternal2Scenario(setFeat(base, 'gusts'), fld, 'x');
    check(isequaln(rmfield(r, {'advanced', 'cfgEffective'}), rmfield(rNo, {'advanced', 'cfgEffective'})), 'advisories never change the flight');

    fprintf('--- per-feature effect on Fully Corrected (each alone; treated / target deposition) ---\n');
    fprintf('        %-14s treated %2d, deposition %5.1f%%\n', 'original', mBase.spray.treatedTrue, mBase.spray.targetDepositionPct);
    for i = 1:numel(feats)
        c = setFeat(base, feats{i});
        rr = runInternal2Scenario(c, fld, 'x');
        mm = computeInternal2Metrics(rr.cfgEffective, fld, rr);
        fprintf('        %-14s treated %2d, deposition %5.1f%%\n', feats{i}, mm.spray.treatedTrue, mm.spray.targetDepositionPct);
    end
    call = base; call.enhancements.enableAdvancedPhysics = true;
    for i = 1:numel(feats), call.enhancements.(feats{i}).enabled = true; end
    rr = runInternal2Scenario(call, fld, 'x');
    mm = computeInternal2Metrics(rr.cfgEffective, fld, rr);
    fprintf('        %-14s treated %2d, deposition %5.1f%%\n', 'ALL features', mm.spray.treatedTrue, mm.spray.targetDepositionPct);

    fprintf('--- dashboard ---\n');
    rApp = runInternal2Scenario(base, fld, 'Fully Corrected');      % same engine call the app makes (run name = preset)
    app = AgriculturalDroneDashboardV2('Visible', 'off', 'AutoPlay', false);
    cl2 = onCleanup(@() delete(app));
    check(~app.AdvMasterCheck.Value && strcmp(app.AdvCtl.payload.enable.Enable, 'off'), 'Advanced mode off by default; its options are disabled');
    app.setSwitches(true, true, true);
    app.generateField(); app.startMission();
    check(~isfield(app.run, 'advanced') && isequaln(app.run, rApp), 'dashboard with Advanced mode off == original engine run');
    check(any(contains(string(app.SummaryAdv.Text), 'OFF')), 'mission summary says advanced physics is OFF');
    app.resetMission();
    app.AdvMasterCheck.Value = true; app.AdvMasterCheck.ValueChangedFcn(app.AdvMasterCheck, []);
    check(app.AdvMasterCheck2.Value && strcmp(app.AdvCtl.payload.enable.Enable, 'on'), 'master switch syncs both tabs and enables the options');
    for i = 1:numel(feats)
        app.AdvCtl.(feats{i}).enable.Value = true;
    end
    app.AdvCtl.payload.enable.ValueChangedFcn([], []);
    check(strcmp(app.AdvCtl.payload.tankCapacity_L.Enable, 'on'), 'a ticked feature enables its parameters');
    app.AdvCtl.perception.altitude_m.Value = 2.5;
    app.startMission();
    check(strcmp(app.mode, 'PLAYING') && isfield(app.run, 'advanced') && app.cfg.enhancements.perception.altitude_m == 2.5, ...
        'dashboard mission runs with every advanced feature and the edited altitude');
    check(strcmp(app.AdvCtl.payload.enable.Enable, 'off'), 'advanced options are locked during replay');
    app.tickOnce(1e9);
    txt = strjoin(string(app.SummaryAdv.Text), ' ');
    check(strcmp(app.mode, 'DONE') && contains(txt, 'Tank') && contains(txt, 'Battery'), 'live advanced readout shows tank and battery');
    check(any(app.tl.isRefill), 'replay contains the refill trip');
    app.resetMission();
    app.AdvMasterCheck.Value = false; app.AdvMasterCheck.ValueChangedFcn(app.AdvMasterCheck, []);
    app.startMission();
    check(isequaln(app.run, rApp), 'switching Advanced mode off again restores the original run exactly');

    fprintf('%s\n', ternary(ok, 'ADVANCED PHYSICS CHECKS: PASS', 'ADVANCED PHYSICS CHECKS: FAIL'));
end

function c = setFeat(c, f)
    c.enhancements.enableAdvancedPhysics = true;
    c.enhancements.(f).enabled = true;
end

function f = quietField(c)
    evalc('f = generateIrregularField(c);');
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end
