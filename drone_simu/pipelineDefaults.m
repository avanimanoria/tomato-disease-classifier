function pc = pipelineDefaults()
%PIPELINEDEFAULTS The LEGACY pipeline configuration (schema v1).
%
%   pc = pipelineDefaults() reproduces the dashboard default mission exactly (Baseline
%   preset: wind off, PID off, no compensation, nearest-neighbour, circular kernel,
%   parametric detector, ground-truth position) - verified by tests/PipelineBuilderTest.
%
%   A PIPELINE is one choice per algorithmic stage (pc.pipeline). A SCENARIO is the
%   field / environment / hardware condition and its seeds (pc.scenario). A MISSION is one
%   pipeline x scenario evaluation (runPipeline). resolvePipeline maps this struct onto the
%   existing engine parameters; there is no second simulator.

    pc.schemaVersion = 1;
    pc.mode = 'manual';                    % manual | bestFixed | scenarioSelector | oracle

    S.field = struct('shape', 'Trapezoid', 'length', 30, 'width', 14, 'bottom', 30, 'top', 18, 'height', 14, ...
        'rowStyle', 'Curved', 'rowSpacing', 2, 'plantSpacing', 0.5, 'seed', 42, ...
        'keepAllRuns', false, 'obstacle', 'none');   % shape also 'UShape' (concave, uses length / width)
    S.wind = struct('enabled', false, 'speed', 2.0, 'dirDeg', 90);
    S.gust_mps = 0;                        % 0 = steady wind; > 0 enables the gust model
    S.gustSeed = 7;
    S.valveDelay_s = 0;                    % > 0 enables the spray-actuation model
    S.locSeed = 3;
    S.droneSpeed = 1.5;
    S.physics = struct('payload', false, 'dynamics', false, 'energy', false, 'atmosphere', false, ...
        'altitudeModel', false, 'altitude_m', 2.0);
    S.hardwareProfile = 'assumedDefault';
    pc.scenario = S;

    P.perception = 'parametric';           % parametric | cnn (unavailable)
    P.localization = 'groundTruthOracle';  % groundTruthOracle | errorModel | imuDeadReckoning | flowOdometry | kalman | sensorFusion
    P.coverage = 'boustrophedon';          % boustrophedon | polygonDecomposition (unavailable)
    P.controller = 'openLoop';             % openLoop (PID off) | pid | purePursuit
    P.routing = 'nearestNeighbour';        % see pipelineRegistry
    P.sprayCompensation = 'none';          % none | wind | windLag | uncertaintyAware (unavailable)
    P.kernel = 'gaussian';                 % gaussian | windStretched | calibrated (unavailable)
    P.geolocateTargets = false;            % true = Pass-2 targets at the ESTIMATED plant position (needs an estimator)
    pc.pipeline = P;
end
