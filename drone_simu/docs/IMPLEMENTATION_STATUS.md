# Implementation status — DRONE_IMPLEMENTATION_COMPLETION_MANUAL_V1

Branch `feature/manual-v1` (on top of tag `v2.0-enhancements`). Regression gate `runAllTests`: **65 / 65 PASS** (16 test files).
Demonstrations `runDemonstrations`: **all pass**. Status values:
- **DONE**: implemented, tested, behind a flag.
- **PARTIAL**: the part that can be done without external inputs is done; the rest is listed.
- **BLOCKED**: needs an external artifact that was not supplied.
- **NOT DONE**: not attempted, with the reason.

| # | Requirement | Status | Code | Evidence (tests / outputs) |
|---|---|---|---|---|
| 1.1 | Inventory and freeze | DONE | `golden/enh_checkpoint/manifest_pre_enhancements.csv`, git tags `v1.0-pre-enhancements`, `v2.0-enhancements`, `golden/frozen_checksums.csv` (70 files) | `FrozenExperimentIntegrityTest` |
| 1.2 | Compatibility invariants | DONE | every new feature behind its own flag (see `CHANGELOG.md`) | `AdvancedOffParityTest`, `LegacyMissionGoldenTest`, `PipelineBuilderTest/testLegacyReproducesGolden` |
| 1.3 | Automated regression gate | DONE | `runAllTests.m` → `test_reports/regression_*.txt` | 65 tests (23 at Phase 0) |
| 2.1 | Minimum selectable pipeline | DONE | `pipelineDefaults.m`, `pipelineRegistry.m`, `validatePipeline.m`, `resolvePipeline.m`, `runPipeline.m` | `PipelineBuilderTest/testEveryOptionChangesEngine` |
| 2.2 | UI acceptance contract | DONE | `pipelineBuilderView.m`, PIPELINE BUILDER tab in `AgriculturalDroneDashboardV2.m` | `PipelineBuilderTest/testUiFlow`, `UIStateTest` |
| 2.3 | Configuration architecture | DONE | PipelineConfig schema v1: `savePipelineConfig.m` / `loadPipelineConfig.m`, SHA-256 `pipelineHash.m` | `ConfigRoundTripTest` |
| 2.4 | Manual run test | DONE | — | `PipelineBuilderTest/testManualRunSequence` |
| — | Paired comparison | DONE | `comparePipelineRuns.m` (refuses unpaired runs) | `ComparisonFairnessTest`, demonstration 3 |
| 3 | Experiment F audit | DONE | `auditExperimentF.m` → `docs/EXPERIMENT_F_AUDIT.md`, `audit/experiment_inventory.csv` | `ExperimentFAuditTest` (623 = 35 + 432 + 144 + 12, no leakage) |
| M1 | CNN perception | PARTIAL / **BLOCKED** | adapter `perceptionCNNAdapter.m`, availability `cnnAvailability.m`; choice shown as UNAVAILABLE | `PipelineBuilderTest/testUnavailableFailClosed`, demonstration 5. Blocked on: trained model, images, plant-to-image linkage, class mapping and preprocessing spec |
| M2 | GPS-denied sensor estimator | DONE (with stated limits) | `sfSensors.m`, `sensorFusionInit.m`, `sensorFusionStep.m`, `getEstimatedState.m`; target geolocation in `runInternal2Scenario.m` | `TruthFirewallTest` (8). RMSE 0.055 m, NEES 4.9 (ideal 2: mildly overconfident), NIS 1.74, 0.2 % gated |
| M3 | Pass-1 polygon coverage | DONE | `planCoverageDecomposition.m`, `freeSpacePath.m`, `generateIrregularField.m` (keepAllRuns, obstacles), `coverageMetrics.m`, obstacle-aware legs in `runTreatmentPass.m` | `CoverageDecompositionTest` (8) |
| M4 | Spray calibration | PARTIAL — calibrated kernel **BLOCKED** | bounded study `runSprayUncertaintyStudy.m` → `results/spray_uncalibrated_v1/` | `SprayStudyTest` (4). No deposition dataset was supplied; kernel stays UNCALIBRATED |
| M5 | Sourced hardware / crop profiles | PARTIAL — sourced profiles **BLOCKED** | `profiles/*.json`, `loadHardwareProfile.m`, `applyHardwareProfile.m`, `checkProfileFeasibility.m`, template `profiles/TEMPLATE_sourced_profile.json.txt` | `HardwareProfileTest` (6). Only the synthetic `assumedDefault` profile ships, and no datasheet numbers were invented. Crop / canopy profiles: NOT DONE |
| M6 | Risk / energy-aware router | NOT DONE (optional, "not essential") | listed as UNAVAILABLE `riskAware` | — |
| M7 | H4 extension and robustness | NOT DONE | depends on M1, M4 and M5 data | — |
| 5 / Phase 8 | Final held-out experiment (F2) and bundle | NOT DONE (deferred) | the reproducibility tooling exists (`REPRODUCE_RESULTS.md`) | See "Phase 8" below |
| 8 | Hand-off documents | DONE | `docs/*.md`, `CHANGELOG.md` | this folder |

