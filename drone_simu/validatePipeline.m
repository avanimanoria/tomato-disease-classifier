function [ok, errs, warns] = validatePipeline(pc)
%VALIDATEPIPELINE Reject unavailable / impossible choices; warn about ineffective ones.
%
%   [ok, errs, warns] = validatePipeline(pc). An invalid choice is never silently replaced.
    errs = {}; warns = {};
    R = pipelineRegistry();
    stages = {'perception', 'localization', 'coverage', 'controller', 'routing', 'sprayCompensation', 'kernel'};
    for i = 1:numel(stages)
        T = R.(stages{i});
        v = pc.pipeline.(stages{i});
        k = find(strcmp(T.id, v), 1);
        if isempty(k)
            errs{end+1} = sprintf('%s: unknown method "%s"', stages{i}, v); %#ok<AGROW>
        elseif ~T.available(k)
            errs{end+1} = sprintf('%s: "%s" is UNAVAILABLE (%s)', stages{i}, T.label{k}, T.note{k}); %#ok<AGROW>
        end
    end
    if ~any(strcmp(pc.mode, R.mode.id))
        errs{end+1} = sprintf('mode: unknown "%s"', pc.mode);
    end
    S = pc.scenario; P = pc.pipeline;
    if ~any(strcmp(S.field.shape, {'Rectangle', 'Trapezoid', 'UShape'})), errs{end+1} = 'field shape must be Rectangle, Trapezoid or UShape'; end
    if isfield(S.field, 'obstacle') && ~any(strcmp(S.field.obstacle, {'none', 'pond'})), errs{end+1} = 'obstacle must be none or pond'; end
    if ~strcmp(S.hardwareProfile, 'assumedDefault')
        try
            [~, ~, hw] = applyHardwareProfile(config(), S.hardwareProfile);
            warns = [warns, strcat('hardware profile: ', hw)];
            if ~(S.physics.payload || S.physics.dynamics || S.physics.energy)
                warns{end+1} = 'hardware profile has no effect unless the payload, dynamics or energy model is on';
            end
        catch e
            errs{end+1} = sprintf('hardware profile "%s" UNAVAILABLE: %s', S.hardwareProfile, e.message);
        end
    end
    if S.gust_mps < 0 || S.valveDelay_s < 0, errs{end+1} = 'gust and valve delay must be >= 0'; end
    if S.valveDelay_s > 0 && S.valveDelay_s > config().internal2.treat.settleTime && strcmp(P.sprayCompensation, 'windLag')
        errs{end+1} = 'valve-lag compensation needs the settle time (1 s) to be at least the valve delay';
    end
    % warnings: valid but ineffective / caveated combinations
    if ~S.wind.enabled && ~strcmp(P.sprayCompensation, 'none')
        warns{end+1} = 'wind is off: spray compensation has zero offset';
    end
    if strcmp(P.sprayCompensation, 'windLag') && S.valveDelay_s == 0
        warns{end+1} = 'valve delay is 0 s: lag compensation has no effect';
    end
    if S.gust_mps > 0 && ~S.wind.enabled
        warns{end+1} = 'gusts are only applied when wind is on';
    end
    if strcmp(P.controller, 'openLoop') && ~strcmp(P.localization, 'groundTruthOracle')
        warns{end+1} = 'open loop ignores the position estimate during the survey (it is used to start Pass-2 legs)';
    end
    if isfield(P, 'geolocateTargets') && P.geolocateTargets && strcmp(P.localization, 'groundTruthOracle')
        warns{end+1} = 'Target geolocation has no effect with the ground-truth oracle (targets are already at the true position).';
    end
    if strcmp(P.localization, 'groundTruthOracle')
        warns{end+1} = 'localization = ORACLE: the controller receives the true position (upper bound, not GPS-denied)';
    elseif strcmp(P.localization, 'errorModel')
        warns{end+1} = 'localization = error model: a PROXY (truth + modelled error), not a sensor-based estimator';
    end
    split = strcmp(S.field.shape, 'UShape') || (isfield(S.field, 'obstacle') && ~strcmp(S.field.obstacle, 'none'));
    if split && ~(isfield(S.field, 'keepAllRuns') && S.field.keepAllRuns)
        warns{end+1} = 'rows are split by the notch / obstacle but "keep all row pieces" is off: the shorter pieces (and their plants) are dropped';
    end
    if strcmp(P.coverage, 'polygonDecomposition') && ~split
        warns{end+1} = 'convex field without obstacles: polygon decomposition gives the same path as boustrophedon';
    end
    if ~strcmp(P.kernel, 'calibrated')
        warns{end+1} = 'spray deposition kernel is UNCALIBRATED: relative comparisons only';
    end
    if strcmp(pc.mode, 'oracle')
        warns{end+1} = 'ORACLE mode uses hindsight (outcomes) - research comparator, not deployable';
    end
    ok = isempty(errs);
end
