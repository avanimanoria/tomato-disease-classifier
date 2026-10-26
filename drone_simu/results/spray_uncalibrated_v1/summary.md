# Spray model: bounded UNCALIBRATED sensitivity study (spray_uncalibrated_v1)

> **UNCALIBRATED.** No deposition / drift measurements were supplied. All numbers are relative results
> of the simplified Gaussian deposition model inside the stated parameter bounds; they are not physical
> validation. The bounds are assumed (around the assumed defaults), not literature-sourced.

Runtime 64 s. Missions: Part A 60, Part B1/B2 18; Part B3 kernel cases 27.

## Part A - does "spray compensation helps" survive the parameter bounds?

| parameter | levels | wind (m/s) | deposition range, comp. off (%) | deposition range, comp. on (%) | compensation benefit range (pp) | sign stable |
|---|---|---|---|---|---|---|
| sigmaFraction | 0.3 / 0.5 / 0.8 | 2 | 0.0 - 0.1 | 29.7 - 78.3 | +29.5 to +78.3 | yes |
| sigmaFraction | 0.3 / 0.5 / 0.8 | 4 | 0.0 - 0.1 | 29.6 - 77.8 | +29.5 to +77.8 | yes |
| dropletFallSpeed | 0.8 / 1.5 / 3 | 2 | 0.0 - 0.1 | 55.2 - 55.2 | +55.1 to +55.2 | yes |
| dropletFallSpeed | 0.8 / 1.5 / 3 | 4 | 0.0 - 0.0 | 54.8 - 54.9 | +54.8 to +54.9 | yes |
| driftFactor | 0.6 / 1 / 1.2 | 2 | 0.0 - 0.6 | 55.2 - 55.2 | +54.6 to +55.2 | yes |
| driftFactor | 0.6 / 1 / 1.2 | 4 | 0.0 - 0.7 | 54.8 - 54.9 | +54.1 to +54.9 | yes |
| releaseHeight | 0.6 / 1 / 1.4 | 2 | 0.0 - 6.4 | 36.1 - 78.3 | +29.7 to +78.3 | yes |
| releaseHeight | 0.6 / 1 / 1.4 | 4 | 0.0 - 1.6 | 35.9 - 77.8 | +34.3 to +77.8 | yes |
| windStretch_perMps | 0 / 0.3 / 0.6 | 2 | 0.0 - 0.6 | 30.8 - 55.2 | +30.2 to +55.2 | yes |
| windStretch_perMps | 0 / 0.3 / 0.6 | 4 | 0.0 - 1.3 | 20.6 - 54.9 | +19.3 to +54.9 | yes |

Compensation benefit positive in 30 of 30 (parameter, level, wind) cells; minimum +19.3 pp, maximum +78.3 pp.
Conclusion: the direction of the compensation effect is robust within these bounds; its MAGNITUDE is parameter-dependent and must not be quoted as a physical number.

Caveat (self-consistency): the compensator computes its upwind offset with the SAME drift parameters as the simulated truth, so these benefits are upper bounds for a perfectly known drift model. Wind-knowledge mismatch is studied separately (Experiment D2, spray.windEstimateScale); fall-speed / drift-factor mismatch is not modelled. Without compensation, deposition is near zero whenever the drift (wind x height / fall speed x driftFactor) exceeds the 0.2 m canopy radius, which holds for every level here.

## Part B - when can valve-lag compensation matter?

### B1 / B2 mission engine (stopped release and hover release)

| release | valve delay (s) | lag comp. | target deposition (%) | treatment success (%) | lag displacement (m) |
|---|---|---|---|---|---|
| stopped | 0.00 | no | 55.2 | 88.1 | 0.000 |
| stopped | 0.10 | no | 54.5 | 88.1 | 0.008 |
| stopped | 0.10 | yes | 55.2 | 88.1 | 0.000 |
| stopped | 0.25 | no | 50.3 | 88.1 | 0.047 |
| stopped | 0.25 | yes | 55.2 | 88.1 | 0.000 |
| stopped | 0.50 | no | 45.6 | 88.1 | 0.113 |
| stopped | 0.50 | yes | 55.2 | 88.1 | 0.000 |
| stopped | 1.00 | no | 35.4 | 88.1 | 0.387 |
| stopped | 1.00 | yes | 55.2 | 88.1 | 0.000 |
| hover | 0.00 | no | 22.8 | 40.5 | 0.000 |
| hover | 0.10 | no | 22.8 | 40.5 | 0.009 |
| hover | 0.10 | yes | 22.8 | 40.5 | 0.000 |
| hover | 0.25 | no | 22.7 | 38.1 | 0.038 |
| hover | 0.25 | yes | 22.8 | 40.5 | 0.000 |
| hover | 0.50 | no | 21.5 | 31.0 | 0.089 |
| hover | 0.50 | yes | 22.8 | 40.5 | 0.000 |
| hover | 1.00 | no | 18.1 | 16.7 | 0.328 |
| hover | 1.00 | yes | 22.8 | 40.5 | 0.000 |

### B3 moving release (kernel-level, not a mission mode)

| speed (m/s) | valve delay (s) | lag comp. | canopy capture (% of emitted) |
|---|---|---|---|
| 1.0 | 0.00 | no | 32.0 |
| 1.0 | 0.10 | no | 32.2 |
| 1.0 | 0.10 | yes | 32.0 |
| 1.0 | 0.25 | no | 30.6 |
| 1.0 | 0.25 | yes | 32.0 |
| 1.0 | 0.50 | no | 17.5 |
| 1.0 | 0.50 | yes | 32.0 |
| 1.0 | 1.00 | no | 0.0 |
| 1.0 | 1.00 | yes | 32.0 |
| 1.5 | 0.00 | no | 31.9 |
| 1.5 | 0.10 | no | 32.1 |
| 1.5 | 0.10 | yes | 31.9 |
| 1.5 | 0.25 | no | 27.3 |
| 1.5 | 0.25 | yes | 31.9 |
| 1.5 | 0.50 | no | 3.4 |
| 1.5 | 0.50 | yes | 31.9 |
| 1.5 | 1.00 | no | 0.0 |
| 1.5 | 1.00 | yes | 31.9 |
| 3.0 | 0.00 | no | 31.7 |
| 3.0 | 0.10 | no | 32.1 |
| 3.0 | 0.10 | yes | 31.7 |
| 3.0 | 0.25 | no | 6.0 |
| 3.0 | 0.25 | yes | 31.7 |
| 3.0 | 0.50 | no | 0.0 |
| 3.0 | 0.50 | yes | 31.7 |
| 3.0 | 1.00 | no | 0.0 |
| 3.0 | 1.00 | yes | 31.7 |

### Interpretation

- Stopped release, 0.5 s delay, no compensation: -9.7 pp target deposition vs. no delay (the drone holds position; the delay mostly shifts flow into the departure).
- Moving release at 1.5 m/s, 0.5 s delay, no compensation: -28.5 pp canopy capture vs. no delay (the release is displaced by v x delay = 0.75 m, larger than the canopy).
- Lag compensation restores the zero-delay result whenever the delay is known and (for the engine) does not exceed the 1 s settle time.
- Hence compensation matters most for MOVING release, and for stopped release only when the delay is a large fraction of the dwell or the drone departs while still spraying.
- Experiment F (hover release, gusts) measured a 2.1 pp delay effect and listed moving release as an open item (docs/EXPERIMENT_F_AUDIT.md section 5); B3 quantifies that case at kernel level only.
