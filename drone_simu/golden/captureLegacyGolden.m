function captureLegacyGolden(projDir, outFile)
%CAPTURELEGACYGOLDEN Phase-0 golden snapshot of the missions the manual names (fixed seeds).
%   captureLegacyGolden(projDir, outFile) stores full engine runs and their metrics for:
%     baseline        dashboard default (Baseline preset, trapezoid, curved, NN)
%     disturbed       Disturbed preset
%     fullyCorrected  Fully Corrected preset
%     pidOff/compOff  covered by baseline/disturbed
%     rectStraight    Rectangle 30x14, straight rows, PID on, stage7Return routing
%     advancedAll     Advanced mode with every feature on (localization 'kalman')
%   Used by tests/LegacyMissionGoldenTest. Capture ONCE from a verified baseline.
    addpath(projDir);
    G = struct();
    G.baseline = one(applyPreset(config(), 'Baseline'));
    G.disturbed = one(applyPreset(config(), 'Disturbed'));
    G.fullyCorrected = one(applyPreset(config(), 'Fully Corrected'));
    s = struct('wind', false, 'pid', true, 'comp', false, 'windSpeed', 2, 'windDirDeg', 90, 'routing', 'stage7Return', ...
        'droneSpeed', 1.5, 'rowSpacing', 2, 'plantSpacing', 0.5, 'shape', 'Rectangle', ...
        'rect', struct('length', 30, 'width', 14), 'trap', struct('bottom', 30, 'top', 18, 'height', 14), 'rowStyle', 'Straight');
    G.rectStraight = one(uiToConfig(s));
    c = applyPreset(config(), 'Fully Corrected');
    c.enhancements.enableAdvancedPhysics = true;
    for f = advFeatures(), c.enhancements.(f{1}).enabled = true; end
    c.enhancements.localization.mode = 'kalman';
    G.advancedAll = one(c);
    G.capturedOn = datestr(now, 'yyyy-mm-dd HH:MM');
    save(outFile, '-struct', 'G');
    fprintf('Legacy golden saved: %s\n', outFile);
end

function g = one(cfg)
    evalc('f = generateIrregularField(cfg);');
    r = runInternal2Scenario(cfg, f, 'golden');
    if isfield(r, 'cfgEffective'), ce = r.cfgEffective; else, ce = cfg; end
    g.cfg = cfg; g.field = f; g.run = r; g.metrics = computeInternal2Metrics(ce, f, r);
end
