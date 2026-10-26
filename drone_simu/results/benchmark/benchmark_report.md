# Experiment F - algorithm benchmark and scenario-conditioned selection
Run 2026-10-10 16:45, 623 simulated missions, 13.9 min (MATLAB 26.2.0.3386108 (R2026b)).
All numbers are SIMULATED with UNCALIBRATED, assumed parameters: relative comparisons only.
Primary metric (pre-specified): targetDepositionPct (simulated, % of emitted spray on truly diseased canopies).

## Routing (frozen all-diseased targets, equal speed)
- Shortest route: antColony, 82.0 m mean (-12.6% vs nearest-neighbour) over 5 fields.
  - fixedOrder             geometric  126.2 +- 10.6 m | flown  127.1 m | travel  84.7 s | +36.7% vs NN | plan 0.0 ms
  - nearestNeighbour       geometric   93.9 +- 19.8 m | flown   95.7 m | travel  63.8 s |  +0.0% vs NN | plan 0.1 ms
  - nearestNeighbour2opt   geometric   83.9 +- 15.9 m | flown   85.5 m | travel  57.0 s | -10.4% vs NN | plan 1.1 ms
  - nearestNeighbourOrOpt  geometric   82.0 +- 15.0 m | flown   83.6 m | travel  55.7 s | -12.3% vs NN | plan 90.3 ms
  - cheapestInsertion      geometric   84.4 +- 15.9 m | flown   86.2 m | travel  57.5 s |  -9.7% vs NN | plan 2.3 ms
  - antColony              geometric   82.0 +- 16.7 m | flown   83.6 m | travel  55.8 s | -12.6% vs NN | plan 272.6 ms
  - stage7Return           geometric  126.2 +- 10.6 m | flown  136.5 m | travel  91.0 s | +36.7% vs NN | plan 0.0 ms

## Pipelines (train / held-out test means)
  - PID | no compensation            train deposition   1.9 +-  0.9% (worst decile   0.1%) | treated   0.8% | off-field  0.0% |  74.0 Wh |   338 s
  - PID | no compensation            test  deposition   1.6 +-  0.6% (worst decile   0.0%) | treated   0.6% | off-field  0.1% |  66.4 Wh |   300 s
  - PID | wind compensation          train deposition  22.3 +-  7.0% (worst decile   9.8%) | treated  34.9% | off-field  0.0% |  74.1 Wh |   338 s
  - PID | wind compensation          test  deposition  25.4 +-  3.8% (worst decile  11.0%) | treated  48.4% | off-field  0.0% |  66.3 Wh |   300 s
  - PID | wind + lag compensation    train deposition  23.0 +-  7.4% (worst decile   9.8%) | treated  35.3% | off-field  0.0% |  74.1 Wh |   338 s
  - PID | wind + lag compensation    test  deposition  26.5 +-  4.0% (worst decile  11.7%) | treated  49.0% | off-field  0.0% |  66.3 Wh |   300 s
  - PurePursuit | no compensation    train deposition   2.0 +-  1.0% (worst decile   0.1%) | treated   0.9% | off-field  0.0% |  74.0 Wh |   338 s
  - PurePursuit | no compensation    test  deposition   1.6 +-  0.6% (worst decile   0.0%) | treated   0.4% | off-field  0.1% |  66.3 Wh |   300 s
  - PurePursuit | wind compensation  train deposition  22.4 +-  7.4% (worst decile   9.2%) | treated  34.5% | off-field  0.0% |  74.1 Wh |   338 s
  - PurePursuit | wind compensation  test  deposition  25.7 +-  3.9% (worst decile  11.2%) | treated  47.7% | off-field  0.0% |  66.3 Wh |   300 s
  - PurePursuit | wind + lag comp.   train deposition  23.4 +-  7.9% (worst decile   9.1%) | treated  35.3% | off-field  0.0% |  74.1 Wh |   338 s
  - PurePursuit | wind + lag comp.   test  deposition  26.9 +-  4.1% (worst decile  12.0%) | treated  48.7% | off-field  0.0% |  66.3 Wh |   300 s
- Pareto-optimal on test (deposition, off-field, energy, time): PurePursuit | wind + lag comp..

## Hypotheses
- H1 rank reversal: SUPPORTED - 3 configuration pair(s) swap order between conditions (> 1 pp).
- H2 selector beats best fixed on held-out tests: NOT SUPPORTED - best fixed "PurePursuit | wind + lag comp." 26.9%, selector 26.6%, oracle 27.0%; gain -0.35 pp (95% bootstrap CI -0.63..-0.13), wins/ties/losses 2/36/10; regret vs oracle 0.09 -> 0.44 pp.
- H3 interactions: SUPPORTED - largest two-factor interaction gust x loc = +2.9 pp (all configs).
- H4 robustness to an alternative (uncalibrated) spray kernel: SUPPORTED - Spearman 1.00 between configuration rankings, same best fixed: yes, selector choices agree in 92% of conditions.

## Single-feature ablation (Fully Corrected, one feature at a time)
  - original       deposition  55.2% | treated  88.1% | cross-track 0.015 m
  - payload        deposition  55.2% | treated  88.1% | cross-track 0.015 m
  - dynamics       deposition  52.2% | treated  88.1% | cross-track 0.054 m
  - energy         deposition  55.2% | treated  88.1% | cross-track 0.015 m
  - gusts          deposition  11.0% | treated   0.0% | cross-track 0.016 m
  - atmosphere     deposition  54.8% | treated  88.1% | cross-track 0.015 m
  - perception     deposition  55.2% | treated  88.1% | cross-track 0.015 m
  - localization   deposition  45.4% | treated  88.1% | cross-track 0.104 m
  - safety         deposition  55.2% | treated  88.1% | cross-track 0.015 m
  - actuation      deposition  45.6% | treated  88.1% | cross-track 0.015 m
  - guidance       deposition  54.9% | treated  88.1% | cross-track 0.066 m
  - ALL features   deposition  10.8% | treated   7.1% | cross-track 0.110 m

## Claim boundaries
- Simulation-based decision support only: no field validation, no agronomic efficacy.
- Not GPS-denied validated: the Kalman mode is a linear position filter on modelled sensors.
- Deposition kernels are uncalibrated; the disease classifier is parametric (teammate CNN not integrated).
- "Best" is conditional on these scenarios; novelty of scenario-conditioned selection is NOT established.
