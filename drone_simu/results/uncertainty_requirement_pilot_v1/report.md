# Cross-layer uncertainty requirement map - falsification pilot (uncertainty_requirement_pilot_v1)

> Reduced-order Monte Carlo model, NOT the mission engine. Grid values are sensitivity values, not measured crop
> or sensor properties. Within this simplified uncertainty model only.

Seed 20261011, 200000 samples per cell, common random numbers; thresholds prespecified: tie 0.5 pp, material 2 pp. Runtime 80 s. Sanity: ALL PASS.

## Baseline accuracy (primary grid)

| set | cells | decision-relevant | of which ties | A acc. | B acc. | C acc. | A acc. (non-tie) | C acc. (non-tie) | A max regret | C max regret | B == A |
|---|---|---|---|---|---|---|---|---|---|---|---|
| primary grid (circular, isotropic) | 576 | 401 | 37 | 0.703 | 0.703 | 0.953 | 0.673 | 0.956 | 1.000 | 0.098 | 1.000 |

decision-relevant = at least 2 applicable interventions and best gain >= 2 pp. Correct = regret <= tie tolerance.

## Anisotropy / geometry challenge summary (R_eq = 0.20 m)

| spray anisotropy | target aspect | major axis | cells | best flips vs iso-circle | A acc. | C acc. | A max regret | C max regret |
|---|---|---|---|---|---|---|---|---|
| 1:1 | 1:1 | x | 75 | 0 | 0.773 | 1.000 | 0.984 | 0.004 |
| 1:1 | 2:1 | x | 75 | 6 | 0.880 | 0.867 | 0.314 | 0.062 |
| 1:1 | 2:1 | y | 75 | 0 | 0.733 | 1.000 | 0.711 | 0.001 |
| 1:1 | 4:1 | x | 75 | 12 | 1.000 | 0.787 | 0.003 | 0.207 |
| 1:1 | 4:1 | y | 75 | 4 | 0.667 | 0.933 | 0.463 | 0.108 |
| 2:1 | 1:1 | x | 75 | 1 | 0.680 | 0.973 | 0.973 | 0.032 |
| 2:1 | 2:1 | x | 75 | 8 | 0.747 | 0.880 | 0.331 | 0.075 |
| 2:1 | 2:1 | y | 75 | 1 | 0.680 | 0.947 | 0.690 | 0.043 |
| 2:1 | 4:1 | x | 75 | 16 | 0.840 | 0.760 | 0.114 | 0.236 |
| 2:1 | 4:1 | y | 75 | 4 | 0.640 | 0.880 | 0.441 | 0.102 |
| 4:1 | 1:1 | x | 75 | 2 | 0.693 | 0.960 | 0.968 | 0.061 |
| 4:1 | 2:1 | x | 75 | 6 | 0.733 | 0.907 | 0.337 | 0.093 |
| 4:1 | 2:1 | y | 75 | 1 | 0.667 | 0.947 | 0.683 | 0.059 |
| 4:1 | 4:1 | x | 75 | 16 | 0.787 | 0.773 | 0.215 | 0.222 |
| 4:1 | 4:1 | y | 75 | 2 | 0.667 | 0.907 | 0.432 | 0.099 |

## Bias vs scatter at matched RMS landing error (R = 0.20 m)

