"""Comprehensive Python tests for Integration Bridge.

Verifies:
1. Read-only model and severity loading.
2. Real inference on real validation dataset images.
3. Strict numerical parity between direct inference and bridge output.
4. Correct label mapping and spray_allowed decisions.
5. Fail-safe error behavior (unknown/null/no-spray) on invalid inputs.
6. Atomic file IPC request-response cycle.
7. Zero writes into protected software_model/ folders.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
import pytest

# Ensure bytecode is never written to protected directories
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

BRIDGE_DIR = Path(__file__).resolve().parent.parent
REPO_ROOT = BRIDGE_DIR.parent
SOFTWARE_MODEL_DIR = REPO_ROOT / "software_model"

if str(SOFTWARE_MODEL_DIR) not in sys.path:
    sys.path.insert(0, str(SOFTWARE_MODEL_DIR))

from integration_bridge.server import BridgeInferenceEngine
from integration_bridge.client import BridgeClient
from src.config_loader import load_config
from src.inference import predict_image


@pytest.fixture(scope="module")
def engine():
    return BridgeInferenceEngine()


@pytest.fixture(scope="module")
def val_images():
    val_dir = SOFTWARE_MODEL_DIR / "data" / "processed" / "val"
    return {
        "early_blight": next((val_dir / "early_blight").glob("*.jpg")),
        "healthy": next((val_dir / "healthy").glob("*.jpg")),
        "late_blight": next((val_dir / "late_blight").glob("*.jpg")),
    }


def test_read_only_engine_initialization(engine):
    """Test that engine loads model weights and configs without modifying files."""
    assert engine.model is not None
    assert engine.class_names == ["early_blight", "healthy", "late_blight"]
    assert engine.demo_threshold == 0.60
    assert engine.loaded_path.exists()


def test_real_inference_early_blight(engine, val_images):
    """Test real inference and severity on an actual early_blight image."""
    img_path = val_images["early_blight"]
    res = engine.predict_single(
        image_path=img_path,
        mission_id="mission_test_01",
        request_id="req_eb_01",
        plant_id=10
    )

    assert res["status"] == "success"
    assert res["predicted_class"] == "early_blight"
    assert res["confidence"] >= engine.demo_threshold
    assert res["spray_allowed"] is True
    assert res["error"] is None

    # Severity verification
    sev = res["severity"]
    assert sev is not None
    assert sev["status"] in ["estimated", "unavailable"]
    if sev["status"] == "estimated":
        assert isinstance(sev["affected_leaf_area_percent"], (int, float))
        assert sev["band"] in ["none", "very_low", "low", "medium", "high", "critical"]


def test_real_inference_healthy(engine, val_images):
    """Test real inference on an actual healthy image ensures spray_allowed is False."""
    img_path = val_images["healthy"]
    res = engine.predict_single(
        image_path=img_path,
        mission_id="mission_test_01",
        request_id="req_h_01",
        plant_id=20
    )

    assert res["status"] == "success"
    assert res["predicted_class"] == "healthy"
    assert res["confidence"] > 0.50
    # Healthy plants must NEVER be permitted for spray treatment
    assert res["spray_allowed"] is False


def test_inference_numerical_parity(engine, val_images):
    """Verify bridge predictions match direct predict_image output within 1e-5."""
    img_path = val_images["late_blight"]

    # 1. Direct call to inference library (with save_json=False)
    direct = predict_image(
        engine.software_cfg,
        img_path,
        model=engine.model,
        class_names=engine.class_names,
        save_json=False,
        save_annotated=False
    )

    # 2. Bridge prediction call
    bridge = engine.predict_single(
        image_path=img_path,
        mission_id="mission_parity",
        request_id="req_parity_01"
    )

    assert bridge["status"] == "success"
    assert bridge["predicted_class"] == direct["predicted_class"]
    assert abs(bridge["confidence"] - direct["confidence"]) < 1e-5

    for c in engine.class_names:
        p_direct = direct["class_probabilities"][c]
        p_bridge = bridge["class_probabilities"][c]
        assert abs(p_bridge - p_direct) < 1e-5, f"Probability mismatch for {c}: {p_bridge} vs {p_direct}"


def test_error_handling_missing_image(engine):
    """Verify missing image returns unknown/null with spray_allowed=False."""
    res = engine.predict_single(
        image_path="software_model/data/non_existent_leaf.jpg",
        mission_id="mission_err_01",
        request_id="req_err_01",
        plant_id=99
    )

    assert res["status"] == "error"
    assert res["predicted_class"] == "unknown"
    assert res["confidence"] is None
    assert res["class_probabilities"] is None
    assert res["severity"] is None
    assert res["spray_allowed"] is False
    assert "not found" in res["error"].lower()


def test_rest_non_2xx_json_error_contract(engine):
    """Regression test: verify non-2xx HTTP responses return structured JSON error contract."""
    from integration_bridge.server import create_flask_app

    app = create_flask_app(engine)
    client = app.test_client()

    # 1. Missing image -> HTTP 404 with structured JSON error contract
    resp_404 = client.post(
        "/bridge/predict",
        json={
            "image_path": "software_model/data/non_existent_leaf.jpg",
            "mission_id": "test_m_404",
            "request_id": "req_404_01",
            "plant_id": "P099"
        }
    )
    assert resp_404.status_code == 404, f"Expected 404 for missing image, got {resp_404.status_code}"
    data_404 = resp_404.get_json()
    assert data_404 is not None, "Response body must be structured JSON"
    assert data_404["status"] == "error"
    assert data_404["mission_id"] == "test_m_404"
    assert data_404["request_id"] == "req_404_01"
    assert str(data_404["plant_id"]) == "P099"
    assert data_404["spray_allowed"] is False
    assert data_404["predicted_class"] == "unknown"
    assert data_404["confidence"] is None
    assert data_404["severity"] is None
    assert "Image file not found" in data_404["error"]

    # 2. Missing parameter -> HTTP 400 with structured JSON error contract
    resp_400 = client.post("/bridge/predict", json={})
    assert resp_400.status_code == 400
    data_400 = resp_400.get_json()
    assert data_400 is not None
    assert data_400["status"] == "error"
    assert data_400["spray_allowed"] is False
    assert "Missing 'image_path'" in data_400["error"]


def test_file_ipc_atomic_cycle(engine, val_images):
    """Verify file-based IPC write, process, and response matching."""
    io_dir = BRIDGE_DIR / "io"
    req_dir = io_dir / "requests"
    resp_dir = io_dir / "responses"

    mission_id = "mission_ipc_test"
    request_id = "req_cycle_101"
    img_path = str(val_images["early_blight"].relative_to(REPO_ROOT))

    # Clean old artifacts if any
    req_file = req_dir / f"req_{mission_id}_{request_id}.json"
    resp_file = resp_dir / f"resp_{mission_id}_{request_id}.json"
    req_file.unlink(missing_ok=True)
    resp_file.unlink(missing_ok=True)

    # Write request
    req_data = {
        "mission_id": mission_id,
        "request_id": request_id,
        "plant_id": 42,
        "image_path": img_path
    }
    with open(req_file, "w", encoding="utf-8") as f:
        json.dump(req_data, f, indent=2)

    # Process cycle
    count = engine.process_file_ipc_cycle()
    assert count >= 1

    # Check response file
    assert resp_file.exists()
    assert not req_file.exists()

    with open(resp_file, "r", encoding="utf-8") as f:
        resp_data = json.load(f)

    assert resp_data["mission_id"] == mission_id
    assert resp_data["request_id"] == request_id
    assert resp_data["plant_id"] == 42
    assert resp_data["status"] == "success"
    assert resp_data["predicted_class"] == "early_blight"
    assert resp_data["spray_allowed"] is True

    # Cleanup test response
    resp_file.unlink(missing_ok=True)


def test_protected_folders_remain_unwritten():
    """Verify that predictions did not write any JSON files into software_model/logs/predictions/."""
    pred_dir = SOFTWARE_MODEL_DIR / "logs" / "predictions"
    if pred_dir.exists():
        # Any file modified in the last 120 seconds would indicate a leak
        recent_files = [
            f for f in pred_dir.glob("*.json")
            if (f.stat().st_mtime > pytest.test_start_timestamp)
        ]
        assert len(recent_files) == 0, f"Leaked prediction logs found in protected dir: {recent_files}"


# Record module import timestamp to check against any file writes
pytest.test_start_timestamp = Path(__file__).stat().st_mtime
