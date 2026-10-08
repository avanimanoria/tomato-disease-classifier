"""Evaluation. `--split val` is for development. `--split test_locked` additionally REQUIRES --final-evaluation,
passes test-lock verification, and prints a warning first. TensorFlow is imported lazily so the guards run first."""
from __future__ import annotations

import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd

from .config_loader import load_config, logs_path, models_path, path_of, reports_path
from .reporting import (HONEST_TEST_MSG, SMALL_TEST_MSG, compute_metrics, metrics_table_md, plot_confusion_matrix,
                        validation_warnings)
from .utils import read_json, setup_logging, utc_now_iso, write_json, write_text

FINAL_WARNING = ("FINAL EVALUATION WARNING:\n"
                 "You are evaluating the frozen selected model on the locked test set.\n"
                 "Do not use these results to continue tuning the current model.\n"
                 "If you change architecture, data preprocessing, augmentation, thresholds, or hyperparameters after "
                 "seeing these results, create a fresh locked test split for the next final evaluation.")
REFUSAL = ("REFUSED: the locked test set is reserved for FINAL performance measurement and is never used during "
           "development.\nIf (and only if) the model is frozen and you accept the rules, re-run with:\n"
           "  python scripts/evaluate_model.py --split test_locked --final-evaluation\n"
           "For development use:  python scripts/evaluate_model.py --split val")


def single_image_latency_ms(model, loaded, n: int = 20) -> Dict[str, float]:
    """Single-image (batch=1) latency on this machine; NOT representative of Raspberry Pi speed."""
    x_all = next(iter(loaded.ds.unbatch().batch(n)))[0].numpy()
    model.predict(x_all[:1], verbose=0)  # warm-up
    times = []
    for i in range(len(x_all)):
        t0 = time.perf_counter()
        model(x_all[i:i + 1], training=False)
        times.append((time.perf_counter() - t0) * 1000)
    return {"images_timed": len(times), "mean_ms": float(np.mean(times)), "median_ms": float(np.median(times)),
            "max_ms": float(np.max(times))}


def run_evaluation(cfg: Dict[str, Any], split: str, final_evaluation: bool, batch_size: Optional[int] = None,
                   model_path: Optional[Path] = None) -> Dict[str, Any]:
    import tensorflow as tf
    from .dataset_loader import load_class_names, load_locked_test_dataset, load_val_dataset
    from .model import predict_dataset

    model_path = Path(model_path) if model_path else models_path(cfg, "best_model.keras")
    if not model_path.exists():
        raise FileNotFoundError(f"{model_path} not found. Train first: python scripts/train_model.py")
    class_names = load_class_names(cfg)

    if split == "test_locked":
        from .split_dataset import verify_test_lock
        lock = verify_test_lock(cfg, write_report=True)
        if not lock["passed"]:
            raise RuntimeError("Test-lock verification FAILED; refusing final evaluation:\n  - " + "\n  - ".join(lock["failures"]))
        print("\n" + "!" * 78 + "\n" + FINAL_WARNING + "\n" + "!" * 78 + "\n")
        hist_path = logs_path(cfg, "final_evaluation_history.json")
        hist = read_json(hist_path) if hist_path.exists() else []
        if hist:
            print(f"NOTE: the locked test set has already been evaluated {len(hist)} time(s) "
                  f"(last: {hist[-1]['timestamp']}). Repeated evaluation while iterating on the model invalidates it.\n")
        loaded = load_locked_test_dataset(cfg, final_evaluation_confirmed=True, batch_size=batch_size)
    else:
        loaded = load_val_dataset(cfg, batch_size)
    if loaded.class_names != class_names:
        raise ValueError(f"Class order mismatch: dataset {loaded.class_names} vs models/class_names.json {class_names}")

    model = tf.keras.models.load_model(model_path)
    if model.output_shape[-1] != len(class_names):
        raise ValueError("Model output size does not match class_names.json")
    y_true, probs, total_s = predict_dataset(model, loaded)
    m = compute_metrics(y_true, probs, class_names)
    y_pred = probs.argmax(axis=1)
    m["inference_time"] = {"batch_total_seconds": round(total_s, 3), "mean_ms_per_image_batched": 1000 * total_s / len(y_true),
                           "single_image": single_image_latency_ms(model, loaded),
                           "note": "Measured on the evaluation machine, not on Raspberry Pi."}
    m["model_path"], m["generated_at"], m["split"] = str(model_path), utc_now_iso(), split

    if split == "val":
        m["warnings"] = validation_warnings(m, y_pred)
        write_json(reports_path(cfg, "validation_metrics.json"), m)
        write_json(reports_path(cfg, "validation_classification_report.json"), m["classification_report"])
        plot_confusion_matrix(m["confusion_matrix"], class_names, reports_path(cfg, "validation_confusion_matrix.png"), False, "Validation confusion matrix")
        plot_confusion_matrix(m["confusion_matrix_normalized"], class_names, reports_path(cfg, "validation_confusion_matrix_normalized.png"), True, "Validation confusion matrix (row-normalised)")
        return m

    # ---- final test outputs ----------------------------------------------------
    lock_entries = {e["image_id"]: e for e in read_json(path_of(cfg, "test_lock_manifest"))["entries"]}
    rows = []
    for p, t, pr, pb in zip(loaded.file_paths, y_true, y_pred, probs):
        iid = Path(p).stem
        row = {"image_path": p, "image_id": iid, "true_label": class_names[t], "predicted_label": class_names[pr],
               "confidence": float(pb[pr])}
        row.update({f"probability_{c}": float(pb[i]) for i, c in enumerate(class_names)})
        row.update({"correct": bool(t == pr), "source_group": lock_entries.get(iid, {}).get("source_group", "")})
        rows.append(row)
    pd.DataFrame(rows).to_csv(reports_path(cfg, "final_test_predictions.csv"), index=False)
    min_n = int(cfg["split"]["minimum_test_images_per_class"])
    small = any(v["support"] < min_n for v in m["per_class"].values())
    m["small_test_set_warning"] = SMALL_TEST_MSG if small else None
    write_json(reports_path(cfg, "final_test_metrics.json"), m)
    write_json(reports_path(cfg, "final_test_classification_report.json"), m["classification_report"])
    plot_confusion_matrix(m["confusion_matrix"], class_names, reports_path(cfg, "final_test_confusion_matrix.png"), False, "Locked test confusion matrix")
    plot_confusion_matrix(m["confusion_matrix_normalized"], class_names, reports_path(cfg, "final_test_confusion_matrix_normalized.png"), True, "Locked test confusion matrix (row-normalised)")
    write_text(reports_path(cfg, "final_test_summary.md"), render_final_summary(m, small))
    hist.append({"timestamp": utc_now_iso(), "accuracy": m["accuracy"], "macro_f1": m["macro_f1"], "model": str(model_path)})
    write_json(logs_path(cfg, "final_evaluation_history.json"), hist)
    return m


