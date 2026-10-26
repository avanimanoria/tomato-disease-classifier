"""Two-stage training using TRAIN and VALIDATION data only. Model selection uses validation loss
(and validation macro F1 for reporting). This module never touches the locked test folder."""
from __future__ import annotations

import logging
import shutil
import time
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np

from .config_loader import load_config, logs_path, models_path, path_of, reports_path
from .dataset_loader import load_train_val
from .reporting import compute_metrics, plot_history
from .split_dataset import verify_test_lock
from .utils import list_images, set_global_seed, setup_logging, utc_now_iso, write_json, write_text

log = logging.getLogger("tomato.train")
CONFIRMATION = "Training will use TRAIN and VALIDATION sets only. The locked test set will not be loaded."


def class_counts_from_paths(file_paths: List[str], class_names: List[str]) -> Dict[str, int]:
    c = Counter(Path(p).parent.name for p in file_paths)
    return {n: int(c.get(n, 0)) for n in class_names}


def compute_class_weights(counts: Dict[str, int], class_names: List[str], threshold: float) -> Optional[Dict[int, float]]:
    """Balanced class weights from TRAINING counts only; None if the data are balanced enough."""
    from sklearn.utils.class_weight import compute_class_weight
    vals = [v for v in counts.values() if v > 0]
    if not vals or max(vals) / min(vals) <= threshold:
        return None
    y = np.concatenate([np.full(counts[n], i) for i, n in enumerate(class_names)])
    w = compute_class_weight("balanced", classes=np.arange(len(class_names)), y=y)
    return {i: float(x) for i, x in enumerate(w)}


def make_callbacks(cfg, ckpt_path: Path, csv_path: Path, append: bool, initial_threshold: Optional[float] = None):
    import tensorflow as tf
    cb, t = tf.keras.callbacks, cfg["training"]
    return [
        cb.ModelCheckpoint(str(ckpt_path), monitor="val_loss", mode="min", save_best_only=True,
                           initial_value_threshold=initial_threshold),
        cb.EarlyStopping(monitor="val_loss", patience=int(t["early_stopping_patience"]), restore_best_weights=True),
        cb.ReduceLROnPlateau(monitor="val_loss", factor=float(t["reduce_lr_factor"]),
                             patience=int(t["reduce_lr_patience"]), min_lr=1e-6),
        cb.CSVLogger(str(csv_path), append=append),
        cb.TerminateOnNaN(),
    ]


def val_metrics_for(model_path: Path, val, class_names):
    import tensorflow as tf
    from .model import predict_dataset
    m = tf.keras.models.load_model(model_path)
    y, probs, _ = predict_dataset(m, val)
    return compute_metrics(y, probs, class_names), m


