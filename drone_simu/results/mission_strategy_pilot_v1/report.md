# Two-pass selective spraying value test (mission_strategy_pilot_v1)

> Within the current simulator: UNCALIBRATED spray model, synthetic detector, no wind, assumed hardware.
> Phase **screen**: 288 strategy evaluations (171 flown missions; blanket flown once per field and oracle once per truth, both reused across detector levels because they do not use detector output). Runtime 679 s. Sanity: ALL PASS.

Pareto tolerances (prespecified): treatment success within 1 pp, spray and time within 1 % count as equal.

## Scenario means (over seeds)

| scale | structure | prev. | detector | strategy | success % | missed % | healthy treated % | spray L | duration s | revisit m | energy Wh | refills |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| small | clustered | 5% | HIGH | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 5% | HIGH | onePass | 97.6 | 2.4 | 3.3 | 1.10 | 163 | 4 | 37.1 | 0.0 |
| small | clustered | 5% | HIGH | oracle | 100.0 | 0.0 | 0.0 | 0.70 | 159 | 33 | 39.7 | 0.0 |
| small | clustered | 5% | HIGH | twoPass | 97.6 | 2.4 | 3.3 | 1.10 | 198 | 56 | 48.0 | 0.0 |
| small | clustered | 5% | LOW | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 5% | LOW | onePass | 54.8 | 45.2 | 19.8 | 2.92 | 322 | 37 | 67.0 | 1.0 |
| small | clustered | 5% | LOW | oracle | 100.0 | 0.0 | 0.0 | 0.70 | 159 | 33 | 39.7 | 0.0 |
| small | clustered | 5% | LOW | twoPass | 54.8 | 45.2 | 19.8 | 2.92 | 386 | 131 | 84.9 | 1.0 |
| small | clustered | 5% | MEDIUM | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 5% | MEDIUM | onePass | 73.8 | 26.2 | 9.4 | 1.72 | 201 | 7 | 42.6 | 0.0 |
| small | clustered | 5% | MEDIUM | oracle | 100.0 | 0.0 | 0.0 | 0.70 | 159 | 33 | 39.7 | 0.0 |
| small | clustered | 5% | MEDIUM | twoPass | 73.8 | 26.2 | 9.4 | 1.72 | 246 | 74 | 56.6 | 0.0 |
| small | clustered | 20% | HIGH | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 20% | HIGH | onePass | 97.5 | 2.5 | 3.1 | 2.97 | 330 | 46 | 68.4 | 1.0 |
| small | clustered | 20% | HIGH | oracle | 100.0 | 0.0 | 0.0 | 2.70 | 348 | 96 | 76.8 | 1.0 |
| small | clustered | 20% | HIGH | twoPass | 97.5 | 2.5 | 3.1 | 2.97 | 376 | 113 | 83.0 | 1.0 |
| small | clustered | 20% | LOW | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 20% | LOW | onePass | 62.3 | 37.7 | 19.0 | 3.73 | 378 | 49 | 77.1 | 1.0 |
| small | clustered | 20% | LOW | oracle | 100.0 | 0.0 | 0.0 | 2.70 | 348 | 96 | 76.8 | 1.0 |
| small | clustered | 20% | LOW | twoPass | 62.3 | 37.7 | 19.0 | 3.73 | 446 | 149 | 96.0 | 1.0 |
| small | clustered | 20% | MEDIUM | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 20% | MEDIUM | onePass | 77.8 | 22.2 | 8.8 | 3.05 | 334 | 44 | 69.2 | 1.0 |
| small | clustered | 20% | MEDIUM | oracle | 100.0 | 0.0 | 0.0 | 2.70 | 348 | 96 | 76.8 | 1.0 |
| small | clustered | 20% | MEDIUM | twoPass | 77.8 | 22.2 | 8.8 | 3.05 | 390 | 126 | 85.8 | 1.0 |
| small | clustered | 50% | HIGH | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 50% | HIGH | onePass | 96.0 | 4.0 | 2.7 | 6.67 | 653 | 114 | 131.2 | 3.0 |
| small | clustered | 50% | HIGH | oracle | 100.0 | 0.0 | 0.0 | 6.75 | 737 | 233 | 153.9 | 3.0 |
| small | clustered | 50% | HIGH | twoPass | 96.0 | 4.0 | 2.7 | 6.67 | 730 | 229 | 152.3 | 3.0 |
| small | clustered | 50% | LOW | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 50% | LOW | onePass | 59.5 | 40.5 | 19.0 | 5.30 | 517 | 75 | 105.6 | 2.0 |
| small | clustered | 50% | LOW | oracle | 100.0 | 0.0 | 0.0 | 6.75 | 737 | 233 | 153.9 | 3.0 |
| small | clustered | 50% | LOW | twoPass | 59.5 | 40.5 | 19.0 | 5.30 | 585 | 175 | 123.9 | 2.0 |
| small | clustered | 50% | MEDIUM | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 50% | MEDIUM | onePass | 78.5 | 21.5 | 10.6 | 6.02 | 592 | 94 | 119.1 | 2.7 |
| small | clustered | 50% | MEDIUM | oracle | 100.0 | 0.0 | 0.0 | 6.75 | 737 | 233 | 153.9 | 3.0 |
| small | clustered | 50% | MEDIUM | twoPass | 78.5 | 21.5 | 10.6 | 6.02 | 667 | 204 | 139.3 | 2.7 |
| small | clustered | 80% | HIGH | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 80% | HIGH | onePass | 95.5 | 4.5 | 3.1 | 10.40 | 988 | 197 | 197.4 | 5.0 |
| small | clustered | 80% | HIGH | oracle | 100.0 | 0.0 | 0.0 | 10.80 | 1095 | 323 | 224.6 | 5.0 |
| small | clustered | 80% | HIGH | twoPass | 95.5 | 4.5 | 3.1 | 10.40 | 1057 | 301 | 216.4 | 5.0 |
| small | clustered | 80% | LOW | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 80% | LOW | onePass | 58.8 | 41.2 | 20.4 | 6.90 | 675 | 126 | 136.3 | 3.0 |
| small | clustered | 80% | LOW | oracle | 100.0 | 0.0 | 0.0 | 10.80 | 1095 | 323 | 224.6 | 5.0 |
| small | clustered | 80% | LOW | twoPass | 58.8 | 41.2 | 20.4 | 6.90 | 751 | 237 | 156.6 | 3.0 |
| small | clustered | 80% | MEDIUM | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | clustered | 80% | MEDIUM | onePass | 79.2 | 20.8 | 11.7 | 8.87 | 849 | 168 | 170.8 | 4.0 |
| small | clustered | 80% | MEDIUM | oracle | 100.0 | 0.0 | 0.0 | 10.80 | 1095 | 323 | 224.6 | 5.0 |
| small | clustered | 80% | MEDIUM | twoPass | 79.2 | 20.8 | 11.7 | 8.87 | 923 | 279 | 190.7 | 4.0 |
| small | dispersed | 5% | HIGH | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 5% | HIGH | onePass | 97.6 | 2.4 | 3.5 | 1.13 | 165 | 4 | 37.7 | 0.0 |
| small | dispersed | 5% | HIGH | oracle | 100.0 | 0.0 | 0.0 | 0.70 | 173 | 53 | 42.8 | 0.0 |
| small | dispersed | 5% | HIGH | twoPass | 97.6 | 2.4 | 3.5 | 1.13 | 210 | 70 | 50.4 | 0.0 |
| small | dispersed | 5% | LOW | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 5% | LOW | onePass | 76.2 | 23.8 | 20.1 | 3.10 | 334 | 39 | 69.5 | 1.0 |
| small | dispersed | 5% | LOW | oracle | 100.0 | 0.0 | 0.0 | 0.70 | 173 | 53 | 42.8 | 0.0 |
| small | dispersed | 5% | LOW | twoPass | 76.2 | 23.8 | 20.1 | 3.10 | 406 | 145 | 88.8 | 1.0 |
| small | dispersed | 5% | MEDIUM | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 5% | MEDIUM | onePass | 88.1 | 11.9 | 9.9 | 1.88 | 211 | 7 | 44.1 | 0.0 |
| small | dispersed | 5% | MEDIUM | oracle | 100.0 | 0.0 | 0.0 | 0.70 | 173 | 53 | 42.8 | 0.0 |
| small | dispersed | 5% | MEDIUM | twoPass | 88.1 | 11.9 | 9.9 | 1.88 | 265 | 87 | 59.9 | 0.0 |
| small | dispersed | 20% | HIGH | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 20% | HIGH | onePass | 96.9 | 3.1 | 3.5 | 3.00 | 327 | 38 | 68.5 | 1.0 |
| small | dispersed | 20% | HIGH | oracle | 100.0 | 0.0 | 0.0 | 2.70 | 378 | 139 | 83.1 | 1.0 |
| small | dispersed | 20% | HIGH | twoPass | 96.9 | 3.1 | 3.5 | 3.00 | 398 | 142 | 87.3 | 1.0 |
| small | dispersed | 20% | LOW | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 20% | LOW | onePass | 67.9 | 32.1 | 19.9 | 3.98 | 405 | 53 | 82.1 | 1.3 |
| small | dispersed | 20% | LOW | oracle | 100.0 | 0.0 | 0.0 | 2.70 | 378 | 139 | 83.1 | 1.0 |
| small | dispersed | 20% | LOW | twoPass | 67.9 | 32.1 | 19.9 | 3.98 | 478 | 160 | 101.7 | 1.3 |
| small | dispersed | 20% | MEDIUM | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 20% | MEDIUM | onePass | 88.3 | 11.7 | 9.6 | 3.42 | 358 | 47 | 73.8 | 1.0 |
| small | dispersed | 20% | MEDIUM | oracle | 100.0 | 0.0 | 0.0 | 2.70 | 378 | 139 | 83.1 | 1.0 |
| small | dispersed | 20% | MEDIUM | twoPass | 88.3 | 11.7 | 9.6 | 3.42 | 425 | 145 | 92.5 | 1.0 |
| small | dispersed | 50% | HIGH | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 50% | HIGH | onePass | 95.6 | 4.4 | 3.2 | 6.67 | 654 | 114 | 131.7 | 3.0 |
| small | dispersed | 50% | HIGH | oracle | 100.0 | 0.0 | 0.0 | 6.75 | 750 | 248 | 156.3 | 3.0 |
| small | dispersed | 50% | HIGH | twoPass | 95.6 | 4.4 | 3.2 | 6.67 | 748 | 253 | 155.9 | 3.0 |
| small | dispersed | 50% | LOW | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 50% | LOW | onePass | 62.0 | 38.0 | 18.8 | 5.45 | 513 | 55 | 104.1 | 2.0 |
| small | dispersed | 50% | LOW | oracle | 100.0 | 0.0 | 0.0 | 6.75 | 750 | 248 | 156.3 | 3.0 |
| small | dispersed | 50% | LOW | twoPass | 62.0 | 38.0 | 18.8 | 5.45 | 613 | 203 | 129.4 | 2.0 |
| small | dispersed | 50% | MEDIUM | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 50% | MEDIUM | onePass | 80.5 | 19.5 | 8.4 | 6.00 | 583 | 81 | 116.8 | 2.7 |
| small | dispersed | 50% | MEDIUM | oracle | 100.0 | 0.0 | 0.0 | 6.75 | 750 | 248 | 156.3 | 3.0 |
| small | dispersed | 50% | MEDIUM | twoPass | 80.5 | 19.5 | 8.4 | 6.00 | 684 | 231 | 142.5 | 2.7 |
| small | dispersed | 80% | HIGH | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 80% | HIGH | onePass | 95.2 | 4.8 | 4.3 | 10.40 | 988 | 196 | 197.2 | 5.0 |
| small | dispersed | 80% | HIGH | oracle | 100.0 | 0.0 | 0.0 | 10.80 | 1099 | 327 | 225.5 | 5.0 |
| small | dispersed | 80% | HIGH | twoPass | 95.2 | 4.8 | 4.3 | 10.40 | 1074 | 325 | 219.8 | 5.0 |
| small | dispersed | 80% | LOW | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 80% | LOW | onePass | 58.8 | 41.2 | 18.5 | 6.85 | 674 | 128 | 135.8 | 3.0 |
| small | dispersed | 80% | LOW | oracle | 100.0 | 0.0 | 0.0 | 10.80 | 1099 | 327 | 225.5 | 5.0 |
| small | dispersed | 80% | LOW | twoPass | 58.8 | 41.2 | 18.5 | 6.85 | 749 | 239 | 156.3 | 3.0 |
| small | dispersed | 80% | MEDIUM | blanket | 100.0 | 0.0 | 100.0 | 13.50 | 1228 | 383 | 245.1 | 6.0 |
| small | dispersed | 80% | MEDIUM | onePass | 78.7 | 21.3 | 9.3 | 8.75 | 836 | 158 | 167.8 | 4.0 |
| small | dispersed | 80% | MEDIUM | oracle | 100.0 | 0.0 | 0.0 | 10.80 | 1099 | 327 | 225.5 | 5.0 |
| small | dispersed | 80% | MEDIUM | twoPass | 78.7 | 21.3 | 9.3 | 8.75 | 924 | 289 | 190.7 | 4.0 |

