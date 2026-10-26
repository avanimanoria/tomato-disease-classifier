# Bias-vs-scatter bridge pilot (bias_scatter_bridge_pilot_v1)

> Within the current mission simulator (existing engine, UNCALIBRATED spray model, synthetic disturbances).
> 480 missions, 3 fields x 10 gust seeds x 4 regimes x 4 states, oracle localization. Runtime 5 s. Sanity: ALL PASS.

## Regime validation (achieved BASE values)

| regime | label | n | bias/R median [min, max] | scatter/R median [min, max] | in intended regime |
|---|---|---|---|---|---|
| A | low bias / low scatter | 30 | 0.36 [0.33, 0.40] | 0.38 [0.35, 0.43] | 100 % |
| B | low bias / high scatter | 30 | 0.35 [0.19, 0.58] | 2.12 [1.93, 2.30] | 90 % |
| C | high bias / low scatter | 30 | 3.03 [3.00, 3.06] | 0.39 [0.35, 0.42] | 100 % |
| D | high bias / high scatter | 30 | 3.03 [2.86, 3.21] | 2.13 [1.95, 2.24] | 100 % |

## Paired intervention effects on target deposition (pp; 95 % CI: field-clustered bootstrap)

| regime | contrast | n | mean | median | 95 % CI | fraction < 0 | min |
|---|---|---|---|---|---|---|---|
| A | dDep_bias_pp | 30 | +2.61 | +2.59 | [+2.54, +2.71] | 0.00 | +2.24 |
| A | dDep_scatter_pp | 30 | +2.66 | +2.68 | [+2.52, +2.77] | 0.00 | +2.08 |
| A | dDep_both_pp | 30 | +5.58 | +5.58 | [+5.43, +5.72] | 0.00 | +5.03 |
| A | biasMinusScatter_pp | 30 | -0.05 | +0.02 | [-0.18, +0.11] | 0.43 | -0.91 |
| B | dDep_bias_pp | 30 | +0.21 | +0.23 | [+0.08, +0.37] | 0.23 | -0.64 |
| B | dDep_scatter_pp | 30 | +16.13 | +16.33 | [+15.30, +16.79] | 0.00 | +14.22 |
| B | dDep_both_pp | 30 | +17.26 | +17.45 | [+16.46, +17.87] | 0.00 | +15.03 |
| B | biasMinusScatter_pp | 30 | -15.92 | -16.11 | [-16.63, -15.05] | 1.00 | -18.20 |
| C | dDep_bias_pp | 30 | +11.71 | +11.89 | [+10.79, +12.40] | 0.00 | +10.23 |
| C | dDep_scatter_pp | 30 | -0.04 | -0.04 | [-0.04, -0.03] | 1.00 | -0.06 |
| C | dDep_both_pp | 30 | +11.29 | +11.53 | [+10.37, +11.97] | 0.00 | +10.02 |
| C | biasMinusScatter_pp | 30 | +11.75 | +11.92 | [+10.84, +12.44] | 0.00 | +10.26 |
| D | dDep_bias_pp | 30 | +7.07 | +6.75 | [+6.55, +7.55] | 0.00 | +5.42 |
| D | dDep_scatter_pp | 30 | -2.47 | -2.43 | [-2.70, -2.25] | 1.00 | -3.52 |
| D | dDep_both_pp | 30 | +9.73 | +9.75 | [+9.21, +10.22] | 0.00 | +8.02 |
| D | biasMinusScatter_pp | 30 | +9.54 | +9.27 | [+8.94, +10.07] | 0.00 | +7.48 |

## Scatter-reduction harm by field

| field | group | n | harmed | fraction | mean dScatter | min dScatter |
|---|---|---|---|---|---|---|
| 1 | bias > R | 20 | 20 | 1.00 | -1.27 | -3.52 |
| 1 | bias <= R | 20 | 0 | 0.00 | +9.70 | +2.48 |
| 2 | bias > R | 20 | 20 | 1.00 | -1.28 | -3.39 |
| 2 | bias <= R | 20 | 0 | 0.00 | +9.61 | +2.43 |
| 3 | bias > R | 20 | 20 | 1.00 | -1.21 | -3.08 |
| 3 | bias <= R | 20 | 0 | 0.00 | +8.88 | +2.08 |

## Decision rules (which single intervention is better)

| rule | accuracy (non-tie) | non-tie / ties | mean regret (pp) | worst regret (pp) |
|---|---|---|---|---|
| scalar: larger of bias^2, scatter^2 | 1.000 | 94 / 26 | 0.01 | 0.33 |
| reduced-order Rice predictor (achieved bias, scatter) | 0.989 | 94 / 26 | 0.02 | 0.64 |

## Matched RMSE

R2 deposition ~ cubic(log RMSE/R) = 0.960; + bias-fraction terms = 0.995; residual SD 3.72 -> 1.35 pp

