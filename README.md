# Tomato Leaf Disease Classifier (honest-evaluation edition)

## 1. Purpose
Classify a tomato leaf photo into exactly one class, with **scientifically honest, leakage-resistant evaluation**.
The goal is the best *real* generalisation on unseen images - not a flattering number. A credible 80-90 % on a
carefully separated test set is worth more than 100 % on a contaminated one. The model (MobileNetV3Small) is small
enough for later TensorFlow Lite / Raspberry Pi deployment.

## 2. Classes
`early_blight`, `healthy`, `late_blight` (class *order* is always taken from the TensorFlow loader and saved to `models/class_names.json`).

## 3. Architecture / workflow
```
Raw images -> manifest -> audit -> group-aware split -> train/validation -> locked test -> TFLite export -> inference
```
| Step | Command | Data it touches |
|---|---|---|
| manifest | `python scripts/create_manifest.py` | raw (read-only) |
| audit | `python scripts/audit_dataset.py` | raw + manifest (read-only) |
| split | `python scripts/split_dataset.py [--dry-run]` | raw -> copies into processed |
| verify lock | `python scripts/verify_locked_test.py` | hashes of test, train, val (no model) |
| train | `python scripts/train_model.py` | **train + validation only** |
| validate | `python scripts/evaluate_model.py --split val` | **validation only** |
| final test | `python scripts/evaluate_model.py --split test_locked --final-evaluation` | **locked test only** |
| export | `python scripts/export_model.py` | validation images only (consistency check) |
| predict | `python scripts/predict_image.py --image x.jpg` | one image |
| tests | `pytest -q` | synthetic temp data only |

## 4. Installation
```bash
python3 -m venv .venv && source .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install --upgrade pip
pip install -r requirements.txt                        # Python 3.10+
```
First training run downloads ImageNet weights (needs internet). If they cannot be loaded, training **stops** - it never silently uses random weights.

## 5. Dataset layout
Put **real** labelled images here (`.jpg .jpeg .png .webp`). Never put generated/placeholder images here.
```
data/raw/early_blight/   data/raw/healthy/   data/raw/late_blight/
```
Optionally use sub-folders to encode real sources: `data/raw/healthy/plant_017/IMG_0001.jpg` -> source group `healthy/plant_017`.
The software never modifies, moves or deletes raw files.

## 6. Adding meaningful source metadata
`create_manifest.py` infers `source_group` in this order: (1) sub-folder inside the class folder, (2) an explicit filename token such as
`plant12_...`, `session3_...`, `plot2_...`, (3) otherwise a **fallback group** (`fallback_<hash>`, one per image; `source_type = fallback_group`).
Fallback groups do **not** claim images come from different plants.
Open `data/metadata/image_manifest.csv` and edit `source_group`, `plant_id`, `capture_session`, `capture_date`, `camera_or_source`, `notes`
(set `source_type` to `manual`, or just change `source_group` - it is detected). Your edits survive re-running the manifest as long as the image path is unchanged.

## 7. Why group-wise splitting matters
Leaves from the same plant, field, day or camera session look alike. If some end up in training and others in test, the model can
"recognise the plant/session" instead of the disease and the test score is inflated. Group-wise splitting keeps every group in **one** split.

> Group-wise splitting is only scientifically meaningful if `source_group` represents a true independent source, such as a plant ID, farm plot, capture session, date/camera session, or original dataset source. File names alone may not be enough.

In addition, images that are byte-identical (SHA-256) or near-duplicates (perceptual hash, Hamming <= 6, configurable) are linked and forced into the same split.

## 8-9. Manifest and audit
```bash
python scripts/create_manifest.py      # -> data/metadata/image_manifest.csv
python scripts/audit_dataset.py        # -> reports/raw_dataset_audit.{md,json}, exact_duplicates.csv, near_duplicates.csv, label_conflict_candidates.csv
```
Read `reports/raw_dataset_audit.md`. Near-duplicates are "manual review required" - nothing is deleted automatically. Exact duplicates across classes are critical label-conflict warnings.
If ImageHash is missing: `pip install ImageHash Pillow`.

## 10. Safe splitting
```bash
python scripts/split_dataset.py --dry-run          # reports only, copies nothing
python scripts/split_dataset.py                    # 70/15/15, copies into data/processed/
```
Options: `--force-rebuild`, `--allow-fallback-groups`, `--allow-small-test-set`, `--seed 42`.
The split is **refused** if: an exact duplicate or source group crosses splits, a class is missing from any split, the locked test has < 20 images/class
(unless `--allow-small-test-set`), or group metadata is only fallback (unless `--allow-fallback-groups`). Label-conflict candidates are excluded and listed in `reports/split_conflict_review.csv`.
Processed data is never overwritten without `--force-rebuild`. Note: a rebuild creates a **new** locked test set - results on the old one must not guide tuning on the new one.
Outputs: `reports/split_manifest.csv`, `split_summary.{json,md}`, `split_leakage_check.{json,md}`, and `data/metadata/test_lock_manifest.json` (SHA-256 of every test image + manifest checksum).
WebP / palette / CMYK images are converted to RGB PNG when copied (TensorFlow cannot decode WebP); the split manifest records this.

