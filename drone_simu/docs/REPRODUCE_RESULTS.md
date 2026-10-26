# Reproduce results

## Environment used

| Item | Value |
|---|---|
| MATLAB | R2026b (26.2.0.3386108), `C:\Program Files\MATLAB\R2026b\bin\matlab.exe` |
| Toolboxes | none beyond base MATLAB (uses `matlab.unittest`, App Designer UI components, `inpolygon`, Java `MessageDigest`) |
| Machine | Intel Core Ultra 7 255U, 31 GB RAM, Windows 11 Enterprise |
| Code | git branch `feature/manual-v1`. Tags `v1.0-pre-enhancements` (original baseline) and `v2.0-enhancements` (start of this manual) |
| Randomness | private seeded streams only (`RandStream`, `advNoise.m`); the global `rng` is never used by the engine |

## Commands

Run from the project folder; every command below is deterministic.

```matlab
cd('C:\Users\Shraddha.B\Downloads\attachments')

runAllTests                          % regression gate: 65 tests, ~4.5 min -> test_reports/regression_*.txt
runDemonstrations                    % 6 hand-off demonstrations, ~1 min   -> demo_reports/demonstrations_*.txt
app = AgriculturalDroneDashboardV2;  % dashboard (MISSION, PIPELINE BUILDER, ADVANCED OPTIONS, COMPARATIVE ANALYSIS, EXPERIMENTS)

r = runPipeline(pipelineDefaults()); % the legacy mission (bit-identical to golden/legacy_mission_golden.mat baseline)

auditExperimentF                     % re-derives docs/EXPERIMENT_F_AUDIT.md and audit/experiment_inventory.csv from the frozen run
```

From a shell:

```bash
"C:\Program Files\MATLAB\R2026b\bin\matlab.exe" -batch "runAllTests"
```

## Frozen and new result sets

| Set | Location | How it was produced | Re-run |
|---|---|---|---|
| Experiments A–E, D2, ablation, screenshots | `results/*` | original scripts (`main_experiments.m`, `runExperimentC.m` and others) | frozen; checked by `FrozenExperimentIntegrityTest` |
| Experiment F (623 missions) | `results/benchmark/` | `runExperimentF` | **frozen**. `runExperimentF` refuses (`runExperimentF:frozen`); new runs need a new folder, e.g. `runExperimentF(fullfile(pwd,'results','benchmark_F2'))` |
| Spray study | `results/spray_uncalibrated_v1/` | `runSprayUncertaintyStudy` (70 s; 78 missions + 27 kernel cases) | refuses to overwrite; use a new folder |
| Golden missions | `golden/legacy_mission_golden.mat`, `golden/internal2_E_golden.mat`, `golden/experimentE_prerefactor.mat` | `golden/captureLegacyGolden.m` (Phase 0) | never regenerate on a changed engine |
| Checksums | `golden/frozen_checksums.csv` (70 files) | `golden/writeFrozenChecksums.m` | only to *add* new frozen sets; existing hashes must not change |

## Seed manifest

| Seed | Default | Where |
|---|---|---|
| Field / disease / detection draws | 42 | `cfg.internal2.seed`; PipelineConfig `scenario.field.seed` |
| Gust stream | 7 | `enhancements.gusts.seed`; `scenario.gustSeed` |
| Localization streams | 3 | `enhancements.localization.seed`. sensorFusion uses `seed + 3 … + 9` (bias direction, accel, flow, LiDAR, dropout) |
| ACO router | fixed in `planRouteAdvanced.m` | — |
| Experiment F | train / test seeds as listed in `docs/EXPERIMENT_F_AUDIT.md` | `results/benchmark/benchmark.mat` |

Every pipeline run records its seeds, SHA-256 config / scenario / pipeline hashes and the git commit in `run_info.json` (EXPORT RUN).

## Runtimes (this machine)

| Task | Time |
|---|---|
| one mission (`runPipeline`) | 1–3 s |
| regression gate | 4.1–4.6 min |
| demonstrations | ~1 min |
| spray study | 70 s |
