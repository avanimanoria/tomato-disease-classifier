function [cfg, info] = resolvePipeline(pc)
%RESOLVEPIPELINE Map a PipelineConfig onto the EXISTING engine parameters (single adapter).
%
%   [cfg, info] = resolvePipeline(pc)
%
%   Uses uiToConfig (the same adapter as the Mission tab) for field / wind / PID /
%   compensation / routing, then switches on exactly the optional features each choice needs.
%   Choices that need nothing optional leave every enhancement flag OFF, so the legacy
%   selection resolves to the legacy cfg (tests/PipelineBuilderTest).
%   info: implementation ids, calibration status, enabled features.
    [ok, errs] = validatePipeline(pc);
    if ~ok
        error('resolvePipeline:invalid', 'Invalid pipeline: %s', strjoin(errs, '; '));
    end
    S = pc.scenario; P = pc.pipeline;
    c0 = config();
    E = c0.enhancements;
    s = struct('wind', S.wind.enabled, 'pid', strcmp(P.controller, 'pid') || strcmp(P.controller, 'purePursuit'), ...
        'comp', ~strcmp(P.sprayCompensation, 'none'), 'windSpeed', S.wind.speed, 'windDirDeg', S.wind.dirDeg, ...
        'routing', P.routing, 'droneSpeed', S.droneSpeed, 'rowSpacing', S.field.rowSpacing, ...
        'plantSpacing', S.field.plantSpacing, 'shape', S.field.shape, ...
        'rect', struct('length', S.field.length, 'width', S.field.width), ...
        'trap', struct('bottom', S.field.bottom, 'top', S.field.top, 'height', S.field.height), 'rowStyle', S.field.rowStyle);
    s.advancedRouting = ~any(strcmp(P.routing, {'fixedOrder', 'nearestNeighbour', 'stage7Return'}));

    feat = struct();
    for f = advFeatures(), feat.(f{1}) = false; end
    feat.payload = S.physics.payload; feat.dynamics = S.physics.dynamics;
    feat.energy = S.physics.energy; feat.atmosphere = S.physics.atmosphere;
    feat.perception = S.physics.altitudeModel;
    feat.gusts = S.gust_mps > 0;
    feat.localization = ~strcmp(P.localization, 'groundTruthOracle');
    feat.guidance = strcmp(P.controller, 'purePursuit');
    feat.actuation = S.valveDelay_s > 0 || strcmp(P.sprayCompensation, 'windLag') || ~strcmp(P.kernel, 'gaussian');
    A.enabled = any(cellfun(@(f) feat.(f), fieldnames(feat)));
    for f = advFeatures()
        A.(f{1}) = E.(f{1});
        A.(f{1}).enabled = feat.(f{1});
    end
    A.gusts.sigma_mps = max(S.gust_mps, 0.01); A.gusts.seed = S.gustSeed;
    if feat.localization, A.localization.mode = P.localization; end
    A.localization.seed = S.locSeed;
    if feat.localization && isfield(P, 'geolocateTargets'), A.localization.geolocateTargets = double(P.geolocateTargets); end
    if feat.guidance, A.guidance.mode = 'purePursuit'; end
    A.actuation.valveDelay_s = S.valveDelay_s;
    A.actuation.lagCompensation = double(strcmp(P.sprayCompensation, 'windLag'));
    A.actuation.kernel = P.kernel;
    A.perception.altitude_m = S.physics.altitude_m;
    if ~A.enabled
        s.adv = struct('enabled', false);          % nothing optional: keep config() defaults untouched
    else
        s.adv = A;
    end
    cfg = uiToConfig(s);
    cfg.internal2.seed = S.field.seed;
    cfg.internal2.coverage.method = P.coverage;                      % 'boustrophedon' = legacy
    cfg.internal2.treat.freeSpaceLegs = strcmp(P.coverage, 'polygonDecomposition');   % obstacle-aware for both passes
    if isfield(S.field, 'keepAllRuns'), cfg.internal2.field.keepAllRuns = logical(S.field.keepAllRuns); end
    if isfield(S.field, 'obstacle'), cfg.internal2.field.obstacles = obstaclePreset(S.field.obstacle, cfg.internal2.field.polygon); end
    if ~A.enabled, cfg.enhancements = c0.enhancements; cfg.enhancements.enableAdvancedRouting = s.advancedRouting; end

    R = pipelineRegistry();
    stages = {'perception', 'localization', 'coverage', 'controller', 'routing', 'sprayCompensation', 'kernel'};
    for i = 1:numel(stages)
        T = R.(stages{i});
        k = find(strcmp(T.id, P.(stages{i})), 1);
        info.(stages{i}) = struct('id', T.id{k}, 'label', T.label{k}, 'implementation', T.implementation{k}, 'status', T.status{k});
    end
    info.enabledFeatures = fieldnames(feat)';
    info.enabledFeatures = info.enabledFeatures(cellfun(@(f) feat.(f), info.enabledFeatures));
    info.calibration = 'UNCALIBRATED spray deposition; synthetic sensors; parametric detector; assumed hardware';
    info.hardwareProfile = S.hardwareProfile;
    info.hardwareProvenance = 'synthetic (config.m defaults)';
    if ~strcmp(S.hardwareProfile, 'assumedDefault')                   % ENHANCEMENT (opt-in, M5)
        [cfg, info.hardwareChanges, info.hardwareWarnings, prof] = applyHardwareProfile(cfg, S.hardwareProfile);
        info.hardwareProvenance = sprintf('%s v%s: %s', prof.id, prof.version, prof.provenance);
    end
end
