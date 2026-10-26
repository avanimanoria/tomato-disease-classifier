# Changelog

Every change is additive and opt-in. The **rollback flag** is the setting that restores legacy behaviour, and it is also the default. Reverting a commit removes the feature entirely.

## Manual V1 (`feature/manual-v1`)

| Commit | Change | Rollback flag / default | Tests |
|---|---|---|---|
| `233b195` | Phase 0: golden snapshots, frozen checksums, `runAllTests` regression gate, 8 test classes (23 tests) | — (test infrastructure only) | all |
| `f7c1bc8` | Phase 1: PIPELINE BUILDER tab; PipelineConfig schema v1 (`pipelineDefaults` / `resolvePipeline` / `runPipeline`); paired comparison; save / load / export; modes manual / bestFixed / scenarioSelector / oracle; CNN adapter (UNAVAILABLE) | Builder tab is separate from MISSION; `pipelineDefaults()` = legacy | PipelineBuilderTest, ConfigRoundTripTest, ComparisonFairnessTest |
| `6f98f6e` | Phase 2: Experiment F audit; `runExperimentF` refuses to overwrite a frozen run | `opts.overwrite` (default false) | ExperimentFAuditTest |
| `8c96ad8` | Phase 4: `localization.mode = 'sensorFusion'` (EKF: IMU + flow + LiDAR landmarks); target geolocation | `localization.enabled = false`, `mode ≠ 'sensorFusion'`; `localization.geolocateTargets = 0`; `pipeline.geolocateTargets = false` | TruthFirewallTest |
| `fbda452` | Phase 5: polygon-decomposition coverage; concave `UShape`; obstacles; keep all row pieces; coverage metrics | `internal2.coverage.method = 'boustrophedon'`, `internal2.field.keepAllRuns = false`, `internal2.field.obstacles = {}`, `scenario.field.obstacle = 'none'` | CoverageDecompositionTest |
| `56aecf6` | Phase 6: bounded UNCALIBRATED spray study (`results/spray_uncalibrated_v1`) | study only; engine untouched | SprayStudyTest |
| `4a8db8f` | Phase 7: hardware profiles with enforced provenance | `scenario.hardwareProfile = 'assumedDefault'` (== config.m) | HardwareProfileTest |
| `c56254d` | Obstacle-aware Pass-2 / refill / return legs (`freeSpacePath`) | `internal2.treat.freeSpaceLegs = false` (enabled only with coverage `polygonDecomposition`) | CoverageDecompositionTest |
| (this) | Hand-off docs, `runDemonstrations.m` | — | demonstrations |

Also added in these commits:
- `computeRunMetrics` gained a "Coverage" group (additive rows).
- The dashboard's advanced panels became scrollable and gained new parameter labels.

## Before manual V1 (`main`)

| Tag / commit | Change |
|---|---|
| `v1.0-pre-enhancements` (`faaa987`) | Internal-2 engine, V2 dashboard, Experiments A–E, D2, ablation |
| `v2.0-enhancements` (`331f5c1`) | Opt-in advanced routing and advanced physics (payload, dynamics, energy, gusts, atmosphere, perception, localization, safety, actuation, guidance); research extensions; Experiment F; COMPARATIVE ANALYSIS tab. Master switches `enableAdvancedRouting` and `enableAdvancedPhysics` default to false |