def run_training(cfg: Dict[str, Any], stage: str = "all", skip_fine_tune: bool = False, stage1_epochs: Optional[int] = None,
                 fine_tune_epochs: Optional[int] = None, batch_size: Optional[int] = None, resume: bool = False) -> Dict[str, Any]:
    import tensorflow as tf
    from .model import build_model, compile_model, count_params, find_base_model, set_fine_tune_layers

    t0 = time.time()
    set_global_seed(int(cfg["seed"]))
    tcfg = cfg["training"]
    s1_epochs = int(stage1_epochs or tcfg["stage1_epochs"])
    ft_epochs = int(fine_tune_epochs or tcfg["fine_tune_epochs"])

    # ---- pre-flight checks --------------------------------------------------
    for key in ("train_dir", "val_dir"):
        d = path_of(cfg, key)
        if not list_images(d, cfg["image"]["supported_extensions"]):
            raise RuntimeError(f"No images found in {d}. Run the split first: python scripts/split_dataset.py")
    lock = verify_test_lock(cfg, write_report=True)
    if not lock["passed"]:
        raise RuntimeError("Test-lock verification FAILED; refusing to train:\n  - " + "\n  - ".join(lock["failures"]))
    print(CONFIRMATION)

    train, val = load_train_val(cfg, batch_size)
    class_names = train.class_names
    counts = class_counts_from_paths(train.file_paths, class_names)
    val_counts = class_counts_from_paths(val.file_paths, class_names)
    weights = compute_class_weights(counts, class_names, float(tcfg["class_imbalance_ratio_threshold"]))
    print(f"Class order (from TensorFlow loader): {class_names}")
    print(f"Train counts: {counts} | Validation counts: {val_counts}")
    if weights:
        print(f"Class weights (training data only): { {class_names[k]: round(v, 3) for k, v in weights.items()} }")
        write_json(logs_path(cfg, "class_weights.json"), {"class_weights_by_index": weights,
                   "class_weights_by_name": {class_names[k]: v for k, v in weights.items()},
                   "train_counts": counts, "computed_from": "training split only"})
    else:
        print("Classes are balanced enough: no class weighting used.")
        write_json(logs_path(cfg, "class_weights.json"), {"class_weighting_used": False, "train_counts": counts,
                   "note": "No class weighting was needed."})

    s1_path = models_path(cfg, "stage1_best_model.keras")
    best_path = models_path(cfg, "best_model.keras")
    s1_csv, ft_csv = logs_path(cfg, "training_history_stage1.csv"), logs_path(cfg, "training_history_finetune.csv")
    marker = logs_path(cfg, "stage1_complete.json")
    summary: Dict[str, Any] = {"class_names": class_names, "train_counts": counts, "val_counts": val_counts}

    # ---- stage 1: train head ----------------------------------------------------
    run_s1 = stage in ("all", "stage1") and not (resume and marker.exists() and s1_path.exists())
    if run_s1:
        if resume and s1_path.exists():
            model = tf.keras.models.load_model(s1_path)
            print("Resuming stage 1 from the saved checkpoint.")
        else:
            model, _ = build_model(cfg, len(class_names))
        compile_model(model, float(tcfg["stage1_learning_rate"]))
        print(f"\n=== Stage 1: training classification head (max {s1_epochs} epochs) ===")
        hist = model.fit(train.ds, validation_data=val.ds, epochs=s1_epochs, class_weight=weights, shuffle=False,
                         callbacks=make_callbacks(cfg, s1_path, s1_csv, append=resume))
        write_json(marker, {"completed_at": utc_now_iso(), "best_val_loss": float(min(hist.history["val_loss"]))})
    if not s1_path.exists():
        raise RuntimeError("stage1_best_model.keras not found. Run stage 1 first.")
    s1_metrics, _ = val_metrics_for(s1_path, val, class_names)
    summary["stage1_val"] = {k: s1_metrics[k] for k in ("loss", "accuracy", "macro_f1", "weighted_f1")}
    print(f"Stage 1 best -> val_loss={s1_metrics['loss']:.4f} acc={s1_metrics['accuracy']:.4f} macroF1={s1_metrics['macro_f1']:.4f}")
    selected, sel_metrics = "stage1", s1_metrics
    ran_ft = False

    # ---- stage 2: fine-tune last layers ----------------------------------------
    if stage in ("all", "finetune") and not skip_fine_tune:
        ran_ft = True
        best_path.unlink(missing_ok=True)
        model = tf.keras.models.load_model(s1_path)
        n_tr, n_all = set_fine_tune_layers(model, int(cfg["model"]["fine_tune_last_n_layers"]))
        compile_model(model, float(tcfg["fine_tune_learning_rate"]))
        print(f"\n=== Stage 2: fine-tuning {n_tr} weighted layers among the last {cfg['model']['fine_tune_last_n_layers']} of {n_all} base layers (BatchNorm frozen), max {ft_epochs} epochs ===")
        model.fit(train.ds, validation_data=val.ds, epochs=ft_epochs, class_weight=weights, shuffle=False,
                  callbacks=make_callbacks(cfg, best_path, ft_csv, append=False, initial_threshold=s1_metrics["loss"]))
        if best_path.exists():  # fine-tuning beat stage 1 on validation loss
            s2_metrics, _ = val_metrics_for(best_path, val, class_names)
            summary["stage2_val"] = {k: s2_metrics[k] for k in ("loss", "accuracy", "macro_f1", "weighted_f1")}
            selected, sel_metrics = "stage2_finetune", s2_metrics
        else:
            print("Fine-tuning did not improve validation loss; keeping the stage 1 model as the final model.")
            summary["stage2_val"] = None
            shutil.copy2(s1_path, best_path)
    elif stage in ("all", "stage1"):
        shutil.copy2(s1_path, best_path)

    final = tf.keras.models.load_model(best_path)
    params = count_params(final)
    summary.update({"selected_model": selected, "selection_rule": "lowest validation loss",
                    "final_val": {k: sel_metrics[k] for k in ("loss", "accuracy", "macro_f1", "weighted_f1")},
                    "params": params, "model_file_mb": round(best_path.stat().st_size / 1e6, 2),
                    "duration_seconds": round(time.time() - t0, 1), "class_weights_used": bool(weights)})

    write_json(logs_path(cfg, "training_config.json"), {"timestamp": utc_now_iso(), "seed": cfg["seed"], "stage": stage,
               "stage1_epochs_max": s1_epochs, "fine_tune_epochs_max": ft_epochs, "batch_size": batch_size or tcfg["batch_size"],
               "config": {k: v for k, v in cfg.items() if k != "_root"}, "class_names": class_names})
    write_json(reports_path(cfg, "validation_metrics.json"), {"note": "Validation set only. No locked test data used.",
               "selected_model": selected, **sel_metrics})
    plot_history(s1_csv, ft_csv if ran_ft and ft_csv.exists() else None,
                 reports_path(cfg, "training_accuracy.png"), reports_path(cfg, "training_loss.png"))
    write_text(reports_path(cfg, "training_summary.md"), render_training_summary(cfg, summary))
    print(f"\nFinal model: {best_path} (selected: {selected}). Training summary: reports/training_summary.md")
    return summary


