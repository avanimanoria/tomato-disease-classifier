"""Flask API and web entry point for the mock UAV mission dashboard."""

from __future__ import annotations

from pathlib import Path
from threading import RLock
from typing import Any

from flask import Flask, jsonify, render_template, request
from flask_cors import CORS

try:
    from .simulation import MissionSimulator
except ImportError:  # Supports direct execution: python dashboard/app.py
    from simulation import MissionSimulator


BASE_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = BASE_DIR.parent

app = Flask(
    __name__,
    template_folder=str(BASE_DIR / "templates"),
    static_folder=str(BASE_DIR / "static"),
)
CORS(app)
ROOT = BASE_DIR
_state_lock = RLock()
_simulator: MissionSimulator | None = None


def current_simulator() -> MissionSimulator:
    if _simulator is None:
        raise RuntimeError("No mission has been started")
    return _simulator


@app.get("/")
def index() -> str:
    return render_template("index.html")


@app.get("/api/mission/status")
def mission_status() -> Any:
    with _state_lock:
        if _simulator is None:
            return jsonify({
                "status": "Ready",
                "mission_progress": 0,
                "covered_area_m2": 0.0,
                "disease_detected_percent": 0.0,
                "spray_used_ml": 0.0,
                "plants_treated": 0,
                "elapsed_seconds": 0.0,
            })
        return jsonify(current_simulator().get_status())


@app.get("/api/drone/telemetry")
def drone_telemetry() -> Any:
    with _state_lock:
        if _simulator is None:
            return jsonify({"status": "Ready", "position": {"x": 0, "y": 0}, "heading": 90, "speed": 0, "altitude": 0, "battery": 100})
        return jsonify(current_simulator().get_telemetry())


@app.get("/api/field/disease_map")
def disease_map() -> Any:
    with _state_lock:
        if _simulator is None:
            return jsonify({"field_dimensions": {"length": 50, "width": 30}, "grid_size": {"rows": 10, "cols": 10}, "cells": []})
        return jsonify(current_simulator().get_disease_map())


@app.get("/api/spray/log")
def spray_log() -> Any:
    with _state_lock:
        return jsonify([] if _simulator is None else current_simulator().get_spray_log())


@app.post("/api/mission/start")
def start_mission() -> Any:
    global _simulator
    payload = request.get_json(silent=True) or {}
    try:
        field_length = float(payload.get("field_length", 50))
        field_width = float(payload.get("field_width", 30))
        drone_speed = float(payload.get("drone_speed", 1.0))
        simulator = MissionSimulator(field_length, field_width, drone_speed)
        simulator.start()
    except (TypeError, ValueError) as error:
        return jsonify({"error": str(error)}), 400
    with _state_lock:
        _simulator = simulator
        return jsonify(_simulator.get_status()), 201


@app.post("/api/mission/stop")
def stop_mission() -> Any:
    with _state_lock:
        if _simulator is not None:
            _simulator.stop()
        return jsonify({"status": "Stopped"})


# --- Real Model Inference Integration ---
_classifier_model = None
_classifier_classes = None
_classifier_cfg = None

@app.post("/api/predict")
def predict_leaf() -> Any:
    global _classifier_model, _classifier_classes, _classifier_cfg
    if "image" not in request.files:
        return jsonify({"error": "No image uploaded. Use multipart/form-data with field 'image'"}), 400
    file = request.files["image"]
    if not file.filename:
        return jsonify({"error": "Empty filename"}), 400

    import tempfile, sys
    upload_dir = Path(tempfile.gettempdir()) / "fieldline_leaf_uploads"
    upload_dir.mkdir(parents=True, exist_ok=True)
    save_path = upload_dir / file.filename
    file.save(save_path)

    classifier_root = PROJECT_ROOT
    if str(classifier_root) not in sys.path:
        sys.path.insert(0, str(classifier_root))

    from src.config_loader import load_config
    from src.inference import load_model_and_classes, predict_image

    if _classifier_model is None:
        _classifier_cfg = load_config(classifier_root / "config/config.yaml")
        model_file = classifier_root / "models/best_model.keras"
        if not model_file.exists():
            return jsonify({"error": f"Model file not found at {model_file}"}), 503
        _classifier_model, _classifier_classes, _ = load_model_and_classes(_classifier_cfg, model_file)

    res = predict_image(_classifier_cfg, save_path, model=_classifier_model,
                        class_names=_classifier_classes, save_json=False)
    res["is_real_model_inference"] = True
    res["source_model"] = "MobileNetV3Small (Stage 1 trained)"
    return jsonify(res)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)

