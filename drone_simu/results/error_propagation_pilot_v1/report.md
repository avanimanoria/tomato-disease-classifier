# Error-propagation pilot (error_propagation_pilot_v1)

> PILOT: one field, one seed set, 16 paired missions. Simulated, currently UNCALIBRATED spray model, synthetic
> sensors, assumed hardware. Descriptive only - no significance, no real-world claim.

Runtime 73 s. Sanity checks: ALL PASS (sanity_checks.csv).

## Runs

| run | wind | localization | controller | comp. | loc RMSE (m) | cross-track RMSE (m) | geoloc (m) | exec (m) | release total (m) | landing (m) | bias (m) | scatter (m) | deposition (%) | treated (%) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M01 | 0 | groundTruthOracle | pid | none | 0.000 | 0.010 | 0.000 | 0.012 | 0.012 | 0.012 | 0.012 | 0.007 | 55.4 | 88.1 |
| M02 | 0 | groundTruthOracle | pid | wind | 0.000 | 0.010 | 0.000 | 0.012 | 0.012 | 0.012 | 0.012 | 0.007 | 55.4 | 88.1 |
| M03 | 0 | groundTruthOracle | purePursuit | none | 0.000 | 0.050 | 0.000 | 0.019 | 0.019 | 0.019 | 0.019 | 0.017 | 55.1 | 88.1 |
| M04 | 0 | groundTruthOracle | purePursuit | wind | 0.000 | 0.050 | 0.000 | 0.019 | 0.019 | 0.019 | 0.019 | 0.017 | 55.1 | 88.1 |
| M05 | 0 | sensorFusion | pid | none | 0.056 | 0.031 | 0.044 | 0.032 | 0.059 | 0.060 | 0.059 | 0.013 | 52.4 | 88.1 |
| M06 | 0 | sensorFusion | pid | wind | 0.056 | 0.031 | 0.044 | 0.032 | 0.059 | 0.060 | 0.059 | 0.013 | 52.4 | 88.1 |
| M07 | 0 | sensorFusion | purePursuit | none | 0.050 | 0.066 | 0.040 | 0.047 | 0.061 | 0.062 | 0.061 | 0.017 | 52.4 | 88.1 |
| M08 | 0 | sensorFusion | purePursuit | wind | 0.050 | 0.066 | 0.040 | 0.047 | 0.061 | 0.062 | 0.061 | 0.017 | 52.4 | 88.1 |
| M09 | 1 | groundTruthOracle | pid | none | 0.000 | 0.012 | 0.000 | 0.015 | 0.015 | 1.370 | 1.351 | 0.275 | 0.8 | 0.0 |
| M10 | 1 | groundTruthOracle | pid | wind | 0.000 | 0.012 | 0.000 | 0.016 | 0.016 | 0.441 | 0.358 | 0.281 | 11.0 | 0.0 |
| M11 | 1 | groundTruthOracle | purePursuit | none | 0.000 | 0.050 | 0.000 | 0.023 | 0.023 | 1.390 | 1.372 | 0.275 | 0.8 | 0.0 |
| M12 | 1 | groundTruthOracle | purePursuit | wind | 0.000 | 0.050 | 0.000 | 0.023 | 0.023 | 0.439 | 0.354 | 0.279 | 10.5 | 0.0 |
| M13 | 1 | sensorFusion | pid | none | 0.056 | 0.032 | 0.044 | 0.037 | 0.063 | 1.403 | 1.384 | 0.271 | 1.9 | 0.0 |
| M14 | 1 | sensorFusion | pid | wind | 0.056 | 0.031 | 0.044 | 0.036 | 0.059 | 0.451 | 0.372 | 0.278 | 10.0 | 4.8 |
| M15 | 1 | sensorFusion | purePursuit | none | 0.050 | 0.065 | 0.040 | 0.046 | 0.063 | 1.402 | 1.384 | 0.274 | 1.8 | 2.4 |
| M16 | 1 | sensorFusion | purePursuit | wind | 0.051 | 0.064 | 0.040 | 0.049 | 0.065 | 0.449 | 0.371 | 0.272 | 10.2 | 4.8 |

