function sv = runSurveyPass(cfg, field)
%RUNSURVEYPASS Pass 1 only: fly the survey reference from its first point.
%
%   sv = runSurveyPass(cfg, field)
%   Returns world/ctrl (end state, handed to runTreatmentPass), log1, and the
%   Pass-1 time and distance. Detection is NOT done here (see detectPlants),
%   so one flight can be scored with several detector modes.

    world = struct('pos', field.surveyRef.pts(1, :), 'time', 0, 'distance', 0);
    if advOn(cfg, 'any'), world = initAdvancedWorld(world, cfg); end   % ENHANCEMENT (opt-in)
    if isfield(world, 'adv') && isfield(world.adv, 'sf')
        world.adv.landmarks = field.polygon;        % known corner posts = LiDAR landmarks (sensorFusion only)
    end
    ctrl = initInternal2Controller();
    [world, ctrl, log1] = flyReference(world, field.surveyRef, ctrl, cfg);

    sv.world    = world;
    sv.ctrl     = ctrl;
    sv.log1     = log1;
    sv.time     = world.time;
    sv.distance = world.distance;
end