| RMSE band (m) | n | bias fraction range | deposition range (%) | Spearman(bias fraction, dep) |
|---|---|---|---|---|
| 0.079-0.087 | 48 | 0.15-0.79 | 47.0-51.0 | -0.11 |
| 0.087-0.096 | 12 | 0.16-0.77 | 46.3-50.9 | -0.13 |
| 0.363-0.400 | 26 | 0.01-0.73 | 11.0-18.2 | -0.66 |

## Geometry (post-hoc scoring of the same missions; equal-area circle / 4:1 ellipses)

| regime | geometry | mean dBias - dScatter (pp) | median | fraction bias better | fraction scatter better |
|---|---|---|---|---|---|
| A | pref_circle_pp | -0.05 | +0.02 | 0.03 | 0.10 |
| A | pref_ellipseAlongY_pp | -1.49 | -1.50 | 0.00 | 1.00 |
| A | pref_ellipseAlongX_pp | +1.41 | +1.48 | 1.00 | 0.00 |
| B | pref_circle_pp | -15.92 | -16.11 | 0.00 | 1.00 |
| B | pref_ellipseAlongY_pp | -11.90 | -12.36 | 0.00 | 1.00 |
| B | pref_ellipseAlongX_pp | -11.59 | -11.47 | 0.00 | 1.00 |
| C | pref_circle_pp | +11.75 | +11.92 | 1.00 | 0.00 |
| C | pref_ellipseAlongY_pp | +20.69 | +21.44 | 1.00 | 0.00 |
| C | pref_ellipseAlongX_pp | +5.12 | +5.33 | 1.00 | 0.00 |
| D | pref_circle_pp | +9.54 | +9.27 | 1.00 | 0.00 |
| D | pref_ellipseAlongY_pp | +7.18 | +7.03 | 1.00 | 0.00 |
| D | pref_ellipseAlongX_pp | +8.38 | +8.26 | 1.00 | 0.00 |

## Sanity checks

| check | pass | detail |
|---|---|---|
| field 1: every paired mission treats the identical frozen target set | PASS | 45 targets |
| field 2: every paired mission treats the identical frozen target set | PASS | 66 targets |
| field 3: every paired mission treats the identical frozen target set | PASS | 32 targets |
| only the intended mechanism differs within paired comparisons (cfg diff) | PASS | enhancements.gusts.sigma_mps, internal2.spray.windEstimateScale |
| oracle localization error is zero in all primary missions | PASS | max 0 m |
| mass balance: emitted = nominal dose x targets; deposited + evaporated <= emitted | PASS | max residual 0.01 % of emitted |
| landing metrics from engine functions: circle union score equals engine targetDeposition | PASS | max diff 1e-13 pp |
| reproducibility of a mission from the stored settings and seeds (|diff| < 1e-9; CSV keeps 15 digits) | PASS | 47.167135298329 vs 47.167135298329 |
| paired runs share field / plants / disease / detection truth (regenerated identically) | PASS |  |
| regime labels are checked against ACHIEVED bias / scatter (regime_validation.csv) | PASS | see regime validation |
| no outcome-based tuning: settings fixed in the runner header before the run | PASS | windEstimateScale 0.95 / 0.55, gust sigma 0.08 / 0.45 |
| no existing source / results / pilot folders modified (git status) | PASS |  |
| frozen checksums unchanged (FrozenExperimentIntegrityTest) | PASS |  |
| MassEnergySprayConservationTest | PASS |  |

<!-- ANALYST ANSWERS: written after reviewing the tables above -->

## Answers (analyst; within the current mission simulator, UNCALIBRATED spray model)

1. **Regimes achieved: yes, cleanly separated** on achieved values (figure 01).

   | Regime | Achieved bias / R | Achieved scatter / R | In intended regime |
   |---|---|---|---|
   | A | ≈ 0.36 | ≈ 0.38 | 100 % |
   | B | 0.19–0.58 | ≈ 2.1 | 90 % |
   | C | ≈ 3.0 | ≈ 0.39 | 100 % |
   | D | ≈ 3.0 | ≈ 2.1 | 100 % |

   Three B runs exceed the 0.5 R low-bias target (max 0.58 R), because gusts also displace the hovering vehicle. Intervention results are interpreted.
2. **Matched RMSE: composition changes deposition, but modestly at mission level.**
   - RMSE alone explains R² = 0.960 of the deposition variance. Adding composition gives 0.995 (residual SD 3.7 → 1.4 pp).
   - In the one well-populated 10 %-matched bin (RMSE 0.36–0.40 m), deposition is 11–18 % and falls with bias fraction (Spearman −0.66). That is about 3–7 pp, far smaller than the reduced-order capture contrast (36 % vs 8 % at RMS 0.30 m).
   - The four-corner design produced few genuinely matched pairs.
3. **Scatter reduction reduces target deposition: yes**, in **60 of 60** paired runs with bias > R (regimes C and D, every field and seed).
   - Regime C: −0.04 pp (CI −0.04 to −0.03). Base deposition is already ≈ 0.1 %, so this is negligible.
   - Regime D: −2.5 pp (CI −2.7 to −2.2, worst −3.5 pp).
   - Scatter reduction never hurt when bias ≤ R (60 of 60 runs gained, +2.1 to +18 pp).