## Pareto sets (deployable: twoPass, onePass, blanket)

| Pareto-efficient set | scenarios |
|---|---|
| onePass | 6 / 72 |
| onePass+blanket | 66 / 72 |

| twoPass dominated by | scenarios |
|---|---|
| onePass | 72 |

## Simple-baseline challenge

| rule | accuracy | mean regret | worst regret | n |
|---|---|---|---|---|
| B+C analytical Pareto set (exact set match) | 0.917 | NaN | NaN | 72 |
| B+C analytical winner: treatmentSuccess_pct | 0.917 | 0 | 0 | 72 |
| B+C analytical winner: emitted_L | 1.000 | 0 | 0 | 72 |
| B+C analytical winner: duration_s | 1.000 | 0 | 0 | 72 |
| A prevalence threshold for twoPass efficiency (best p* = 0.00, in-sample) | 1.000 | NaN | NaN | 72 |

Regret units: treatment success pp, spray L, duration s. Predictions use only scenario parameters and field geometry.

## Sanity checks

| check | pass | detail |
|---|---|---|
| same truth (plants, diseased count) across strategies in every paired scenario | PASS |  |
| same detector output for twoPass and onePass (identical flagged TP / FP sets) | PASS |  |
| blanket ignores detector output: one flight per field, identical duration / spray across detector levels | PASS | blanket sprays every plant |
| oracle sprays exactly the truly diseased plants (research-only, excluded from the deployable Pareto set) | PASS |  |
| spray accounting: emitted = nominal dose x sprayed targets (existing accounting) | PASS | max diff 1.8e-15 L |
| mission time / distance / energy finite and non-negative | PASS |  |
| prevalence sets only the disease truth (exact count = round(p N)); detector draws and geometry unchanged | PASS |  |
| same hardware / spray assumptions across strategies (one cfg per field; strategies differ only in mission plan) | PASS | by construction: makeField + prep |
| reproducibility from seeds (twoPass mission rebuilt; |diff| < 1e-9) | PASS | 201.800000 s vs 201.800000 s |
| no retuning after seeing outcomes (design fixed in the runner header) | PASS |  |
| no existing source / results / previous pilot folders modified (git status) | PASS |  |
| frozen Experiment F checksums unchanged | PASS |  |

