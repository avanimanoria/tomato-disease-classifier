function run = runInternal2Scenario(cfg, field, name, opts)
%RUNINTERNAL2SCENARIO One deterministic Internal-2 mission.
%
%   run = runInternal2Scenario(cfg, field, name)
%   run = runInternal2Scenario(cfg, field, name, opts)
%
%   The scenario is defined ENTIRELY by cfg.internal2 (wind.enabled,
%   ctrl.enabled, spray.compensate; see applyScenario), so Baseline /
%   Disturbed / Corrected differ only in those switches; field, ground truth
%   and detection draws come from the shared `field` struct. No random
%   numbers are drawn here.
%
%   Pass 1: runSurveyPass - fly the survey reference; detectPlants images
%           plants within cfg.cameraFovRadius of the TRUE position and flags
%           targets (cfg.internal2.detect.mode).
%   Pass 2: runTreatmentPass - nearest-neighbour route over the target set's
%           RELEASE points (target, or target shifted upwind when
%           spray.compensate), fly straight legs from the ESTIMATED position,
%           settle, spray. No per-target return to the survey path.
%
%   opts (optional): opts.targets - a frozen target set (struct with XY, and
%   the same fields as detectPlants output) used for Pass 2 INSTEAD of the
%   detected set; detection is still run and reported in run.seen.

    if ~cfg.internal2.enabled
        error('runInternal2Scenario:notEnabled', ...
            'Set cfg.internal2.enabled = true to use Internal-2 mode.');
    end
    if nargin < 4, opts = struct(); end
    if advOn(cfg, 'any'), cfg = applyAdvancedDerived(cfg); end   % ENHANCEMENT (opt-in): altitude-dependent values

    cfg.internal2.spray.footprintRadius = ...
        cfg.internal2.spray.releaseHeight * tand(cfg.internal2.spray.nozzleHalfAngle); % [DERIVED]

    sv = runSurveyPass(cfg, field);
    [targets, seen, firstStep] = detectPlants(field, sv.log1, cfg);
    if isfield(opts, 'targets')
        targets = opts.targets;
    elseif advOn(cfg, 'localization') && isfield(cfg.enhancements.localization, 'geolocateTargets') ...
            && cfg.enhancements.localization.geolocateTargets      % absent in configs saved before Phase 4
        % ENHANCEMENT (opt-in, truth firewall): the drone records each flagged plant where IT BELIEVED it
        % was when the plant was centred in the camera (estimate error at that step); Pass 2 flies there.
        targets.XYtrue = targets.XY;                 % kept for diagnostics / scoring only
        targets.XY = targets.XY + sv.log1.advEstErr(firstStep(targets.plantIdx), :);
    end
    tp = runTreatmentPass(cfg, field, sv, targets);

    pass1.time = sv.time;
    pass1.distance = sv.distance;

    run.name = name;
    run.flags = struct('wind', cfg.internal2.wind.enabled, 'pid', cfg.internal2.ctrl.enabled, ...
                       'compensate', cfg.internal2.spray.compensate);
    run.windVel = tp.windVel;
    run.driftTrue = tp.driftTrue;
    run.compVec = tp.compVec;
    run.log1 = sv.log1;
    run.legLogs = tp.legLogs;
    run.pass1 = pass1;
    run.seen = seen;
    run.targets = targets;
    run.order = tp.order;
    run.releasePts = tp.releasePts;
    run.grid = tp.grid;
    run.routes = tp.routes;
    run.startXY = tp.startXY;
    run.finalWorld = tp.finalWorld;
    if advOn(cfg, 'any')                                   % ENHANCEMENT (opt-in)
        run.advanced = advancedMetrics(cfg, field, sv, tp);
        run.cfgEffective = cfg;
    end
end
