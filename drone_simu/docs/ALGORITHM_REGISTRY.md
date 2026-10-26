# Algorithm registry

The single source is `pipelineRegistry.m`; the Pipeline Builder reads it, and so does this table. "Available" means the method runs through the same mission engine (`runInternal2Scenario`). Unavailable methods are shown in the UI as `(UNAVAILABLE)` and rejected by `validatePipeline` (fail closed).

**Wall time** is one complete mission measured with `runPipeline`:
- Scenario: disturbed (wind 2 m/s, PID), default trapezoid, 45 flagged targets.
- Machine: Intel Core Ultra 7 255U, MATLAB R2026b.
- Coverage rows use the UShape field.

It covers the whole mission (both passes plus metrics), not the method alone.

All parameter values are `[ASSUMED]` unless stated otherwise; see `CALIBRATION_AND_DATA_PROVENANCE.md`.

## Perception (Pass-1 classification)

| id | Available | File | Inputs → outputs | Key parameters | Assumptions |
|---|---|---|---|---|---|
| `parametric` | yes (default) | `detectPlants.m` | true track, camera radius → seen set, flagged targets | `cameraFovRadius` 0.6 m; P(detect \| diseased, imaged) 0.95; P(FP) 0.03 | synthetic stand-in, fixed per-plant draws |
| `cnn` | **no** | `perceptionCNNAdapter.m` | — | — | blocked: model, images, linkage, class map (`cnnAvailability.m`) |

## Localization (what the controller / planner believe)

| id | Available | File | Method | Parameters (config `enhancements.localization`) | Wall time |
|---|---|---|---|---|---|
| `groundTruthOracle` | yes (default) | `getEstimatedState.m` | true position (upper bound, not GPS-denied) | — | 2.05 s |
| `errorModel` | yes | `stepVehicleAdvanced.m` | PROXY: truth + random-walk / scale error with resets | drift, scale, fix interval | 2.31 s |
| `imuDeadReckoning` | yes | `stepVehicleAdvanced.m` | double-integrated accelerometer, no fixes | IMU noise / bias | 1.05 s |
| `flowOdometry` | yes | `stepVehicleAdvanced.m` | integrated optical-flow velocity, no fixes | flow noise, scale error | 2.11 s |
| `kalman` | yes | `stepVehicleAdvanced.m` | linear position KF, flow + periodic fixes (the fix source is not modelled physically) | fix interval / noise | 1.88 s |
| `sensorFusion` | yes | `sfSensors.m`, `sensorFusionInit.m`, `sensorFusionStep.m` | 6-state planar EKF [p, v, accel bias]. IMU predict at 10 Hz; flow velocity update (5 % dropout); LiDAR ranges to field corner posts at 1 Hz within 25 m; NIS gating χ² 99.9 % | `lidarRange_m` 25, `lidarNoise_m` 0.05, `lidarRate_Hz` 1, `flowDropoutProb` 0.05, IMU / flow noise | 2.86 s |

Option `geolocateTargets` (pipeline checkbox, default off) records Pass-2 targets at the estimated plant position, with scoring by plant identity.

## Pass-1 coverage

| id | Available | File | Method | Parameters | Wall time |
|---|---|---|---|---|---|
| `boustrophedon` | yes (default) | `generateIrregularField.m` | fly the crop rows in alternating directions, joined by straight connectors | `rowSpacing` 2 m, `edgeMargin` 1 m | 1.61 s |
| `polygonDecomposition` | yes | `planCoverageDecomposition.m`, `freeSpacePath.m` | Steps: boustrophedon cell decomposition over row pieces; serpentine per cell; greedy cell order; visibility-graph collision-free connectors; densified validation (error `planCoverageDecomposition:infeasible`). Also routes Pass-2, refill and return legs around obstacles (`treat.freeSpaceLegs`) | `coverage.clearance_m` 0.5 | 1.80 s |

Scenario options used with coverage:
- field shape `UShape` (concave),
- `keepAllRuns` (keep every row piece),
- obstacle `pond`.

On convex fields without obstacles the two methods produce the identical path (tested).

## Path following (controller)

| id | Available | File | Notes | Wall time |
|---|---|---|---|---|
| `openLoop` | yes (default) | `pidCrossTrackController.m` | feed-forward only (PID off) | 1.01 s |
| `pid` | yes | `pidCrossTrackController.m` | cross-track PID plus along-track P, saturated at `maxCommandSpeed` 2.5 m/s | 1.62 s |
| `purePursuit` | yes | `purePursuitController.m` | lookahead pursuit; gains not tuned | 1.80 s |

## Pass-2 routing (order of flagged targets)

| id | Available | File | Notes | Wall time |
|---|---|---|---|---|
| `fixedOrder` | yes | `runTreatmentPass.m` | detection order | 1.71 s |
| `nearestNeighbour` | yes (default) | `planTreatmentRoute.m` | greedy | 1.63 s |
| `nearestNeighbour2opt` | yes | `planRouteAdvanced.m` | NN + 2-opt | 1.68 s |
| `nearestNeighbourOrOpt` | yes | `planRouteAdvanced.m` | NN + 2-opt + Or-opt | 1.96 s |
| `cheapestInsertion` | yes | `planRouteAdvanced.m` | — | 1.65 s |
| `antColony` | yes | `planRouteAdvanced.m` | seeded ACO + 2-opt | 2.15 s |
| `stage7Return` | yes | `runTreatmentPass.m` | original Stage 7: return to the survey path after each target, at 0.6× speed | 1.84 s |
| `riskAware` | **no** | — | manual M6, not implemented | — |

All routers order targets by Euclidean distance.

## Spray compensation

| id | Available | File | Notes | Wall time |
|---|---|---|---|---|
| `none` | yes (default) | `sprayContext.m` | release directly above the target | 1.82 s |
| `wind` | yes | `sprayContext.m`, `advSprayPlan.m` | upwind offset from mean wind × `windEstimateScale` | 1.72 s |
| `windLag` | yes | `advActuatedDeposition.m` | wind offset plus the valve commanded `valveDelay_s` early; needs delay ≤ 1 s settle | 1.04 s |
| `uncertaintyAware` | **no** | — | not implemented | — |

## Deposition kernel

| id | Available | File | Status |
|---|---|---|---|
| `gaussian` | yes (default) | `depositSpray.m` | UNCALIBRATED circular Gaussian |
| `windStretched` | yes | `advDepositKernel.m` | UNCALIBRATED ellipse, along-wind σ × (1 + 0.3·\|w\|) |
| `calibrated` | **no** | — | blocked: no deposition dataset supplied |

## Run modes

| id | Notes |
|---|---|
| `manual` | runs the selected pipeline |
| `bestFixed` | best fixed configuration saved by Experiment F (controller + spray stages only) |
| `scenarioSelector` | saved Experiment F selector. Fails closed (`runPipeline:selectorOutOfScope`) outside its trained scenarios |
| `oracle` | research only: runs all 6 controller × spray choices and keeps the best in hindsight. Non-deployable |