<!-- ANALYST ANSWERS: written after reviewing the tables above -->

## Answers (analyst; within the current simulator; SCREEN phase only)

The screen covered the small field: 4 prevalence × 3 detector × 2 structure × 3 seeds = 72 paired scenarios. The full phase and the larger field were **not run**: the specification allows expansion only if structured trade-offs appear, and they did not.

1. **Two-pass never dominates.** It is not Pareto-efficient in any scenario (0 / 72).
2. **Two-pass is always dominated, by one-pass, in 72 / 72 scenarios.**
   - Both fly the identical survey and spray the identical flagged set, so treatment and spray are equal.
   - One-pass is 32–114 s shorter, because the revisit tour is removed.
   - **This follows from the one-pass approximation's assumption of zero detection-to-decision latency and no stop / backtrack penalty, not from a measured trade-off.**
3. **Strategy changes occur in only one place.** The deployable Pareto set is {onePass, blanket} in 66 / 72 scenarios and {onePass} in 6 / 72.
   - The 6 are HIGH-detector scenarios at 5–20 % prevalence where the selective mission happened to treat every diseased plant (small counts, e.g. 14 diseased plants). Blanket's only advantage, higher treatment success, then vanishes.
   - Blanket stays Pareto-efficient whenever detection misses any diseased plant, solely because it treats everything.
