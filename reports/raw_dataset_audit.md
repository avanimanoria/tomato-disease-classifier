# Raw dataset audit

Generated: 2026-10-08T19:27:13+00:00  
Read-only: no raw file was modified.

**Verdict: PROCEED_WITH_CAUTION**

## Counts

- Files in manifest: 4500
- Valid images: 4500
- Invalid / unsupported: 0

| Class | Valid images | Source groups |
|---|---|---|
| early_blight | 1000 | 251 |
| healthy | 1591 | 836 |
| late_blight | 1909 | 1211 |

Class balance ratio (max/min): 1.91

## Image dimensions

- Width  min/median/max: 256 / 256 / 256
- Height min/median/max: 256 / 256 / 256
- Small images (below recommended size): 0
- Aspect ratios:
  - portrait (<0.75): 0
  - slightly portrait (0.75-0.9): 0
  - square-ish (0.9-1.1): 4500
  - slightly landscape (1.1-1.34): 0
  - landscape (>1.34): 0
- Modes: {'RGB': 4500}

## Duplicates

- Exact-duplicate sets: 14 (across classes: 0, across source groups: 0, within class: 14)
- Near-duplicate pairs (Hamming <= 6): 51 — **manual review required**, nothing was deleted
- Label-conflict candidates: 6

## Source-group metadata

Sufficient for verified group-wise splitting: **NO**

- 1582 of 4500 valid images only have a FALLBACK group (one group per image). Fallback groups do not prove independence by plant, field or capture session.

> Group-wise splitting is only scientifically meaningful if `source_group` represents a true independent source, such as a plant ID, farm plot, capture session, date/camera session, or original dataset source. File names alone may not be enough.

## Blockers

- none

## Warnings

- Class imbalance ratio 1.91 exceeds 1.2; class weights will be used in training.
- 14 exact-duplicate set(s) found; they are kept together in one split.
- 51 near-duplicate pair(s) (Hamming <= 6) need MANUAL REVIEW; they are kept together in one split.
- 3 near-duplicate pair(s) span different classes (possible label noise).
- Source-group metadata is NOT sufficient for a verified group-wise split (see group_metadata section).

Reports: `exact_duplicates.csv`, `near_duplicates.csv`, `label_conflict_candidates.csv`.