4. **The harm occurs specifically when the mean landing point is outside the target** (bias ≈ 3 R in every harmed run). No runs sat near the boundary, so its exact onset was not observed.
5. **Bias-dominated regimes: yes, bias reduction outperforms scatter reduction.** C: +11.7 vs −0.04 pp. D: +7.1 vs −2.5 pp. Paired difference +11.8 [10.8, 12.4] and +9.5 [8.9, 10.1] pp.
6. **Low-bias / high-scatter: yes, scatter reduction outperforms bias reduction.** B: +16.1 vs +0.2 pp, paired difference −15.9 [−16.6, −15.1] pp. Regime A is a tie (2.6 vs 2.7 pp, difference −0.05 [−0.18, +0.11]).
7. **The scalar baseline chooses perfectly.** "Fix whichever of bias² or scatter² is larger" is correct in **94 / 94** non-tie pairs (26 ties, all regime A). The reduced-order Rice predictor is no better (93 / 94).
8. **Worst regret:** scalar rule 0.33 pp (mean 0.01 pp); Rice predictor 0.64 pp.
9. **Replication: yes.** Every directional result (H-B2 to H-B4) has the same sign in all 3 fields and all 10 gust seeds, with tight field-clustered CIs. The fields differ in shape, row style and disease seed but share the same wind direction, crop spacing and spray model.
10. **Geometry (post-hoc equal-area scoring of the same missions, not a new physics run):**
    - Orientation changes the magnitude strongly where bias dominates. In C, the bias-minus-scatter advantage is +20.7 pp for a 4:1 target along the bias, against +11.8 (circle) and +5.1 (across). Halving a 0.6 m bias puts the landing inside a 0.4 m semi-axis but not inside a 0.2 m radius.
    - The preferred intervention itself flips only in regime A, consistently but by about ±1.5 pp: scatter is better along the bias, bias is better across it.
    - In B, C and D the preference does not change.
11. **sensorFusion / geolocation:** not tested. The specification makes it conditional on the spray-level effect surviving, and the decision below is negative.
12. **Mission-level magnitude.**
    - Bias-vs-scatter *contrasts* are large: 10–16 pp of deposition between the right and wrong intervention.
    - The *non-trivial* parts are small. The harm effect is ≤ 3.5 pp and appears only where deposition is already ≤ 5 %. The composition effect at matched RMSE is about 3–7 pp. The geometry preference flip is about 1.5 pp.
    - Every decision-relevant choice is predicted by the trivial scalar rule.
13. **Could it disappear? Yes, easily.**
    - Every magnitude follows from uncalibrated settings: drift = driftFactor × wind × h / fall speed, gust σ, the gust spectrum (2–20 s), the 0.2 m canopy radius and the Gaussian kernel σ_k = 0.134 m.
    - The kernel blurs each landing, which is one reason the mission-level composition effect is much weaker than in the reduced-order model.
    - Wind direction was fixed at 90°, perpendicular to the rows.
14. **Still needs experimental grounding:**
    - Post-compensation residual drift bias and gust-driven scatter for a real nozzle / platform.
    - Deposition kernel width.
    - Canopy footprint size and shape relative to wind direction.
    - Gust spectra at spray height.
    - Wind-estimation error of the compensator.
    - The ICAERUS UC2 sheets contain none of these (no landing-position data).
15. **Is this enough to justify Experiment G? No.** The reduced-order prediction that does survive (bias and scatter act differently, and scatter reduction can hurt when bias > R) is real in the mission model. But it does not create a decision problem that simple rules get wrong. The scalar rule had 0.33 pp worst regret, and the harm appears only where the scalar rule already prescribes bias reduction.
    - **Design limitation, stated plainly:** the prespecified four-corner design does not sample the region where the reduced-order baseline failed (bias / R ≈ 0.5–1 with scatter / R ≈ 0.5). The mission-level behaviour there is untested.
    - Even in the reduced-order model the mean regret there was below 1 pp, so a large mission-level effect there would be surprising. This is the only open check, and it was not added after seeing the data, to avoid changing the design to fit.

DECISION: A. STOP — REDUCED-ORDER EFFECT DOES NOT SURVIVE MISSION MODEL

Justification:
- The directional bias / scatter effects replicate, including the scatter-reduction harm when bias > R (60 / 60 pairs).
- But the intervention preference is fully explained by the trivial scalar rule (100 % accuracy, worst regret 0.33 pp).
- The matched-RMSE composition effect is modest (R² 0.960 → 0.995), and the harm and geometry-flip effects are small (≤ 3.5 pp and about 1.5 pp) and occur where they do not change the correct decision.
- This meets the specification's first STOP criterion. A bias-vs-scatter requirement map does not, in this simulator, carry a non-trivial mission-level decision consequence large enough to anchor Experiment G.