4. **Clustering does not change the answer.**
   - It shortens the two-pass revisit by 7–20 % (5 %: 56 vs 70 m; 80 %: 301 vs 325 m) and the duration by 1.5–5 %.
   - It changes no Pareto set: the modal Pareto set is the same for clustered and dispersed in every prevalence × detector cell.
5. **Chemical savings against blanket:** 92 % (5 %, HIGH) falling to 23 % (80 %, HIGH). With LOW detectors, 49–78 %; they are larger at high prevalence because LOW misses more diseased plants.
6. **Time / energy:**
   - There is no time penalty. Two-pass is **faster** than the stop-and-spray blanket in every scenario (−162 to −1024 s), because blanket hovers at all 270 plants (1228 s, 245 Wh, 6 refills).
   - Against a *continuous* boom blanket (not modelled) the sign would likely reverse. That is the main assumption behind "selective is faster".
7. **Treatment loss with imperfect detection, against blanket:** HIGH −2 to −5 pp, MEDIUM −17 to −21 pp, LOW −35 to −41 pp.
   - That is the detector sensitivity almost one-for-one. Healthy plants treated: 3 % / 10 % / 19 %, close to the false-positive rates.
8. **One-pass removes all revisit cost here,** which is what flips the two-pass result.
   - The break-even extra cost one-pass could carry per target before two-pass becomes competitive is 0.3–2.2 s (mean 1.4 s at 5 % prevalence, 0.5 s at 80 %).
   - A decision latency of a few tenths of a second that forces a stop-and-backtrack would plausibly exceed this.
   - This parameter is unmeasured and not modelled, and it decides the one-pass vs two-pass question entirely.