def render_final_summary(m: Dict[str, Any], small: bool) -> str:
    st = m["inference_time"]["single_image"]
    L = ["# Final locked-test evaluation (held-out internal test performance)", "", f"Generated: {m['generated_at']}  ",
         f"Model: `{m['model_path']}`  ", f"Test images: {m['n_samples']}", "",
         f"- Loss: {m['loss']:.4f}", f"- Accuracy: {100 * m['accuracy']:.2f}%", f"- Macro F1: {m['macro_f1']:.4f}",
         f"- Weighted F1: {m['weighted_f1']:.4f}", "", metrics_table_md(m), "", "Confusion matrix (rows = true, cols = predicted; "
         f"order {m['class_names']}):", "", "```", str(np.array(m["confusion_matrix"])), "```", "",
         f"Inference time on this machine (single image): mean {st['mean_ms']:.1f} ms, median {st['median_ms']:.1f} ms "
         "(not Raspberry Pi timings).", "", HONEST_TEST_MSG, ""]
    if small:
        L += [SMALL_TEST_MSG, ""]
    L += ["No confidence intervals are reported: none were computed and none are implied.", ""]
    return "\n".join(L)


def main(argv: Optional[List[str]] = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Evaluate on validation (dev) or on the locked test set (final only)")
    ap.add_argument("--split", choices=["val", "test_locked"], required=True)
    ap.add_argument("--final-evaluation", action="store_true", help="REQUIRED for --split test_locked")
    ap.add_argument("--batch-size", type=int, default=None)
    ap.add_argument("--model", default=None)
    ap.add_argument("--config", default=None)
    a = ap.parse_args(argv)
    if a.split == "test_locked" and not a.final_evaluation:  # guard runs BEFORE any data/TensorFlow work
        print(REFUSAL)
        return 2
    setup_logging("tomato")
    cfg = load_config(a.config)
    try:
        m = run_evaluation(cfg, a.split, a.final_evaluation, a.batch_size, a.model)
    except (RuntimeError, FileNotFoundError, ValueError, PermissionError) as exc:
        print(f"\nEVALUATION REFUSED / FAILED:\n{exc}")
        return 1
    tag = "FINAL TEST" if a.split == "test_locked" else "VALIDATION"
    print(f"\n{tag}: n={m['n_samples']} loss={m['loss']:.4f} acc={100 * m['accuracy']:.2f}% "
          f"macroF1={m['macro_f1']:.4f} weightedF1={m['weighted_f1']:.4f}")
    for w in m.get("warnings", []):
        print(f"  warning: {w}")
    if m.get("small_test_set_warning"):
        print("  " + m["small_test_set_warning"])
    print("Reports written to reports/.")
    return 0