| RMS landing (m) | bias share | sigma each (m) | bias (m) | P_capture | d loc | d spray | d bias | best |
|---|---|---|---|---|---|---|---|---|
| 0.10 | 0.00 | 0.050 | 0.000 | 0.982 | +0.016 | +0.016 | NaN | none (spray) |
| 0.10 | 0.25 | 0.043 | 0.050 | 0.985 | +0.013 | +0.013 | +0.008 | none (loc) |
| 0.10 | 0.50 | 0.035 | 0.071 | 0.992 | +0.008 | +0.008 | +0.007 | none (spray) |
| 0.10 | 0.75 | 0.025 | 0.087 | 0.999 | +0.001 | +0.001 | +0.001 | none (bias) |
| 0.10 | 0.90 | 0.016 | 0.095 | 1.000 | +0.000 | +0.000 | +0.000 | none (loc) |
| 0.10 | 1.00 | 0.000 | 0.100 | 1.000 | NaN | NaN | +0.000 | none (bias) |
| 0.20 | 0.00 | 0.100 | 0.000 | 0.632 | +0.167 | +0.166 | NaN | loc |
| 0.20 | 0.25 | 0.087 | 0.100 | 0.626 | +0.121 | +0.122 | +0.081 | spray |
| 0.20 | 0.50 | 0.071 | 0.141 | 0.606 | +0.085 | +0.085 | +0.191 | bias |
| 0.20 | 0.75 | 0.050 | 0.173 | 0.574 | +0.055 | +0.056 | +0.335 | bias |
| 0.20 | 0.90 | 0.032 | 0.190 | 0.547 | +0.033 | +0.033 | +0.440 | bias |
| 0.20 | 1.00 | 0.000 | 0.200 | 1.000 | NaN | NaN | +0.000 | none (bias) |
| 0.30 | 0.00 | 0.150 | 0.000 | 0.359 | +0.149 | +0.151 | NaN | spray |
| 0.30 | 0.25 | 0.130 | 0.150 | 0.351 | +0.093 | +0.092 | +0.069 | loc |
| 0.30 | 0.50 | 0.106 | 0.212 | 0.311 | +0.029 | +0.030 | +0.193 | bias |
| 0.30 | 0.75 | 0.075 | 0.260 | 0.210 | -0.026 | -0.026 | +0.409 | bias |
| 0.30 | 0.90 | 0.047 | 0.285 | 0.080 | -0.036 | -0.036 | +0.664 | bias |
| 0.30 | 1.00 | 0.000 | 0.300 | 0.000 | NaN | NaN | +1.000 | bias |
| 0.50 | 0.00 | 0.250 | 0.000 | 0.149 | +0.078 | +0.078 | NaN | spray |
| 0.50 | 0.25 | 0.217 | 0.250 | 0.143 | +0.041 | +0.042 | +0.037 | spray |
| 0.50 | 0.50 | 0.177 | 0.354 | 0.117 | -0.002 | -0.001 | +0.105 | bias |
| 0.50 | 0.75 | 0.125 | 0.433 | 0.051 | -0.023 | -0.023 | +0.224 | bias |
| 0.50 | 0.90 | 0.079 | 0.474 | 0.004 | -0.004 | -0.004 | +0.269 | bias |
| 0.50 | 1.00 | 0.000 | 0.500 | 0.000 | NaN | NaN | +0.000 | none (bias) |

## Smooth outcome (UNCALIBRATED Gaussian kernel, sigma_k = 0.134 m)

A Gaussian deposition kernel is exactly equivalent to adding sigma_k to the spray scatter (convolution of Gaussians), so it is not an independent mechanism. Best intervention differs from binary capture in 0 of 60 cells where both are decision-relevant and untied; cells where binary capture shows a material gain but the smooth outcome does not: 0.

## Sanity checks

| check | pass | detail |
|---|---|---|
| P_capture within [0, 1] | PASS |  |
| increasing R never reduces capture (exact under common random numbers) | PASS |  |
| R > 0, b = 0, both sigmas 0 => P_capture = 1 | PASS |  |
| b = 0: swapping sigma_loc and sigma_spray leaves P_capture unchanged (MC tolerance) | PASS | max diff 0.0015, tol 0.0045 |
| equal sigmas, b = 0: equal intervention values (MC tolerance) | PASS | max diff 0.0006 |
| Monte Carlo vs analytical Rayleigh / Rice capture, all 576 cells (tol 4 SE) | PASS | max |MC - analytic| 0.0017, tol 0.0045 |
| zero-bias cells vs analytical Rayleigh baseline | PASS | max 0.0015 |
| common random numbers: identical draws regenerated from the stored seed | PASS |  |
| exact reproducibility of a cell from the stored seed | PASS | 0.341890 |
| no existing source / results modified (git status: only this runner and its folder) | PASS |  |
| frozen checksums unchanged (FrozenExperimentIntegrityTest) | PASS |  |