9. **Stability:** Pareto sets are identical across the 3 seeds in 20 of 24 scenario cells. The 4 that vary are the HIGH-detector, 5–20 % cells, where small counts decide whether every diseased plant was found.
10. **Simple analytical rules predict the choices almost perfectly:**
    - the sprayed fraction p·se + (1 − p)·fp, plus a dwell + BHH tour time model;
    - the exact Pareto set: 66 / 72 (92 %), with the 6 misses being the small-count cells in answer 3;
    - the least-spray and shortest-mission winners: 100 %, zero regret;
    - the best-treatment winner: 92 %, zero regret (ties within tolerance).
    - The optimistic prevalence-threshold rule A is trivially 100 %: two-pass is never efficient.
11. **The full simulator adds little decision value over those formulas.** Its added value is the magnitudes: revisit distance, refill count and energy. None of them changed a strategy decision.
12. **No non-trivial strategy boundary appeared.** The decision reduces to two facts:
    - "fewer stops = less time and spray" (sprayed-fraction formula),
    - "blanket wins only on treatment completeness".
    The only genuinely open boundary, one-pass vs two-pass, is set by an assumption the simulator does not model.
13. **Assumptions that control the result most strongly:**
    - zero one-pass decision latency and no backtrack (decides one-pass vs two-pass);
    - blanket modelled as stop-and-spray rather than continuous application (decides whether selective is faster than blanket);
    - the 3 s settle + dwell per plant (dominates every mission time);
    - perfect delivery when hovering in still air (no wind in this pilot);
    - tank 2 L / 50 mL dose (refills).
14. **Evidence still needed before practical claims:**
    - detection-to-decision latency and stopping distance of a real platform;
    - real blanket application rates and speeds;
    - real per-target dwell requirements;
    - real detector sensitivity / false-positive rates in the target crop;
    - field disease prevalence and clustering statistics;
    - energy and refill logistics for the actual airframe.

DECISION: A. STOP — STRATEGY TRADE-OFF IS TRIVIAL OR UNINFORMATIVE

Justification:
- Within the current simulator one deployable selective strategy (one-pass) dominates two-pass everywhere, and blanket survives only on treatment completeness.
- Simple sprayed-fraction and dwell-time formulas reproduce 92 % of Pareto sets and 100 % of the spray / time winners with zero regret.
- Clustering changes revisit cost by at most 20 % without changing any decision.
- The one comparison that could carry a real operating boundary (one-pass vs two-pass) is determined by detection latency / backtrack and by blanket application mode. The engine does not model either, so the pilot cannot inform it without new modelling, which is out of scope here.
