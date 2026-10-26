function results = main_experiments(which)
%MAIN_EXPERIMENTS Controlled experiment harness for Internal-2 (Experiments A-E).
%
%   results = main_experiments            % run A, B, C, D and E
%   results = main_experiments('AB')      % any subset of the letters A B C D E
%
%   A+B  vehicle-disturbance sweep (PID off/on) -> tracking, observation, recall
%   C    routing comparison on one frozen, detection-independent target set
%   D    spray-only wind sweep (uncompensated vs compensated), drift distance recorded
%   E    integrated end-to-end mission (original demo + no-wind PID control)
%
%   Writes to cfg.experiments.outDir: one .mat and one CSV per experiment,
%   PNG figures, and cfg_used.json (every parameter used). Raw values only:
%   no constants are tuned here, and sweeps change only the swept variable.
%   All sweep parameters are in config.m under cfg.experiments.

    if nargin < 1, which = 'ABCDE'; end
    which = upper(which);
    runAB = any(which == 'A' | which == 'B');   % A and B share one sweep

    cfg = config();
    cfg.internal2.enabled = true;
    outDir = cfg.experiments.outDir;
    if ~isfolder(outDir), mkdir(outDir); end

    field = generateIrregularField(cfg);
    results = struct();

    fid = fopen(fullfile(outDir, 'cfg_used.json'), 'w');
    fwrite(fid, jsonencode(struct('internal2', cfg.internal2, 'experiments', cfg.experiments, ...
        'droneSpeed', cfg.droneSpeed, 'dt', cfg.dt, 'cameraFovRadius', cfg.cameraFovRadius, ...
        'flightAltitude', cfg.flightAltitude, 'rowSpacing', cfg.rowSpacing, 'plantSpacing', cfg.plantSpacing), ...
        'PrettyPrint', true));
    fclose(fid);

    if runAB
        fprintf('\n=== Experiments A/B: vehicle-disturbance sweep ===\n');
        res = runExperimentAB(cfg, field);
        results.AB = res;
        saveExperiment(outDir, 'experimentAB', res);
        saveFigure(outDir, 'experimentAB', plotExperiments('AB', res, 'off'));
        fprintf('A/B determinism check: %s\n', passFail(res.determinismOK));
    end
    if contains(which, 'C')
        fprintf('\n=== Experiment C: routing comparison (frozen target set) ===\n');
        res = runExperimentC(cfg, field);
        results.C = res;
        saveExperiment(outDir, 'experimentC', res);
        saveFigure(outDir, 'experimentC', plotExperiments('C', res, 'off'));
        fprintf('C determinism check: %s | invariance (Gate 3): %s\n', passFail(res.determinismOK), passFail(res.invariance.allPass));
        disp(res.summary);
    end
    if contains(which, 'D')
        fprintf('\n=== Experiment D: spray-only wind sweep ===\n');
        res = runExperimentD(cfg, field);
        results.D = res;
        saveExperiment(outDir, 'experimentD', res);
        saveFigure(outDir, 'experimentD', plotExperiments('D', res, 'off'));
        fprintf('D determinism check: %s | hover-vs-step deposition max rel. diff: %.2e\n', ...
            passFail(res.determinismOK), res.hoverEquivalenceRelErr);
    end
    if contains(which, 'D')
        fprintf('\n=== Experiment D2: compensation with imperfect wind estimate ===\n');
        res = runExperimentD2(cfg, field);
        results.D2 = res;
        saveExperiment(outDir, 'experimentD2', res);
        saveFigure(outDir, 'experimentD2', plotExperiments('D2', res, 'off'));
        fprintf('D2 consistency with D (alpha 0 and 1 rows identical): %s\n', passFail(res.determinismOK));
    end
    if contains(which, 'E')
        fprintf('\n=== Experiment E: integrated end-to-end mission ===\n');
        res = runExperimentE(cfg, field, true);
        results.E = res;
        saveExperiment(outDir, 'experimentE', res);
        close all;
        set(groot, 'DefaultFigureVisible', 'off');
        plotInternal2(cfg, field, res.runs, res.mets);       % creates the maps figure, then the tracking figure
        set(groot, 'DefaultFigureVisible', 'on');
        figs = findobj('Type', 'figure');
        [~, o] = sort([figs.Number]);
        figs = figs(o);
        saveFigure(outDir, 'experimentE_maps', figs(1));
        saveFigure(outDir, 'experimentE_tracking', figs(2));
        close(figs);
    end
    fprintf('\nResults written to %s\n', outDir);
end

function saveExperiment(outDir, name, res)
    save(fullfile(outDir, [name '.mat']), '-struct', 'res', '-v7.3');
    writetable(res.table, fullfile(outDir, [name '.csv']));
end

function saveFigure(outDir, name, fig)
    exportgraphics(fig, fullfile(outDir, [name '.png']), 'Resolution', 150);
end

function s = passFail(ok)
    if ok, s = 'PASS'; else, s = 'FAIL'; end
end