<!-- ANALYST ANSWERS: written after reviewing the tables above -->

## Answers (analyst; within this simplified uncertainty model)

Supporting numbers come from the tables above and from `intervention_values.csv` / `baseline_predictions.csv`, split by bias level.

1. **Circular / isotropic case: yes, it reduces exactly to combined variance.** With b = 0, capture is the Rayleigh probability 1 − exp(−R² / 2σ_tot²), σ_tot = √(σ_loc² + σ_spray²). Monte Carlo matches it within 0.0015.
   - With bias, capture is the Rice probability. It depends only on (σ_tot / R, b / R).
   - Everything isotropic is analytically closed-form, and the Monte Carlo adds nothing beyond verification.
2. **Beyond "largest variance wins": no information for the localization-vs-spray choice.**
   - In b = 0 cells, A and C are 100 % correct on the 68 non-tie decision-relevant cells (max regret 0.001).
   - Even with bias, "halve the larger σ" is 100 % correct whenever the choice is loc vs spray (226 cells, regret 0), because both enter only through σ_tot.
   - Baseline B (normalized by R) is identical to A in 100 % of cells: R cancels, so it adds nothing.
   - The only information beyond scalar rules concerns **bias versus scatter**.
3. **Target radius: only rescales.** The pattern is a function of σ/R and b/R. For example, R = 0.4 and R = 0.8 with doubled σ and b give identical values.
   - The best possible gain from a 50 % improvement is 47 pp at every R.
   - The number of cells on this fixed absolute grid with a material (≥ 2 pp) gain falls from 31 / 36 (R = 0.10) to 16 / 36 (R = 0.80): bigger targets need bigger errors before any upgrade matters.
4. **Localization improvement helps materially** where σ_loc ≥ σ_spray and σ_tot is comparable to R. At R = 0.20, b = 0: σ_loc ≥ 0.1 with σ_spray ≤ σ_loc, gains 13–47 pp, largest near σ_loc ≈ R.
5. **Spray-dispersion improvement helps materially** in the mirror region (σ_spray > σ_loc and σ_spray ≳ 0.1 at R = 0.20). Gains are largest (≈ 47 pp) at σ_spray ≈ R.
6. **Neither helps materially** in 149 of 576 cells:
   - When σ_tot ≪ R, capture is already about 1.
   - When σ_tot ≫ R, a 50 % reduction cannot reach the target.
   - When b > R, scatter reduction is useless or harmful: in 69 cells, halving a random error *reduces* capture by > 0.5 pp, all with b > R. Scatter is what occasionally lands a biased cloud on the target.
7. **Equal RMS landing error, different capture: yes, strongly.** At RMS 0.30 m, capture falls from 36 % (all scatter) to 8 % (90 % bias) to 0 % (all bias), and the preferred intervention flips from loc / spray to bias at a bias share of about 0.5.
   - The RMS 0.20 m, bias-share 1.0 point (b = R exactly, zero scatter → 100 %) is a knife-edge artifact.
   - RMS landing error alone is therefore not a sufficient requirement metric.
8. **Anisotropy and target geometry:**
   - Spray anisotropy on a circular target, at equal spray variance, rarely changes the preferred intervention (1–3 % of cells).
   - **Elongated targets aligned with the bias direction** do: 8–11 % (2:1) and 16–21 % (4:1) of cells flip, mostly from "fix bias" to a random-error improvement, because the long axis absorbs the bias.
   - The same targets aligned across the bias flip only 0–5 %.
   - C accuracy drops to 0.76–0.79 for 4:1 targets along the bias, against 0.88–1.0 across it.
   - The relevant factor is the **orientation of the bias / drift relative to the target's long axis**, not anisotropy itself.
