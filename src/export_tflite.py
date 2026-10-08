"""TensorFlow Lite export (float32 + dynamic-range). No calibration data is needed or used; consistency is
checked against VALIDATION images only. This module never reads the locked test folder."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np

from .config_loader import load_config, models_path, path_of, reports_path
from .dataset_loader import load_class_names, load_image_array
from .utils import list_images, setup_logging, utc_now_iso, write_json, write_text

FLOAT32_NAME = "tomato_disease_mobilenetv3_float32.tflite"
DYNAMIC_NAME = "tomato_disease_mobilenetv3_dynamic_range.tflite"


def select_validation_images(cfg: Dict[str, Any], n: int = 60) -> List[Path]:
    """Deterministic, evenly spaced sample of VALIDATION images."""
    imgs = list_images(path_of(cfg, "val_dir"), cfg["image"]["supported_extensions"])
    if len(imgs) <= n:
        return imgs
    step = len(imgs) / n
    return [imgs[int(i * step)] for i in range(n)]


def convert(model, quantize: bool) -> bytes:
    import tensorflow as tf
    conv = tf.lite.TFLiteConverter.from_keras_model(model)
    if quantize:
        conv.optimizations = [tf.lite.Optimize.DEFAULT]  # dynamic-range quantisation: no representative data
    return conv.convert()


def tflite_predict(tflite_path: Path, x: np.ndarray) -> np.ndarray:
    try:  # preferred runtime (tf.lite.Interpreter is deprecated from TF 2.20)
        from ai_edge_litert.interpreter import Interpreter
    except ImportError:
        import tensorflow as tf
        Interpreter = tf.lite.Interpreter
    it = Interpreter(model_path=str(tflite_path))
    it.allocate_tensors()
    inp, out = it.get_input_details()[0], it.get_output_details()[0]
    res = []
    for i in range(len(x)):
        it.set_tensor(inp["index"], x[i:i + 1].astype(inp["dtype"]))
        it.invoke()
        res.append(it.get_tensor(out["index"])[0])
    return np.array(res)


def export(cfg: Dict[str, Any], model_path: Optional[Path] = None, n_check: int = 60) -> Dict[str, Any]:
    import tensorflow as tf
    from .model import strip_augmentation
    model_path = Path(model_path) if model_path else models_path(cfg, "best_model.keras")
    if not model_path.exists():
        raise FileNotFoundError(f"{model_path} not found. Train first.")
    keras_model = tf.keras.models.load_model(model_path)
    inf_model = strip_augmentation(keras_model)
    f32, dyn = models_path(cfg, FLOAT32_NAME), models_path(cfg, DYNAMIC_NAME)
    f32.write_bytes(convert(inf_model, False))
    dyn.write_bytes(convert(inf_model, True))

    imgs = select_validation_images(cfg, n_check)
    report: Dict[str, Any] = {"generated_at": utc_now_iso(), "source_model": str(model_path)}
    if imgs:
        x = np.stack([load_image_array(p, cfg) for p in imgs])
        ref = np.asarray(keras_model(x, training=False))
        consistency = {}
        for name, path in (("float32", f32), ("dynamic_range", dyn)):
            p = tflite_predict(path, x)
            consistency[name] = {"images_compared": len(imgs),
                                 "top1_agreement_with_keras": float((p.argmax(1) == ref.argmax(1)).mean()),
                                 "max_abs_probability_difference": float(np.abs(p - ref).max())}
        report["consistency_check"] = {"images_used": "validation only (locked test set not used)", **consistency}
    else:
        report["consistency_check"] = "SKIPPED: no validation images available"
    s32, sdyn = f32.stat().st_size, dyn.stat().st_size
    report.update({"files": {FLOAT32_NAME: s32, DYNAMIC_NAME: sdyn},
                   "file_sizes_mb": {FLOAT32_NAME: round(s32 / 1e6, 2), DYNAMIC_NAME: round(sdyn / 1e6, 2)},
                   "dynamic_range_compression_pct_vs_float32": round(100 * (1 - sdyn / s32), 1),
                   "class_names": load_class_names(cfg) if models_path(cfg, "class_names.json").exists() else None,
                   "required_preprocessing": f"Input: float32 RGB image resized to {cfg['image']['height']}x{cfg['image']['width']} "
                                             "(bilinear), pixel values in [0, 255]. Do NOT normalise: rescaling is built into the "
                                             "model. Output: softmax probabilities in the order of class_names.",
                   "calibration_data": "none used (dynamic-range quantisation only; no full-int8 export)",
                   "raspberry_pi_note": "Use tflite-runtime (or tf.lite.Interpreter) on the Pi and benchmark there; "
                                        "latencies measured on a development machine do not transfer. Validate the .tflite "
                                        "on images captured with the real camera before relying on it."})
    write_json(reports_path(cfg, "tflite_export_report.json"), report)
    write_text(reports_path(cfg, "tflite_export_report.md"), render_md(report))
    return report


def render_md(r: Dict[str, Any]) -> str:
    L = ["# TFLite export report", "", f"Generated: {r['generated_at']}  ", f"Source: `{r['source_model']}`", "", "## Files", ""]
    L += [f"- `{k}`: {v} MB" for k, v in r["file_sizes_mb"].items()]
    L += [f"- Dynamic-range size reduction vs float32: {r['dynamic_range_compression_pct_vs_float32']}%", "",
          "## Keras vs TFLite consistency (validation images only)", ""]
    cc = r["consistency_check"]
    if isinstance(cc, dict):
        for k in ("float32", "dynamic_range"):
            L.append(f"- {k}: top-1 agreement {cc[k]['top1_agreement_with_keras']:.3f} over {cc[k]['images_compared']} images, "
                     f"max |Δp| {cc[k]['max_abs_probability_difference']:.4f}")
    else:
        L.append(f"- {cc}")
    L += ["", "## Required preprocessing", "", r["required_preprocessing"], "", "## Calibration", "", r["calibration_data"],
          "", "## Raspberry Pi", "", r["raspberry_pi_note"], ""]
    return "\n".join(L)


def main(argv: Optional[List[str]] = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Export best_model.keras to TensorFlow Lite")
    ap.add_argument("--model", default=None)
    ap.add_argument("--config", default=None)
    a = ap.parse_args(argv)
    setup_logging("tomato")
    try:
        r = export(load_config(a.config), a.model)
    except FileNotFoundError as exc:
        print(f"ERROR: {exc}")
        return 1
    print(f"Exported: {r['file_sizes_mb']}  (reports/tflite_export_report.md)")
    return 0