geoloc = |recorded - true plant|; exec = |actual release - commanded release|; release total = |actual - (true plant + compensation offset)|;
landing = mean over spray steps of |release position + drift(instantaneous wind incl. gusts) - true plant| (same functions as the engine deposition: advancedDrift, windVector); bias = |mean landing point - plant|; scatter = RMS spread of landing points (gust-driven). Canopy radius = 0.2 m.

## A. Contrasts (Y_after - Y_before)

| controller | comp. | contrast | d loc RMSE (m) | d cross RMSE (m) | d release (m) | d landing (m) | d deposition (pp) | d treated (pp) |
|---|---|---|---|---|---|---|---|---|
| pid | none | oracle->sensorFusion | no wind | +0.056 | +0.021 | +0.047 | +0.048 | -2.9 | +0.0 |
| pid | none | oracle->sensorFusion | wind | +0.056 | +0.020 | +0.048 | +0.033 | +1.1 | +0.0 |
| pid | none | no wind->wind | oracle | +0.000 | +0.002 | +0.003 | +1.358 | -54.6 | -88.1 |
| pid | none | no wind->wind | sensorFusion | -0.000 | +0.001 | +0.005 | +1.343 | -50.5 | -88.1 |
| pid | wind | oracle->sensorFusion | no wind | +0.056 | +0.021 | +0.047 | +0.048 | -2.9 | +0.0 |
| pid | wind | oracle->sensorFusion | wind | +0.056 | +0.019 | +0.043 | +0.010 | -1.0 | +4.8 |
| pid | wind | no wind->wind | oracle | +0.000 | +0.002 | +0.004 | +0.429 | -44.4 | -88.1 |
| pid | wind | no wind->wind | sensorFusion | -0.000 | +0.000 | +0.000 | +0.391 | -42.5 | -83.3 |
| purePursuit | none | oracle->sensorFusion | no wind | +0.050 | +0.016 | +0.041 | +0.043 | -2.8 | +0.0 |
| purePursuit | none | oracle->sensorFusion | wind | +0.050 | +0.015 | +0.040 | +0.012 | +1.0 | +2.4 |
| purePursuit | none | no wind->wind | oracle | +0.000 | -0.001 | +0.004 | +1.371 | -54.3 | -88.1 |
| purePursuit | none | no wind->wind | sensorFusion | -0.000 | -0.002 | +0.002 | +1.340 | -50.6 | -85.7 |
| purePursuit | wind | oracle->sensorFusion | no wind | +0.050 | +0.016 | +0.041 | +0.043 | -2.8 | +0.0 |
| purePursuit | wind | oracle->sensorFusion | wind | +0.051 | +0.015 | +0.042 | +0.010 | -0.2 | +4.8 |
| purePursuit | wind | no wind->wind | oracle | +0.000 | -0.001 | +0.004 | +0.420 | -44.6 | -88.1 |
| purePursuit | wind | no wind->wind | sensorFusion | +0.001 | -0.002 | +0.004 | +0.387 | -42.1 | -83.3 |

## B. Wind x localization difference-in-differences (CANDIDATE interactions only)

