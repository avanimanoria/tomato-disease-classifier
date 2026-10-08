"""Single-image inference with exactly the training preprocessing (inside the model) and no augmentation."""
from __future__ import annotations

import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np

from .config_loader import load_config, logs_path, models_path
from .dataset_loader import load_class_names, load_image_array
from .utils import utc_now_iso, write_json

CONFIDENCE_NOTE = ("Confidence indicates classifier certainty for this image; it does not measure infected leaf area "
                   "or disease severity.")


def load_model_and_classes(cfg: Dict[str, Any], model_path: Optional[Path] = None, class_names: Optional[List[str]] = None):
    import tensorflow as tf
    model_path = Path(model_path) if model_path else models_path(cfg, "best_model.keras")
    if not model_path.exists():
        raise FileNotFoundError(f"{model_path} not found. Train a model first.")
    class_names = class_names or load_class_names(cfg)
    model = tf.keras.models.load_model(model_path)
    if int(model.output_shape[-1]) != len(class_names):
        raise ValueError(f"Model outputs {model.output_shape[-1]} classes but class_names.json has {len(class_names)}.")
    return model, class_names, model_path


def predict_image(cfg: Dict[str, Any], image_path: Path, model=None, class_names: Optional[List[str]] = None,
                  model_path: Optional[Path] = None, save_json: bool = True, save_annotated: bool = False) -> Dict[str, Any]:
    if model is None:
        model, class_names, model_path = load_model_and_classes(cfg, model_path, class_names)
    elif class_names is None:
        class_names = load_class_names(cfg)
    image_path = Path(image_path)
    if not image_path.exists():
        raise FileNotFoundError(image_path)
    x = load_image_array(image_path, cfg)[None, ...]
    t0 = time.perf_counter()
    probs = np.asarray(model(x, training=False))[0]  # training=False => augmentation layers are inactive
    ms = (time.perf_counter() - t0) * 1000
    idx = int(np.argmax(probs))
    conf = float(probs[idx])
    thr = float(cfg["model"]["low_confidence_threshold"])
    warning = (f"Low confidence ({conf:.1%} < {thr:.0%}): the prediction is unreliable; check the image or retake it."
               if conf < thr else None)
    result = {"image_path": str(image_path), "predicted_class": class_names[idx], "confidence": conf,
              "class_probabilities": {c: float(p) for c, p in zip(class_names, probs)},
              "inference_time_ms": float(ms), "model_path": str(model_path) if model_path else "in-memory",
              "timestamp": utc_now_iso(), "low_confidence_warning": warning, "note": CONFIDENCE_NOTE}
    if save_json:
        out_dir = logs_path(cfg, "predictions/.keep").parent
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        out = out_dir / f"{image_path.stem}_{stamp}.json"
        write_json(out, result)
        result["prediction_json"] = str(out)
    if save_annotated:
        result["annotated_image"] = str(save_annotated_image(cfg, image_path, result))
    return result


def save_annotated_image(cfg: Dict[str, Any], image_path: Path, result: Dict[str, Any]) -> Path:
    import cv2
    img = cv2.imdecode(np.fromfile(str(image_path), dtype=np.uint8), cv2.IMREAD_COLOR)
    if img is None:
        from PIL import Image
        img = cv2.cvtColor(np.asarray(Image.open(image_path).convert("RGB")), cv2.COLOR_RGB2BGR)
    scale = max(img.shape[1] / 640, 0.6)
    lines = [(f"{result['predicted_class']}  {100 * result['confidence']:.1f}%", (0, 200, 0))]
    if result["low_confidence_warning"]:
        lines.append(("LOW CONFIDENCE - unreliable", (0, 0, 255)))
    pad = int(14 * scale)
    bar_h = int((34 * len(lines) + 10) * scale)
    cv2.rectangle(img, (0, 0), (img.shape[1], bar_h), (0, 0, 0), -1)
    for i, (txt, col) in enumerate(lines):
        cv2.putText(img, txt, (pad, int((30 + 34 * i) * scale)), cv2.FONT_HERSHEY_SIMPLEX, 0.9 * scale, col,
                    max(1, int(2 * scale)), cv2.LINE_AA)
    out = logs_path(cfg, "predictions/.keep").parent / f"{Path(image_path).stem}_annotated.jpg"
    cv2.imwrite(str(out), img)
    return out


def main(argv: Optional[List[str]] = None) -> int:
    import argparse, json
    ap = argparse.ArgumentParser(description="Classify one tomato leaf image")
    ap.add_argument("--image", required=True)
    ap.add_argument("--save-annotated", action="store_true")
    ap.add_argument("--model", default=None)
    ap.add_argument("--config", default=None)
    a = ap.parse_args(argv)
    try:
        r = predict_image(load_config(a.config), Path(a.image), model_path=a.model, save_annotated=a.save_annotated)
    except (FileNotFoundError, ValueError) as exc:
        print(f"ERROR: {exc}")
        return 1
    print(json.dumps(r, indent=2))
    return 0