def render_training_summary(cfg, s) -> str:
    n_train, n_val = sum(s["train_counts"].values()), sum(s["val_counts"].values())
    f = lambda d: "n/a" if not d else f"loss {d['loss']:.4f}, accuracy {d['accuracy']:.4f}, macro F1 {d['macro_f1']:.4f}"
    L = ["# Training summary", "", "## Dataset", "", f"- Train images: {n_train} — {s['train_counts']}",
         f"- Validation images: {n_val} — {s['val_counts']}", f"- Class order (TensorFlow loader): {s['class_names']}",
         f"- Class weights used: {s['class_weights_used']}", "", "## Model", "",
         f"- Architecture: {cfg['model']['architecture']} (ImageNet-pretrained base, preprocessing inside the model)",
         f"- Parameters: {s['params']['total']:,} total, {s['params']['trainable']:,} trainable "
         f"(~{s['params']['approx_float32_size_mb']} MB float32; saved .keras file {s['model_file_mb']} MB)",
         f"- Training duration: {s['duration_seconds']} s", "", "## Validation performance", "",
         f"- Stage 1 best: {f(s.get('stage1_val'))}", f"- Stage 2 best: {f(s.get('stage2_val'))}",
         f"- Selected model: **{s['selected_model']}** (rule: {s['selection_rule']})", "", "## Warnings", "",
         "- Validation metrics are measured on data that influenced model selection (early stopping, checkpointing); "
         "they are optimistic relative to the locked test set.",
         "- Limited data: small datasets give unstable estimates; curated leaf photos differ from real field/drone images.",
         "", "No locked test-set metrics were used during model training or selection.", ""]
    return "\n".join(L)


def main(argv: Optional[List[str]] = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Train on TRAIN, select on VALIDATION. Never touches the test set.")
    ap.add_argument("--stage", choices=["all", "stage1", "finetune"], default="all")
    ap.add_argument("--skip-fine-tune", action="store_true")
    ap.add_argument("--stage1-epochs", type=int, default=None)
    ap.add_argument("--fine-tune-epochs", type=int, default=None)
    ap.add_argument("--batch-size", type=int, default=None)
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--config", default=None)
    a = ap.parse_args(argv)
    setup_logging("tomato")
    try:
        run_training(load_config(a.config), a.stage, a.skip_fine_tune, a.stage1_epochs, a.fine_tune_epochs,
                     a.batch_size, a.resume)
    except (RuntimeError, FileNotFoundError, ValueError) as exc:
        print(f"\nTRAINING REFUSED / FAILED:\n{exc}")
        return 1
    return 0