| controller | comp. | metric | noWind oracle | wind oracle | noWind SF | wind SF | DiD |
|---|---|---|---|---|---|---|---|
| pid | none | track_rmse_m | 0.010 | 0.012 | 0.031 | 0.032 | -0.001 |
| pid | none | release_total_mean_m | 0.012 | 0.015 | 0.059 | 0.063 | +0.002 |
| pid | none | landing_mean_m | 0.012 | 1.370 | 0.060 | 1.403 | -0.015 |
| pid | none | targetDeposition_pct | 55.362 | 0.790 | 52.427 | 1.911 | +4.055 |
| pid | none | treatmentSuccess_pct | 88.095 | 0.000 | 88.095 | 0.000 | +0.000 |
| pid | wind | track_rmse_m | 0.010 | 0.012 | 0.031 | 0.031 | -0.002 |
| pid | wind | release_total_mean_m | 0.012 | 0.016 | 0.059 | 0.059 | -0.004 |
| pid | wind | landing_mean_m | 0.012 | 0.441 | 0.060 | 0.451 | -0.038 |
| pid | wind | targetDeposition_pct | 55.362 | 10.992 | 52.427 | 9.965 | +1.907 |
| pid | wind | treatmentSuccess_pct | 88.095 | 0.000 | 88.095 | 4.762 | +4.762 |
| purePursuit | none | track_rmse_m | 0.050 | 0.050 | 0.066 | 0.065 | -0.001 |
| purePursuit | none | release_total_mean_m | 0.019 | 0.023 | 0.061 | 0.063 | -0.001 |
| purePursuit | none | landing_mean_m | 0.019 | 1.390 | 0.062 | 1.402 | -0.031 |
| purePursuit | none | targetDeposition_pct | 55.113 | 0.842 | 52.363 | 1.799 | +3.707 |
| purePursuit | none | treatmentSuccess_pct | 88.095 | 0.000 | 88.095 | 2.381 | +2.381 |
| purePursuit | wind | track_rmse_m | 0.050 | 0.050 | 0.066 | 0.064 | -0.001 |
| purePursuit | wind | release_total_mean_m | 0.019 | 0.023 | 0.061 | 0.065 | +0.001 |
| purePursuit | wind | landing_mean_m | 0.019 | 0.439 | 0.062 | 0.449 | -0.033 |
| purePursuit | wind | targetDeposition_pct | 55.113 | 10.464 | 52.363 | 10.227 | +2.513 |
| purePursuit | wind | treatmentSuccess_pct | 88.095 | 0.000 | 88.095 | 4.762 | +4.762 |

## C. Descriptive associations (no inference)

| level | x | y | n | Pearson | Spearman |
|---|---|---|---|---|---|
| 16 runs | loc_rmse_m | track_rmse_m | 16 | 0.39 | 0.19 |
| 16 runs | track_rmse_m | release_total_mean_m | 16 | 0.53 | 0.69 |
| 16 runs | release_total_mean_m | targetDeposition_pct | 16 | -0.10 | -0.43 |
| 16 runs | loc_rmse_m | targetDeposition_pct | 16 | -0.03 | -0.12 |
| 16 runs | landing_mean_m | targetDeposition_pct | 16 | -0.87 | -0.97 |
| per target (pooled) | landing_m | doseFraction | 720 | -0.84 | -0.95 |
| per target (pooled) | release_total_m | doseFraction | 720 | -0.10 | -0.26 |

## D. Bottleneck diagnostic

Normalization (explicit): geometric stages = increase over the clean reference (no wind + oracle, same controller / compensation) divided by the canopy radius 0.2 m; deposition = relative loss (ref - run) / ref. The largest geometric stage is reported; deposition is reported separately (different unit, not combined into one score).