9. **Baseline accuracy** (decision-relevant cells):

   | Baseline | Accuracy | Notes |
   |---|---|---|
   | A | 0.70 | blind to bias: 0.27 at b = 0.50 |
   | B | 0.70 | = A |
   | C | 0.95 (0.956 non-tie) | 1.00 at b ≤ 0.10, 0.91–0.93 at b = 0.25–0.50 |
   | C, anisotropy / geometry set | 0.76–1.00 | |

10. **Largest baseline regret:**
    - **A:** 1.00, choosing a random-error fix when halving the bias takes capture from 0 to 1.
    - **C:** 0.098 (about 10 pp) on circular targets. It occurs at b / R ≈ 0.6 with σ_tot / R ≈ 0.5, where the bias is the largest term but still lies *inside* the target, so halving it is worth less than halving σ.
    - **C, elongated targets aligned with the bias:** up to 0.24.
11. **Non-trivial phenomenon:** the *composition* of the landing error (systematic bias vs random scatter) relative to the target's size **and shape / orientation** decides which subsystem upgrade pays, including regions where reducing scatter is harmful (b > R). No scalar error rule (RMS, largest σ, largest term) captures this.
    - It is classical CEP / Rice-distribution geometry, not a new mathematical effect. Its relevance here is as a requirement map.
    - Link to the mission pilot (error_propagation_pilot_v1): its compensated wind runs had landing bias ≈ 0.36 m and scatter ≈ 0.28 m against R = 0.20 m, i.e. b / R ≈ 1.8. That is inside the "scatter reduction does not help, fix the bias" regime here. This is model-based in both pilots.
12. **Could it disappear under other bounds? Partly.**
    - If calibrated drift turns out unbiased after compensation (b ≪ R), the problem collapses to the trivial variance rule.
    - If targets are effectively circular, or drift is not aligned with rows, the geometry effect shrinks to ≤ 5 %.
    - The 50 % intervention size, the 2 pp / 0.5 pp thresholds and equal intervention costs are all assumptions.
    - The Gaussian smooth outcome changes nothing (0 of 60 decisions). That is exact: a Gaussian kernel is just extra scatter. A non-Gaussian kernel could behave differently and was not tested.
13. **Evidence still required before any real-world claim:**
    - Measured landing-position error decomposed into bias and scatter for a real platform: positioning and drift, ideally after compensation.
    - Real canopy footprint geometry and its orientation relative to the wind / flight direction.
    - Measured localization / geolocation error of the actual estimator.
    - Intervention costs.
    - ICAERUS UC2 2023 / 2024 (inspected read-only, nothing fitted): per-site canopy and ground coverage, deposits per cm², deposition and droplet quantiles DV1 / DV5 / DV9.
      - They contain **no** landing-position or localization errors, so they cannot set σ_spray, b or σ_loc.
      - The DV columns are labelled "(m)" in some sheets and "(µm)" in others, and the deposition unit appears garbled ("L/cm²", probably µL/cm²). Both must be resolved before any use.
      - They support only qualitative context: real canopy-vs-ground and site-to-site heterogeneity.

DECISION: B. PROCEED WITH NON-TRIVIAL EXTENSION

Justification:
- The circular / isotropic model is trivial: exact variance addition, and target size only rescales it. That rules out C, and an "uncertainty-budget selector" over loc vs spray would be mathematically trivial.
- Scalar baselines do fail systematically in one identifiable place: **bias-vs-scatter composition relative to target size, combined with target elongation aligned with the bias / drift direction**. C regret reaches 10–24 pp, A's reaches 100 pp, and scatter reduction becomes harmful for b > R. That rules out A.
- The extension should study exactly this factor (bias / R, σ / R, target aspect and orientation versus drift direction) before any mission-level Experiment G. Experiment G was not designed or run.
