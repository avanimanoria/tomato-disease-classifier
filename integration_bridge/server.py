"""Integration Bridge Server.

Exposes a localhost REST API and atomic file-based IPC to serve tomato disease
predictions and severity estimates from the read-only software_model to external
consumers (such as the MATLAB drone simulation).
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

# Ensure bytecode is never written to protected directories
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

# Resolve root and bridge directories
BRIDGE_DIR = Path(__file__).resolve().parent
REPO_ROOT = BRIDGE_DIR.parent
SOFTWARE_MODEL_DIR = REPO_ROOT / "software_model"

# Add software_model directory to sys.path for read-only library imports
if str(SOFTWARE_MODEL_DIR) not in sys.path:
    sys.path.insert(0, str(SOFTWARE_MODEL_DIR))

from src.config_loader import load_config
from src.inference import load_model_and_classes, predict_image
from src.severity_estimation import load_severity_config, estimate_leaf_severity

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.FileHandler(BRIDGE_DIR / "logs" / "bridge_server.log", encoding="utf-8"),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("BridgeServer")


class BridgeInferenceEngine:
    """Thread-safe engine managing in-memory model inference and severity estimation."""

    def __init__(self, config_path: Optional[Path] = None):
        self.bridge_config_path = config_path or (BRIDGE_DIR / "config" / "config.json")
        with open(self.bridge_config_path, "r", encoding="utf-8") as f:
            self.bridge_cfg = json.load(f)

        self.demo_threshold = float(
            self.bridge_cfg.get("thresholds", {}).get("classification_confidence_demo_threshold", 0.60)
        )

        software_cfg_path = REPO_ROOT / self.bridge_cfg["paths"]["software_config_path"]
        self.software_cfg = load_config(software_cfg_path, root=SOFTWARE_MODEL_DIR)

        model_path = REPO_ROOT / self.bridge_cfg["paths"]["model_path"]
        class_names_path = REPO_ROOT / self.bridge_cfg["paths"]["class_names_path"]

        logger.info(f"Loading disease model from {model_path}...")
        self.model, self.class_names, self.loaded_path = load_model_and_classes(
            self.software_cfg, model_path=model_path, class_names=None
        )
        logger.info(f"Model successfully loaded. Classes: {self.class_names}")

        sev_cfg_path = REPO_ROOT / self.bridge_cfg["paths"]["severity_config_path"]
        self.severity_cfg = load_severity_config(sev_cfg_path)
        logger.info("Severity estimation configuration loaded.")

    def predict_single(
        self,
        image_path: str | Path,
        mission_id: Optional[str] = None,
        request_id: Optional[str] = None,
        plant_id: Optional[Any] = None,
    ) -> Dict[str, Any]:
        """Execute disease prediction and severity estimation on a leaf image.

        Guarantees:
        - Reuses exact training preprocessing without double normalization.
        - Calls predict_image with save_json=False to prevent writes to software_model/logs/.
        - On any failure, returns explicit status="error" with spray_allowed=False,
          never fabricating healthy or 0 severity.
        """
        mission_id = str(mission_id) if mission_id is not None else "mission_unknown"
        request_id = str(request_id) if request_id is not None else f"req_{int(time.time()*1000)}"
        plant_id_val = plant_id if plant_id is not None else "unknown"

        img_p = Path(image_path)
        if not img_p.is_absolute():
            img_p = REPO_ROOT / img_p

        if not img_p.is_file():
            err_msg = f"Image file not found: {img_p}"
            logger.warning(f"[{mission_id}:{request_id}] {err_msg}")
            return {
                "mission_id": mission_id,
                "request_id": request_id,
                "plant_id": plant_id_val,
                "status": "error",
                "error_type": "not_found",
                "predicted_class": "unknown",
                "confidence": None,
                "class_probabilities": None,
                "severity": None,
                "spray_allowed": False,
                "error": err_msg,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }

        try:
            # Direct prediction using existing inference code (read-only, save_json=False)
            pred = predict_image(
                self.software_cfg,
                img_p,
                model=self.model,
                class_names=self.class_names,
                save_json=False,
                save_annotated=False
            )

            pred_class = pred["predicted_class"]
            conf = float(pred["confidence"])
            probs = {k: float(v) for k, v in pred["class_probabilities"].items()}

            # Run severity estimation
            sev = estimate_leaf_severity(
                img_p,
                predicted_class=pred_class,
                config=self.severity_cfg
            )

            # Decision rule: treatment only when diseased with confidence >= demo_threshold
            spray_allowed = bool(
                pred_class in ["early_blight", "late_blight"] and conf >= self.demo_threshold
            )

            result = {
                "mission_id": mission_id,
                "request_id": request_id,
                "plant_id": plant_id_val,
                "status": "success",
                "predicted_class": pred_class,
                "confidence": conf,
                "class_probabilities": probs,
                "severity": {
                    "status": sev.get("status"),
                    "affected_leaf_area_percent": sev.get("affected_leaf_area_percent"),
                    "band": sev.get("band"),
                    "band_label": sev.get("band_label"),
                    "reliability": sev.get("reliability"),
                    "reasons": sev.get("reasons", [])
                },
                "spray_allowed": spray_allowed,
                "inference_time_ms": pred.get("inference_time_ms"),
                "demo_threshold": self.demo_threshold,
                "error": None,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }
            return result

        except Exception as exc:
            err_msg = f"Inference pipeline exception: {str(exc)}"
            logger.error(f"[{mission_id}:{request_id}] {err_msg}", exc_info=True)
            return {
                "mission_id": mission_id,
                "request_id": request_id,
                "plant_id": plant_id_val,
                "status": "error",
                "error_type": "internal_error",
                "predicted_class": "unknown",
                "confidence": None,
                "class_probabilities": None,
                "severity": None,
                "spray_allowed": False,
                "error": err_msg,
                "timestamp": datetime.now(timezone.utc).isoformat()
            }

    def process_file_ipc_cycle(self) -> int:
        """Process one cycle of file-based IPC requests using atomic rename."""
        req_dir = REPO_ROOT / self.bridge_cfg["transport"]["file_ipc"]["request_dir"]
        resp_dir = REPO_ROOT / self.bridge_cfg["transport"]["file_ipc"]["response_dir"]
        req_dir.mkdir(parents=True, exist_ok=True)
        resp_dir.mkdir(parents=True, exist_ok=True)

        processed = 0
        for req_file in sorted(req_dir.glob("req_*.json")):
            try:
                with open(req_file, "r", encoding="utf-8") as f:
                    req_data = json.load(f)

                mission_id = req_data.get("mission_id", "mission_ipc")
                request_id = req_data.get("request_id", req_file.stem)
                plant_id = req_data.get("plant_id")
                image_path = req_data.get("image_path")

                resp_data = self.predict_single(
                    image_path=image_path,
                    mission_id=mission_id,
                    request_id=request_id,
                    plant_id=plant_id
                )

                # Write atomically: .tmp then rename
                tmp_out = resp_dir / f"resp_{mission_id}_{request_id}.tmp"
                final_out = resp_dir / f"resp_{mission_id}_{request_id}.json"
                with open(tmp_out, "w", encoding="utf-8") as f:
                    json.dump(resp_data, f, indent=2)
                tmp_out.replace(final_out)

                # Remove completed request file
                req_file.unlink(missing_ok=True)
                processed += 1
            except Exception as e:
                logger.error(f"Failed processing IPC file {req_file}: {e}")

        return processed


def create_flask_app(engine: BridgeInferenceEngine):
    from flask import Flask, request, jsonify

    app = Flask(__name__)

    @app.route("/bridge/health", methods=["GET"])
    def health():
        return jsonify({
            "status": "ok",
            "model_loaded": True,
            "classes": engine.class_names,
            "demo_threshold": engine.demo_threshold
        })

    @app.route("/bridge/predict", methods=["POST"])
    def predict():
        data = request.get_json(silent=True) or {}
        image_path = data.get("image_path")
        mission_id = data.get("mission_id")
        request_id = data.get("request_id")
        plant_id = data.get("plant_id")

        if not image_path:
            return jsonify({
                "mission_id": mission_id or "unknown",
                "request_id": request_id or "unknown",
                "plant_id": plant_id or "unknown",
                "status": "error",
                "predicted_class": "unknown",
                "confidence": None,
                "class_probabilities": None,
                "severity": None,
                "spray_allowed": False,
                "error": "Missing 'image_path' parameter in request body."
            }), 400

        result = engine.predict_single(
            image_path=image_path,
            mission_id=mission_id,
            request_id=request_id,
            plant_id=plant_id
        )

        if result.get("status") == "success":
            status_code = 200
        elif result.get("error_type") == "not_found" or "Image file not found" in str(result.get("error", "")):
            status_code = 404
        elif result.get("error_type") == "validation_error":
            status_code = 400
        else:
            status_code = 500

        return jsonify(result), status_code

    @app.route("/bridge/batch_predict", methods=["POST"])
    def batch_predict():
        data = request.get_json(silent=True) or {}
        items = data.get("items", [])
        mission_id = data.get("mission_id", "mission_batch")

        results = []
        for item in items:
            res = engine.predict_single(
                image_path=item.get("image_path"),
                mission_id=mission_id,
                request_id=item.get("request_id"),
                plant_id=item.get("plant_id")
            )
            results.append(res)

        return jsonify({"mission_id": mission_id, "results": results})

    return app


def main():
    parser = argparse.ArgumentParser(description="Integration Bridge Server")
    parser.add_argument("--host", default="127.0.0.1", help="Host interface (localhost only)")
    parser.add_argument("--port", type=int, default=5005, help="Port to listen on")
    parser.add_argument("--config", default=None, help="Path to config.json")
    parser.add_argument("--ipc-once", action="store_true", help="Process IPC queue once and exit")
    args = parser.parse_args()

    cfg_path = Path(args.config) if args.config else (BRIDGE_DIR / "config" / "config.json")
    engine = BridgeInferenceEngine(cfg_path)

    if args.ipc_once:
        count = engine.process_file_ipc_cycle()
        logger.info(f"Processed {count} file IPC requests.")
        return 0

    app = create_flask_app(engine)
    logger.info(f"Starting Integration Bridge REST server on http://{args.host}:{args.port}")
    app.run(host=args.host, port=args.port, threaded=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