| run | ctrl | comp. | wind | localization | loc | tracking | release | landing | deposition rel. loss | largest geometric stage |
|---|---|---|---|---|---|---|---|---|---|---|
| M01 | pid | none | 0 | groundTruthOracle | +0.00 | +0.00 | +0.00 | +0.00 | +0.00 | none (reference) |
| M09 | pid | none | 1 | groundTruthOracle | +0.00 | +0.01 | +0.02 | +6.79 | +0.99 | landing (spray transport) |
| M05 | pid | none | 0 | sensorFusion | +0.28 | +0.10 | +0.23 | +0.24 | +0.05 | localization |
| M13 | pid | none | 1 | sensorFusion | +0.28 | +0.11 | +0.26 | +6.95 | +0.97 | landing (spray transport) |
| M02 | pid | wind | 0 | groundTruthOracle | +0.00 | +0.00 | +0.00 | +0.00 | +0.00 | none (reference) |
| M10 | pid | wind | 1 | groundTruthOracle | +0.00 | +0.01 | +0.02 | +2.15 | +0.80 | landing (spray transport) |
| M06 | pid | wind | 0 | sensorFusion | +0.28 | +0.10 | +0.23 | +0.24 | +0.05 | localization |
| M14 | pid | wind | 1 | sensorFusion | +0.28 | +0.11 | +0.23 | +2.19 | +0.82 | landing (spray transport) |
| M03 | purePursuit | none | 0 | groundTruthOracle | +0.00 | +0.00 | +0.00 | +0.00 | +0.00 | none (reference) |
| M11 | purePursuit | none | 1 | groundTruthOracle | +0.00 | -0.00 | +0.02 | +6.85 | +0.98 | landing (spray transport) |
| M07 | purePursuit | none | 0 | sensorFusion | +0.25 | +0.08 | +0.21 | +0.21 | +0.05 | localization |
| M15 | purePursuit | none | 1 | sensorFusion | +0.25 | +0.07 | +0.22 | +6.91 | +0.97 | landing (spray transport) |
| M04 | purePursuit | wind | 0 | groundTruthOracle | +0.00 | +0.00 | +0.00 | +0.00 | +0.00 | none (reference) |
| M12 | purePursuit | wind | 1 | groundTruthOracle | +0.00 | -0.00 | +0.02 | +2.10 | +0.81 | landing (spray transport) |
| M08 | purePursuit | wind | 0 | sensorFusion | +0.25 | +0.08 | +0.21 | +0.21 | +0.05 | localization |
| M16 | purePursuit | wind | 1 | sensorFusion | +0.25 | +0.07 | +0.23 | +2.15 | +0.81 | landing (spray transport) |

## Sanity checks

| check | pass | detail |
|---|---|---|
| scenario pairing: wind=0 runs share one scenario hash | PASS | 73489343c29d |
| scenario pairing: wind=1 runs share one scenario hash | PASS | 69a0b6616d6d |
| identical field / plants / disease truth / detection draws in all 16 runs | PASS |  |
| oracle localization error is zero (ORACLE) | PASS | max 0 m |
| no-wind sanity: wind compensation offset is zero when wind = 0 | PASS | max 0 m |
| actuator timing error is zero (valve delay 0) | PASS |  |
| sensorFusion runs geolocate targets from the estimate (geolocation error > 0) | PASS |  |
| oracle runs: targets at true plant positions (geolocation error 0) | PASS |  |
| test suite TruthFirewallTest | PASS | 8/8 passed |
| test suite MassEnergySprayConservationTest | PASS | 3/3 passed |
| test suite FrozenExperimentIntegrityTest | PASS | 1/1 passed |

## Metrics NOT available / caveats

- Obstacle violation: no obstacles in this pilot field (reported as 0 by construction).
- Actuator timing error: valve delay 0 and the actuation model is off, so it is 0 by construction (sanity check only).
- Landing error is reconstructed from the logged dwell states with the engine's own drift functions (evaluated at the logged step, i.e. within one 0.1 s step of the deposit call); the deposition grid itself is not decomposed per target because sprays overlap.
- Mass residual = emitted - deposited on grid - evaporated: mass beyond the 4-sigma kernel window / grid edge (by design of depositSpray), not a conservation failure; conservation itself is checked by MassEnergySprayConservationTest.
- NEES uses the synthetic sensor model; oracle runs have no NEES.

<!-- ANALYST ANSWERS: written after reviewing the tables above -->

## Answers (analyst, from the tables above; in this simulated, currently UNCALIBRATED model)

1. **Localization error into tracking: weakly.** With sensorFusion, localization RMSE rose by 0.05–0.056 m (oracle 0 m). Cross-track RMSE rose by only 0.016–0.021 m. Across the 16 runs the association is weak (Pearson 0.39, Spearman 0.19). Most of the estimate error does not appear as cross-track error of the true track.
2. **Into release geometry: yes, via target geolocation, not via tracking.**
   - The release-error increase (+0.041–0.047 m) matches the geolocation error (mean 0.03–0.05 m, p95 0.11 m). Targets are recorded where the drone believed it was.
   - Release execution error is small because the spray is released after a 1 s settle at hover, so transit tracking error is absorbed before release.
   - Pure Pursuit tracks transit worse than PID (cross-track 0.050 vs 0.010 m with the oracle) but releases almost equally well (0.019 vs 0.012 m).
