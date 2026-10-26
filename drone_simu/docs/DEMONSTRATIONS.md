# Demonstrations (manual V1 section 8, item 9)

Produced by `runDemonstrations` (executable; re-run any time, output in `demo_reports/`). Captured output of the run at commit `c56254d` (docs commit follows):

```text
AGRICULTURAL DRONE - MANUAL V1 DEMONSTRATIONS  (11-Oct-2026 19:56:16, MATLAB 26.2.0.3386108 (R2026b), commit c56254d)

[1] Baseline run (legacy defaults) reproduces the frozen golden mission
   PASS  runPipeline(pipelineDefaults()) == golden/legacy_mission_golden.mat baseline (bit-identical)
   pipeline: openLoop | nearestNeighbour | none | groundTruthOracle | gaussian | parametric | deposition 50.39 % | mission time 302.6 s

[2] One manual pipeline run
   pipeline: pid | nearestNeighbourOrOpt | wind | sensorFusion | windStretched | parametric | geolocated
   run R20261011T195623-6966d0b8  scenario 78908c1d7af3  pipeline e377701a6a4c
   Detector recall                      88.095 % of truly diseased
   Estimate error RMSE                   0.055 m
   NEES (consistency, ~2 ideal)          4.912 -
   Target deposition                    19.312 % of emitted
   Treatment success                    21.429 % of truly diseased
   Mission time                        289.700 s
   PASS  the selected pipeline changed the flown mission (not a label)

[3] Paired comparison changing ONE algorithm (Pass-2 routing)
   PASS  same scenario hash (field, seeds, wind / gust / sensor traces)
   PASS  Pass 1 identical - only Pass-2 routing differs
   Planned (geometric) Pass-2 route   NN     90.92 | NN+Or-opt     85.02 | diff    -5.90 m
   Flown Pass-2 distance              NN    103.78 | NN+Or-opt     96.09 | diff    -7.69 m
   Target deposition                  NN     18.88 | NN+Or-opt     19.31 | diff    +0.43 % of emitted
   Mission time                       NN    294.30 | NN+Or-opt    289.70 | diff    -4.60 s
   PASS  a different field seed is refused as UNPAIRED

[4] Experiment F frozen results readable and intact
   PASS  results/benchmark/benchmark.mat loads
   PASS  70 frozen files, 0 checksum mismatches
   - H2 selector beats best fixed on held-out tests: NOT SUPPORTED - best fixed "PurePursuit | wind + lag comp." 26.9%, selector 26.6%, oracle 27.0%; gain -0.35 pp
   PASS  runExperimentF refuses to overwrite the frozen benchmark

[5] Unavailable CNN explicitly disabled
   PASS  registry: cnn available = false (missing: trained model (C:\Users\Shraddha.B\Downloads\attachments\dataset\diseaseModel.mat); plant images (C:\Users\Shraddha.B\Downloads\attachments\dataset\plant_images); plant-to-image linkage for the Internal-2 field (not defined); class mapping / preprocessing specification from the model owner)
   PASS  validator: perception: "Teammate CNN" is UNAVAILABLE (missing: trained model (C:\Users\Shraddha.B\Downloads\attachments\dataset\diseaseModel.mat); plant images (C:\Users\Shraddha.B\Downloads\attachments\dataset\plant_images); plant-to-image linkage for the Internal-2 field (not defined); class mapping / preprocessing specification from the model owner)
   PASS  adapter raises perceptionCNNAdapter:unavailable (no silent fallback to the parametric detector)

[6] Failure-safe recovery
   PASS  unknown hardware profile rejected before any flight
   PASS  field split by a wall: coverage reports INFEASIBLE instead of clipping through it
   PASS  after the failures the legacy mission is still bit-identical to the golden run

RESULT: ALL DEMONSTRATIONS PASSED
```
