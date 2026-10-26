function captureGolden(projDir, outFile)
%CAPTUREGOLDEN Save full Internal-2 runs+metrics of the 4 original scenarios.
    addpath(projDir);
    cfgBase = config();
    cfgBase.internal2.enabled = true;
    field = generateIrregularField(cfgBase);
    sw = [0 0 0; 1 0 0; 1 1 0; 1 1 1];
    names = {'Baseline', 'Disturbed', 'PID only', 'Corrected'};
    runs = cell(1, 4); mets = cell(1, 4);
    for i = 1:4
        cfg = cfgBase;
        cfg.internal2.wind.enabled     = logical(sw(i, 1));
        cfg.internal2.ctrl.enabled     = logical(sw(i, 2));
        cfg.internal2.spray.compensate = logical(sw(i, 3));
        runs{i} = runInternal2Scenario(cfg, field, names{i});
        mets{i} = computeInternal2Metrics(cfg, field, runs{i});
    end
    save(outFile, 'runs', 'mets', 'field', 'cfgBase');
    fprintf('Golden saved: %s\n', outFile);
end