3. **Materially affected deposition?**
   - **Without wind: modestly and consistently.** oracle → sensorFusion costs −2.8 to −2.9 pp target deposition (55.4 → 52.4 %) in all four controller × compensation pipelines. Treatment success is unchanged (88.1 %).
   - **With wind and gusts: no.** Loss is dominated by spray transport.
4. **Candidate wind × localization interaction: yes in deposition, but explainable.**
   - DiD +1.9 / +2.5 pp with compensation; +3.7 / +4.1 pp without.
   - Without compensation the effect sits on a floor: deposition is 0.8–1.9 %, so the DiD there is a floor artifact.
   - With compensation the sensorFusion penalty shrinks from 2.9 pp (no wind) to 1.0 / 0.2 pp (wind). Landing error is consistent with errors adding roughly in quadrature: √(0.441² + 0.047²) = 0.44 m against the observed 0.45 m. The smaller localization error is masked by the larger gust-driven drift scatter (≈ 0.28 m within a dwell, plus ≈ 0.36 m residual bias from low-frequency gusts).
   - This is a sub-additive masking pattern. It is mathematically expected and not a novel effect.
   - The geometric DiDs (cross-track, release) are ≤ 0.004 m, effectively zero.
5. **Did the controller or compensation change the chain?**
   - **Controller: no** in any stage that matters (deposition within 0.5 pp between PID and Pure Pursuit in every cell).
   - **Compensation:** it changes only the transport stage. Under wind it removes the steady drift bias (landing 1.37 → 0.44 m; deposition 0.8 → 11.0 %). It cannot remove gust scatter, and it does not interact with localization beyond the masking in answer 4.
6. **Dominant loss.** Spray transport (drift landing error) under wind and gusts, in every disturbed run. The normalized landing degradation is +2.1 to +7.0 canopy radii, against ≤ 0.28 for localization and ≤ 0.26 for release geometry.
   - Wind + compensation removes 80–82 % of the clean deposition even with oracle localization.
   - Without wind, the only loss source is localization → geolocation → release, about 5 % relative.
   - So the limiting stage switches with the disturbance regime.
7. **Large enough and structured enough for Experiment G?**
   - The *original* framing, a multi-stage chain where localization and controller errors propagate through tracking into deposition, is **not supported**. Tracking is decoupled from release by the hover release, and the controller hardly matters.
   - What *is* structured and repeatable-looking:
     - the regime switch between a localization-limited and a transport-limited condition,
     - the quadrature masking in between.
   - That would require mapping the crossover over gust level and localization error level with replication, not repeating this 2 × 2 × 2 × 2.
8. **Possible artifacts of the current assumptions:**
   - The magnitude of the transport term follows directly from uncalibrated parameters: drift = driftFactor × wind × release height / fall speed, gust σ 0.5 m/s, canopy radius 0.2 m, Gaussian kernel. With calibrated, smaller gust drift the crossover would move and localization could dominate. With larger drift, localization would never matter.
   - The 2.9 pp localization cost depends on the 0.2 m canopy radius and on geolocation at the first imaging step.
   - The decoupling of tracking from release is a property of the hover-release design. A moving release would couple them.
   - One field and one seed set: the sign of the small DiDs could change with other seeds.

DECISION: PROCEED, BUT MODIFY HYPOTHESIS

Justification: the data do not support localization / controller error propagation through tracking as the primary effect. They do show a structured, regime-dependent error budget: release-geometry error (from localization via geolocation) and drift scatter (from wind and gusts) combine sub-additively, and the limiting stage switches with the disturbance level. A modified Experiment G should test that crossover, specifically where localization error stops mattering, across replicated fields and seeds and *bounded* drift-parameter regimes. A null outcome there (crossover position entirely set by uncalibrated drift parameters) would also be informative.