## Phase-by-phase summary (commits)

| Phase | Commit | Result |
|---|---|---|
| 0 | `233b195` | Golden snapshots `golden/legacy_mission_golden.mat` (5 missions), checksums, regression gate |
| 1 | `f7c1bc8` | Pipeline Builder tab, paired comparison, PipelineConfig schema v1, saved-model modes |
| 2 | `6f98f6e` | Experiment F audit (exact 623 reconciliation, leakage checks, H1–H4) and frozen-run protection |
| 3 | (in 1) | CNN adapter and UNAVAILABLE choice. Real integration blocked |
| 4 | `8c96ad8` | `sensorFusion` EKF, truth firewall, opt-in target geolocation |
| 5 | `fbda452`, `c56254d` | Polygon cell decomposition coverage, concave `UShape` field, `pond` obstacle, obstacle-aware Pass-2 legs |
| 6 | `56aecf6` | Bounded UNCALIBRATED spray study, valve delay for stopped / hover / moving release |
| 7 | `4a8db8f` | Hardware profile infrastructure with enforced provenance |
| 8 docs | this commit | Hand-off documents and `runDemonstrations.m` |

## Known limitations (stated, not hidden)

- **sensorFusion**:
  - Yaw is assumed known, and no gyro is simulated.
  - The flow scale factor is not estimated; it only inflates R.
  - Landmark (corner-post) positions are assumed surveyed and exact.
  - NEES ≈ 4.9 against an ideal of 2, so the filter is mildly overconfident, consistently across gust levels.
  - There is no reset policy, because none is needed while posts are in range. With every post out of range the filter dead-reckons on IMU and flow.
- **Target geolocation** is opt-in. The default (off) keeps the legacy behaviour, where Pass-2 targets sit at the true plant coordinates. This is a truth leak in the legacy mode and is labelled as such in the builder warnings for the oracle.
- **Coverage**:
  - Pass-2 *ordering* (NN, Or-opt, ACO and the others) still uses Euclidean distances, so with obstacle-aware legs the "planned Pass-2 route" metric underestimates the flown distance. The flown distance is reported separately.
  - Turn dynamics are not constrained; corners are tracked by the existing controller.
  - Altitude is constant.
  - Obstacles are polygons: the `pond` preset in the builder, or any polygon via `cfg.internal2.field.obstacles`.
- **Moving release** is evaluated at kernel level only. The mission engine still sprays only after settling.
- **The spray study's compensation benefit** is an upper bound, because the compensator knows the true drift parameters. Wind-knowledge mismatch is covered separately by Experiment D2.

## Phase 8 (F2) — why deferred, and a ready design

The manual places M7 and Phase 8 after M1–M5. Three of their inputs are unavailable:
- the CNN (M1),
- calibration data (M4),
- sourced hardware profiles (M5).

An F2 run now would re-test the same synthetic and uncalibrated setup as Experiment F, plus two new modules (sensorFusion, polygon coverage). The recommended design, ready to run when wanted, follows manual section 5.2:
- A new folder `results/benchmark_F2/` with its own manifest; Experiment F stays frozen.
- Factors:
  - localization {kalman, sensorFusion}
  - controller {pid, purePursuit}
  - spray {wind, windLag}
  - gust {0, 0.3, 0.6}
  - valve delay {0, 0.5}
  - field family {Trapezoid, UShape + keepAllRuns}
- Train/test split by **field seed family**: train seeds 1–10, test seeds 101–110.
- Best fixed, selector and oracle are compared on the test family only, with paired bootstrap CIs and H1–H4 evaluated exactly as defined (no new metrics).
