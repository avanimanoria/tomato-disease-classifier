"""Metrics, warnings, plots and markdown helpers shared by training and evaluation."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402
import seaborn as sns  # noqa: E402
from sklearn.metrics import classification_report, confusion_matrix  # noqa: E402

SMALL_TEST_MSG = ("WARNING: The test set contains fewer than 20 images per class. The result is statistically "
                  "unstable and should be presented as preliminary.")
HONEST_TEST_MSG = ("The model achieved the reported score on a locked internal test set. This result does not "
                   "establish field or drone deployment performance unless the test images were independently "
                   "collected under representative field/drone conditions.")


def sparse_ce_loss(y_true: np.ndarray, probs: np.ndarray) -> float:
    p = np.clip(probs[np.arange(len(y_true)), y_true], 1e-7, 1.0)
    return float(-np.mean(np.log(p)))


def compute_metrics(y_true: np.ndarray, probs: np.ndarray, class_names: List[str]) -> Dict[str, Any]:
    y_pred = probs.argmax(axis=1)
    labels = list(range(len(class_names)))
    rep = classification_report(y_true, y_pred, labels=labels, target_names=class_names, output_dict=True,
                                zero_division=0)
    cm = confusion_matrix(y_true, y_pred, labels=labels)
    with np.errstate(divide="ignore", invalid="ignore"):
        cmn = np.nan_to_num(cm / cm.sum(axis=1, keepdims=True))
    return {
        "n_samples": int(len(y_true)), "loss": sparse_ce_loss(y_true, probs), "accuracy": float((y_true == y_pred).mean()),
        "per_class": {c: {k: float(rep[c][k]) for k in ("precision", "recall", "f1-score")} | {"support": int(rep[c]["support"])}
                      for c in class_names},
        "macro_precision": float(rep["macro avg"]["precision"]), "macro_recall": float(rep["macro avg"]["recall"]),
        "macro_f1": float(rep["macro avg"]["f1-score"]),
        "weighted_precision": float(rep["weighted avg"]["precision"]),
        "weighted_recall": float(rep["weighted avg"]["recall"]), "weighted_f1": float(rep["weighted avg"]["f1-score"]),
        "confusion_matrix": cm.tolist(), "confusion_matrix_normalized": cmn.round(4).tolist(),
        "class_names": list(class_names), "classification_report": rep,
    }


def validation_warnings(m: Dict[str, Any], y_pred: np.ndarray, min_per_class: int = 20) -> List[str]:
    w = []
    if m["accuracy"] < 0.75:
        w.append(f"Validation accuracy {m['accuracy']:.3f} is below 0.75.")
    if m["macro_f1"] < 0.70:
        w.append(f"Macro F1 {m['macro_f1']:.3f} is below 0.70.")
    for c, v in m["per_class"].items():
        if v["recall"] < 0.60:
            w.append(f"Recall for class '{c}' is {v['recall']:.3f} (< 0.60).")
    counts = np.bincount(y_pred, minlength=len(m["class_names"]))
    share = counts / max(counts.sum(), 1)
    if len(m["class_names"]) > 1 and share.max() > 0.60:
        w.append(f"One class dominates predictions: '{m['class_names'][int(share.argmax())]}' = {share.max():.0%}.")
    if any(v["support"] < min_per_class for v in m["per_class"].values()):
        w.append(f"Validation set is small (fewer than {min_per_class} images in at least one class); "
                 "metrics are unstable.")
    return w


def plot_confusion_matrix(cm: Any, class_names: List[str], path: Path, normalized: bool, title: str) -> None:
    cm = np.array(cm)
    fig, ax = plt.subplots(figsize=(6.2, 5.2))
    sns.heatmap(cm, annot=True, fmt=".2f" if normalized else "d", cmap="Blues", xticklabels=class_names,
                yticklabels=class_names, cbar=True, ax=ax, vmin=0, vmax=1 if normalized else None)
    ax.set_xlabel("Predicted"); ax.set_ylabel("True"); ax.set_title(title)
    plt.setp(ax.get_xticklabels(), rotation=30, ha="right")
    fig.tight_layout(); Path(path).parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=150); plt.close(fig)


def plot_history(stage1_csv: Optional[Path], ft_csv: Optional[Path], acc_path: Path, loss_path: Path) -> None:
    frames, split_at = [], None
    for csv in (stage1_csv, ft_csv):
        if csv and Path(csv).exists():
            d = pd.read_csv(csv)
            if csv is ft_csv and frames:
                split_at = sum(len(f) for f in frames)
            frames.append(d)
    if not frames:
        return
    h = pd.concat(frames, ignore_index=True)
    x = np.arange(1, len(h) + 1)
    for key, path, ylabel in (("accuracy", acc_path, "Accuracy"), ("loss", loss_path, "Loss")):
        fig, ax = plt.subplots(figsize=(7, 4.2))
        ax.plot(x, h[key], label=f"train {key}")
        ax.plot(x, h[f"val_{key}"], label=f"validation {key}")
        if split_at:
            ax.axvline(split_at + 0.5, color="gray", ls="--", label="fine-tuning starts")
        ax.set_xlabel("Epoch (stage 1 + fine-tuning)"); ax.set_ylabel(ylabel); ax.legend(); ax.grid(alpha=.3)
        fig.tight_layout(); Path(path).parent.mkdir(parents=True, exist_ok=True)
        fig.savefig(path, dpi=150); plt.close(fig)


def metrics_table_md(m: Dict[str, Any]) -> str:
    L = ["| Class | Precision | Recall | F1 | Support |", "|---|---|---|---|---|"]
    for c, v in m["per_class"].items():
        L.append(f"| {c} | {v['precision']:.3f} | {v['recall']:.3f} | {v['f1-score']:.3f} | {v['support']} |")
    L.append(f"| **macro avg** | {m['macro_precision']:.3f} | {m['macro_recall']:.3f} | {m['macro_f1']:.3f} | {m['n_samples']} |")
    L.append(f"| **weighted avg** | {m['weighted_precision']:.3f} | {m['weighted_recall']:.3f} | {m['weighted_f1']:.3f} | {m['n_samples']} |")
    return "\n".join(L)
