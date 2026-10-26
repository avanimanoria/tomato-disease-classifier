function cfg = config()
%CONFIG Central configuration for the Agricultural Drone Simulation.
%   Edit THIS file to change field size, spacing, speeds, or mode.
%   Every other file reads its settings from here - nothing is
%   hard-coded elsewhere.

    %% ---- FIELD PARAMETERS (Section 3 / 28 of the spec) ----
    cfg.fieldLength    = 20;   % meters (X direction)
    cfg.fieldWidth     = 10;   % meters (Y direction)
    cfg.rowSpacing     = 2;    % meters between zig-zag passes (Y direction)
    cfg.plantSpacing   = 0.5;  % meters between plants along a row (X direction)
    cfg.flightAltitude = 2;    % meters (Z)

    %% ---- DRONE PARAMETERS (used from Stage 2 onward) ----
    cfg.droneSpeed = 1.5;   % m/s
    cfg.dt         = 0.1;   % simulation timestep (s)

    %% ---- CAMERA PARAMETERS (used from Stage 3 onward) ----
    cfg.cameraFovRadius = 0.6; % m, radius of ground footprint below drone

    %% ---- MODE (Section 12) ----
    cfg.USE_REAL_MODEL = true;  % true = REAL ML MODE, false = DEMO MODE

    %% ---- DATASET / IMAGES (used from Stage 3/4 onward) ----
    cfg.datasetRoot = fullfile(pwd, 'dataset');
    cfg.imageRoot   = fullfile(pwd, 'dataset', 'plant_images'); % per-plant demo images

    %% ---- INTERNAL-2 (opt-in; ignored by Stage 1-7 and the dashboard) ----
    %  Only main_internal2.m / runInternal2Scenario.m read this block.
    %
    %  PARAMETER PROVENANCE TAGS used below:
    %    [EXISTING] value reused from the fields above (already in the project)
    %    [DERIVED]  computed from other parameters, not a free choice
    %    [ASSUMED]  engineering placeholder chosen for the demo. NOT taken from
    %               literature, a datasheet, or an experiment. Change freely.
    %  NO value in this block is literature-validated or experimentally
    %  validated. Results are RELATIVE comparisons between runs that share
    %  these assumptions, not predictions of real-world performance.
    cfg.internal2.enabled = false;   % must be set true by the caller to run Internal-2
    cfg.internal2.seed    = 42;      % [ASSUMED] seed for disease layout + detection draws

    % -- field geometry (all lengths in m) --
    cfg.internal2.field.polygon        = [0 0; 30 0; 24 14; 6 14]; % [ASSUMED] trapezoid vertices [x y], m
    cfg.internal2.field.rowFirstOffset = 1.5;   % [ASSUMED] y of first row before curvature, m (>= edgeMargin + rowCurveAmp)
    cfg.internal2.field.rowCurveAmp    = 0.4;   % [ASSUMED] sinusoidal row offset amplitude, m
    cfg.internal2.field.rowCurveLambda = 30;    % [ASSUMED] sinusoidal row wavelength, m
    cfg.internal2.field.edgeMargin     = 1.0;   % [ASSUMED] rows/plants kept this far inside boundary, m
    cfg.internal2.field.rowSampleStep  = 0.1;   % [ASSUMED] numerical sampling step along rows, m
    cfg.internal2.field.diseaseFraction = 0.15; % [ASSUMED] fraction of plants truly diseased (matches the
                                                %   ~15% used by detectDiseaseDemo.m, which is also an assumption)
    % row spacing and plant spacing reuse cfg.rowSpacing / cfg.plantSpacing  [EXISTING]
    cfg.internal2.field.keepAllRuns    = false; % ENHANCEMENT (opt-in): keep every row piece (concave / obstacles)
    cfg.internal2.field.obstacles      = {};    % ENHANCEMENT (opt-in): no-crop / no-fly polygons {Kx2}
    % -- Pass-1 coverage planner (ENHANCEMENT, opt-in; 'boustrophedon' = legacy joined rows) --
    cfg.internal2.coverage.method      = 'boustrophedon';  % boustrophedon | polygonDecomposition
    cfg.internal2.coverage.clearance_m = 0.5;   % [ASSUMED] min connector clearance from boundary / obstacles

    % -- Pass-1 detection model (parametric stand-in; NOT the CNN) --
    %  Per-plant uniform draws are fixed at field generation so every run
    %  sees identical detection outcomes for plants it actually images.
    cfg.internal2.detect.pDetectDiseased = 0.95; % [ASSUMED] P(flag | truly diseased, imaged)
    cfg.internal2.detect.pFalsePositive  = 0.03; % [ASSUMED] P(flag | truly healthy, imaged)
    % camera footprint radius reuses cfg.cameraFovRadius                       [EXISTING]
    cfg.internal2.detect.mode = 'stochastic';    % 'stochastic' (the default demo behaviour) | 'perfectVisible'.
                                                 %   perfectVisible = perfect classification CONDITIONAL ON OBSERVATION:
                                                 %   plants outside the camera footprint stay unobserved/undetected.

    % -- wind (steady; no turbulence) --
    cfg.internal2.wind.enabled = false;  % set per scenario by main_internal2
    cfg.internal2.wind.speed   = 2.0;    % [ASSUMED] wind speed, m/s
    cfg.internal2.wind.dirDeg  = 90;     % [ASSUMED] direction wind blows TOWARD, deg from +X (90 = +Y)

    % -- vehicle (kinematic point mass; commanded velocity is realised exactly) --
    cfg.internal2.vehicle.windCoupling = 0.01;  % [ASSUMED] fraction of wind velocity that becomes ground-velocity
                                                %   disturbance of the drone (lumped; a real attitude loop and
                                                %   airframe drag are NOT modelled), dimensionless
    % drone speed / dt reuse cfg.droneSpeed / cfg.dt                           [EXISTING]

    % -- controller --
    cfg.internal2.ctrl.enabled         = false; % set per scenario. false = open-loop reference-velocity feed-forward
    cfg.internal2.ctrl.Kp              = 1.5;   % [ASSUMED] cross-track P gain, (m/s)/m
    cfg.internal2.ctrl.Ki              = 0.4;   % [ASSUMED] cross-track I gain, (m/s)/(m*s)
    cfg.internal2.ctrl.Kd              = 0.1;   % [ASSUMED] cross-track D gain, (m/s)/(m/s)
    cfg.internal2.ctrl.KpAlong         = 1.0;   % [ASSUMED] along-track P gain, (m/s)/m
    cfg.internal2.ctrl.integralLimit   = 1.0;   % [ASSUMED] anti-windup limit on |integral of cross error|, m*s
    cfg.internal2.ctrl.maxCommandSpeed = 2.5;   % [ASSUMED] saturation of commanded speed, m/s

    % -- Pass-2 treatment mission --
    cfg.internal2.treat.settleTime = 1.0;  % [ASSUMED] hold at release point before spraying, s
    % spray duration is cfg.internal2.spray.duration below
    cfg.internal2.treat.routing = 'nearestNeighbour';  % Pass-2 routing: 'fixedOrder' | 'nearestNeighbour' | 'stage7Return'
    % Travel-speed multiplier on cfg.droneSpeed per routing strategy (settle/dwell unaffected).
    % stage7Return = 0.6 reproduces the original Stage-7 navigateToTarget/returnToPath speed [EXISTING];
    % Experiment C's equal-speed condition overrides all three to the same value.
    cfg.internal2.treat.speedFactor.fixedOrder       = 1.0;
    cfg.internal2.treat.speedFactor.nearestNeighbour = 1.0;
    cfg.internal2.treat.speedFactor.stage7Return     = 0.6;
    cfg.internal2.treat.freeSpaceLegs = false;  % ENHANCEMENT (opt-in): Pass-2 / refill / return legs routed around
                                                %   obstacles and concave boundary (freeSpacePath); false = straight legs

    % -- spray model (simplified relative model, NOT CFD) --
    cfg.internal2.spray.compensate        = false; % set per scenario. true = release upwind of target
    cfg.internal2.spray.releaseHeight     = 1.0;   % [ASSUMED] nozzle height above plant canopy, m
    cfg.internal2.spray.nozzleHalfAngle   = 15;    % [ASSUMED] cone half-angle, deg
    cfg.internal2.spray.footprintRadius   = [];    % [DERIVED] releaseHeight*tand(halfAngle), m (filled at run time)
    cfg.internal2.spray.sigmaFraction     = 0.5;   % [ASSUMED] Gaussian sigma = sigmaFraction * footprintRadius
    cfg.internal2.spray.flowRate          = 25;    % [ASSUMED] mL/s (x duration 2 s = 50 mL, same order as the
                                                   %   placeholder baseVolumePerPlant_mL in calculatePesticideCapacity.m,
                                                   %   which is itself a placeholder)
    cfg.internal2.spray.duration          = 2;     % s [EXISTING] value of sprayDuration in sprayTarget.m
    cfg.internal2.spray.dropletFallSpeed  = 1.5;   % [ASSUMED] mean droplet settling speed, m/s
    cfg.internal2.spray.driftFactor       = 1.0;   % [ASSUMED] fraction of wind velocity the droplets acquire
    cfg.internal2.spray.windEstimateScale = 1.0;   % [ASSUMED] drone's wind knowledge used for compensation
                                                   %   (1 = perfect; <1 under-compensates)
    cfg.internal2.spray.gridCell          = 0.05;  % [ASSUMED] deposition grid resolution, m (numerical)
    cfg.internal2.spray.gridMargin        = 4.0;   % [ASSUMED] grid extends this far beyond polygon bbox, m

    % -- metrics --
    cfg.internal2.metrics.canopyRadius        = 0.2;  % [ASSUMED] plant "target zone" radius, m (< plantSpacing/2)
    cfg.internal2.metrics.treatedDoseFraction = 0.30; % [ASSUMED] plant counts as treated if its canopy disc gets
                                                      %   >= this fraction of one nominal spray volume
    cfg.internal2.metrics.crossTrackWindow    = 3.0;  % [ASSUMED] arclength window around the reference point used
                                                      %   to pick the active segment for cross-track error, m
    cfg.internal2.metrics.stage7SpeedFactor   = 0.6;  % [EXISTING] approach/return speed factor in navigateToTarget.m

    %% ---- EXPERIMENT HARNESS (main_experiments.m; ignored by everything else) ----
    %  [SWEEP] = the independent variable of an experiment, chosen for coverage of the
    %  range, NOT tuned to produce a result. No physical parameter lives in this block:
    %  all physics stays in cfg.internal2 above and is never modified by a sweep other
    %  than the swept variable itself (wind speed).
    cfg.experiments.outDir = fullfile(pwd, 'results');   % raw .mat, CSV tables, PNG figures, cfg snapshot

    % A/B: vehicle-disturbance sweep. One Pass-1 flight per (wind speed, PID) is scored
    % with BOTH detector modes (perfectVisible = B's clean geometry result; stochastic
    % = reported alongside). wind speed 0 is the no-wind control for each PID state.
    cfg.experiments.A.windSpeeds = [0 0.5 1.0 1.5 2.0 2.5];   % [SWEEP] m/s
    cfg.experiments.A.pidStates  = [false true];              % [SWEEP]
    cfg.experiments.A.detectModes = {'perfectVisible', 'stochastic'};

    % C: routing comparison on a FROZEN target set: all truly diseased plant coordinates,
    % in a fixed boustrophedon (survey-row) order that does not depend on detection.
    % Start point = last point of the nominal survey reference. Geometric estimates only.
    cfg.experiments.C.targetCounts = [];   % [] = full set only; e.g. [10 20] adds seeded subsets of that size
    cfg.experiments.C.subsetSeed   = 7;    % [SWEEP] seed for subset selection (private stream)

    % D: spray-only wind sweep. Drone hovers exactly at the release point of every truly
    % diseased target; no navigation, no detector. Modelled drift distance is recorded
    % for every wind speed and is the primary x-variable of the results.
    cfg.experiments.D.windSpeeds = 0:0.25:2.5;   % [SWEEP] m/s

    % D2: compensation with an imperfect wind estimate: the compensator uses alpha*W while the
    % spray cloud experiences the true W. Swept over these alphas x the D wind speeds.
    cfg.experiments.D2.alphas = [0 0.5 0.75 0.9 1.0 1.1 1.25 1.5];   % [SWEEP] windEstimateScale

    % E: integrated mission. Each entry is a preset NAME (see scenarioPresets.m), 'Custom'
    % (use cfg as supplied), or a struct(wind, pid, comp [, name, windSpeed]). Names are
    % labels only; the switches are all that matter.
    cfg.experiments.E.scenarios = {'Baseline', 'No wind + PID', 'Disturbed', ...
                                   'Navigation Corrected', 'Fully Corrected'};

    %% ---- OPTIONAL ENHANCEMENTS (all OFF by default = original behaviour) ----
    %  A flag is added here only when its feature exists. With every flag false the
    %  engine follows exactly the original code paths (golden-verified).
    cfg.enhancements.enableAdvancedRouting = false;  % allows treat.routing = 'nearestNeighbour2opt' |
                                                     %   'cheapestInsertion' (planRouteAdvanced.m)

    % Advanced physics: MASTER switch + one switch per feature (both must be true).
    % Every value below is an [ASSUMED] placeholder, not a datasheet or measurement.
    cfg.enhancements.enableAdvancedPhysics = false;

    cfg.enhancements.payload.enabled           = false; % tank level falls while spraying -> mass falls; refill trips
    cfg.enhancements.payload.dryMass_kg        = 5.0;   % [ASSUMED] drone without liquid
    cfg.enhancements.payload.tankCapacity_L    = 2.0;   % [EXISTING] default of calculatePesticideCapacity.m
    cfg.enhancements.payload.liquidDensity_kgL = 1.0;   % [ASSUMED] water-like spray mix
    cfg.enhancements.payload.refillTime_s      = 30;    % [ASSUMED] time on the ground to refill

    cfg.enhancements.dynamics.enabled            = false; % mass-dependent point-mass dynamics + physical wind drag
    cfg.enhancements.dynamics.velTimeConstant_s  = 0.3;   % [ASSUMED] velocity-loop response time
    cfg.enhancements.dynamics.thrustToWeightFull = 2.0;   % [ASSUMED] max thrust / weight at full tank
    cfg.enhancements.dynamics.dragArea_m2        = 0.08;  % [ASSUMED] drag coefficient x frontal area
    cfg.enhancements.dynamics.airDensity_kgm3    = 1.225; % sea-level standard air

    cfg.enhancements.energy.enabled          = false; % momentum-theory power, battery use and reserve
    cfg.enhancements.energy.battery_Wh       = 222;   % [ASSUMED] e.g. 6S 10 Ah pack
    cfg.enhancements.energy.reservePct       = 20;    % [ASSUMED] minimum reserve
    cfg.enhancements.energy.rotorDiskArea_m2 = 0.45;  % [ASSUMED] total disk area (4 x 15-inch props)
    cfg.enhancements.energy.efficiency       = 0.6;   % [ASSUMED] figure of merit x motor/ESC efficiency
    cfg.enhancements.energy.avionics_W       = 20;    % [ASSUMED]

    cfg.enhancements.gusts.enabled     = false; % zero-mean gusts on the steady wind (vehicle AND spray)
    cfg.enhancements.gusts.sigma_mps   = 0.5;   % [ASSUMED] gust RMS per axis
    cfg.enhancements.gusts.periodMin_s = 2;     % [ASSUMED]
    cfg.enhancements.gusts.periodMax_s = 20;    % [ASSUMED]
    cfg.enhancements.gusts.nComponents = 12;
    cfg.enhancements.gusts.seed        = 7;

    cfg.enhancements.atmosphere.enabled         = false; % droplet size, evaporation (humidity), rotor downwash
    cfg.enhancements.atmosphere.temperature_C   = 30;    % [ASSUMED]
    cfg.enhancements.atmosphere.relHumidity_pct = 50;    % [ASSUMED]
    cfg.enhancements.atmosphere.dropletVMD_um   = 250;   % [ASSUMED] "medium" spray quality
    cfg.enhancements.atmosphere.downwashFactor  = 0.1;   % [ASSUMED] fraction of rotor induced velocity reaching the droplets

    cfg.enhancements.perception.enabled               = false; % altitude drives camera footprint, detection, release height
    cfg.enhancements.perception.altitude_m            = 2.0;      % [EXISTING] cfg.flightAltitude
    cfg.enhancements.perception.cameraHalfFOV_deg     = atand(0.3); % gives the existing 0.6 m footprint at 2 m
    cfg.enhancements.perception.canopyHeight_m        = 1.0;      % gives the existing 1.0 m release height at 2 m
    cfg.enhancements.perception.detectRefAltitude_m   = 2.0;      % [ASSUMED] no detection loss up to here
    cfg.enhancements.perception.detectAltitudeScale_m = 3.0;      % [ASSUMED] detection falloff length above it

    cfg.enhancements.localization.enabled             = false; % GPS-denied style estimate: odometry drift + periodic fixes
    cfg.enhancements.localization.randomWalk_m_sqrt_s = 0.01;  % [ASSUMED]
    cfg.enhancements.localization.scaleError          = 0.01;  % [ASSUMED] 1% odometry scale error along the motion
    cfg.enhancements.localization.fixInterval_s       = 30;    % [ASSUMED] absolute fix (e.g. landmark) period
    cfg.enhancements.localization.fixNoise_m          = 0.05;  % [ASSUMED]
    cfg.enhancements.localization.seed                = 3;
    cfg.enhancements.localization.mode                = 'errorModel'; % 'errorModel' (error model above) |
                                                     %   'imuDeadReckoning' (integrate noisy, biased accelerometer; weak baseline) |
                                                     %   'flowOdometry' (integrate optical-flow velocity, no fixes) |
                                                     %   'kalman' (optical-flow prediction + periodic absolute fix, linear KF)
    cfg.enhancements.localization.imuAccelNoise_mps2  = 0.05;  % [ASSUMED] accelerometer white noise
    cfg.enhancements.localization.imuAccelBias_mps2   = 0.005; % [ASSUMED] residual accelerometer bias
    cfg.enhancements.localization.flowVelNoise_mps    = 0.05;  % [ASSUMED] optical-flow velocity noise
    % mode 'sensorFusion' (EKF: IMU + optical flow + LiDAR ranges to the field corner posts)
    cfg.enhancements.localization.lidarRange_m        = 25;    % [ASSUMED] max range to a corner post
    cfg.enhancements.localization.lidarNoise_m        = 0.05;  % [ASSUMED] range noise
    cfg.enhancements.localization.lidarRate_Hz        = 1;     % [ASSUMED] range update rate
    cfg.enhancements.localization.flowDropoutProb     = 0.05;  % [ASSUMED] optical-flow dropout probability
    cfg.enhancements.localization.geolocateTargets    = 0;     % 1 = Pass-2 targets at the plant position ESTIMATED from
                                                               %   the drone's belief when it saw the plant (truth firewall);
                                                               %   0 = original behaviour (true plant coordinates)

    cfg.enhancements.actuation.enabled            = false; % spray valve delay (+ lag compensation) and spray kernel shape
    cfg.enhancements.actuation.valveDelay_s       = 0.5;   % [ASSUMED] command-to-flow delay (same order as reported PWM lag)
    cfg.enhancements.actuation.lagCompensation    = 0;     % 1 = command the valve valveDelay_s early
    cfg.enhancements.actuation.kernel             = 'gaussian'; % 'gaussian' (original circular) | 'windStretched' (UNCALIBRATED ellipse)
    cfg.enhancements.actuation.windStretch_perMps = 0.3;   % [ASSUMED] along-wind sigma growth per m/s of wind

    cfg.enhancements.guidance.enabled        = false; % path-following controller choice
    cfg.enhancements.guidance.mode           = 'pid'; % 'pid' (original controller) | 'purePursuit' (look-ahead guidance)
    cfg.enhancements.guidance.lookahead_m    = 1.0;   % [ASSUMED] pure-pursuit look-ahead distance
    cfg.enhancements.guidance.holdGain_per_s = 1.5;   % [ASSUMED] position-hold gain while settling / spraying

    cfg.enhancements.safety.enabled          = false; % advisories only (no behaviour change)
    cfg.enhancements.safety.maxSprayWind_mps = 3.0;   % [ASSUMED] check the product label / local rules
end