## 11. Training (train + validation only)
```bash
python scripts/train_model.py            # options: --stage stage1|finetune, --skip-fine-tune, --stage1-epochs N, --fine-tune-epochs N, --batch-size N, --resume
```
Before training it verifies the test lock and prints "Training will use TRAIN and VALIDATION sets only. The locked test set will not be loaded."
Stage 1 trains the head (frozen MobileNetV3Small); stage 2 fine-tunes the last 25 layers (BatchNorm frozen, lr 1e-5). Checkpoints are chosen by **validation loss**
(stage 2 only replaces stage 1 if it beats it). Class weights are used only if the training imbalance ratio > 1.2. Augmentation (flip, rotation, zoom, contrast, brightness) exists only inside the model and is inactive at evaluation/inference.
Preprocessing is inside the model: feed raw RGB pixels in [0, 255].

## 12. Validation evaluation
`python scripts/evaluate_model.py --split val` -> `reports/validation_*` (metrics, report, confusion matrices) with warnings for acc < 0.75, macro F1 < 0.70, any recall < 0.60, a dominating class, or a tiny set.

## 13. Final locked test evaluation
```bash
python scripts/evaluate_model.py --split test_locked --final-evaluation
```
Without `--final-evaluation` it refuses. It re-verifies the lock, prints the final-evaluation warning, then writes `reports/final_test_*`
(metrics, report, confusion matrices, per-image predictions, summary). It logs each final evaluation in `logs/final_evaluation_history.json` and warns on repeats.
**Do not tune after seeing these numbers.** If you change anything, create a fresh split (new locked test) before the next final evaluation.

## 14. TensorFlow Lite export
`python scripts/export_model.py` -> float32 and dynamic-range `.tflite`, plus `reports/tflite_export_report.{md,json}`. No calibration data; consistency vs Keras is checked on validation images only.
On the Raspberry Pi install a LiteRT/TFLite runtime (`pip install ai-edge-litert` or `tflite-runtime`), feed float32 RGB 224x224 in [0,255] (no extra normalisation) and benchmark on the device.

## 15. Inference
```bash
python scripts/predict_image.py --image path/to/leaf.jpg [--save-annotated]
```
Writes JSON to `logs/predictions/`. Confidence below 0.50 triggers a warning. *Confidence indicates classifier certainty for this image; it does not measure infected leaf area or disease severity.*

## 16. Reading the metrics
- **Accuracy**: share of images classified correctly; misleading if classes are imbalanced.
- **Recall (per class)**: of the truly diseased leaves of a class, how many were found. Low recall for a disease class = missed disease.
- **Precision (per class)**: of the leaves predicted as a class, how many really are. Low precision = false alarms.
- **Macro F1**: unweighted mean of per-class F1; every class counts equally - the main headline metric here.
- **Weighted F1**: like macro F1 but weighted by class size; can hide a poor small class.
- **Confusion matrix**: rows = true class, columns = predicted. Off-diagonal cells show *which* classes get confused (e.g. early vs late blight). The normalised version shows per-class recall on the diagonal.
- Small test sets (< 20 images/class) give unstable numbers; no confidence intervals are computed or implied.

## 17. Honest reporting template
“On a locked internal test set containing [N] images across three classes, the model achieved [accuracy]% accuracy and [macro_f1] macro F1-score. The test split was separated using [grouping method]. These results estimate internal generalization only and do not by themselves demonstrate field or drone deployment performance.”

Fill `[grouping method]` truthfully, e.g. "verified plant-ID groups" or "duplicate-aware split with unverified fallback groups".

## 18. Limitations
- Curated dataset images differ from real drone/field images (lighting, distance, motion blur, occlusion, backgrounds).
- Group splitting is only as good as the source metadata; with fallback groups independence by plant/field/session is **not** guaranteed.
- Classifier confidence is not infection-area severity.
- Pesticide / spray actuation is out of scope.
- Real agricultural deployment needs agronomist, regulatory and safety validation.
- EXIF orientation is ignored consistently in training and inference; only three classes exist, so other diseases/species will be forced into one of them.

## 19. Troubleshooting
| Symptom | Fix |
|---|---|
| "Could not load pretrained ImageNet weights" | Check internet / proxy; weights are fetched from storage.googleapis.com once and cached in `~/.keras/models/` |
| "ImageHash ... required" | `pip install ImageHash Pillow` |
| Split refused: fallback groups | Add real `source_group` values, or `--allow-fallback-groups` (preliminary results only) |
| Split refused: test < 20/class | Add more images, or `--allow-small-test-set` (preliminary results only) |
| Training refused: test-lock failed | Read `reports/test_lock_verification.md`; never edit files under `data/processed/` by hand - rebuild the split |
| WebP images not used by TF | They are auto-converted to PNG during the split |

## 20. Git ignore policy
Ignored: virtual env, caches, `data/raw/`, `data/processed/`, the test-lock manifest, trained models (`*.keras *.h5 *.tflite`), `logs/`, and generated `reports/*.{png,csv,json}`.
`.gitkeep` files keep empty folders. Do not commit datasets or the test-lock manifest; back them up separately.
