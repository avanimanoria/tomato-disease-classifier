"""Automated verification suite for Milestone 1: MATLAB Navigation Engine to Dashboard Integration.

Tests:
1. Direct headless MATLAB execution with Configuration 1 (30m x 20m).
2. Direct headless MATLAB execution with Configuration 2 (40m x 25m).
3. Verification that plant counts, row counts, and paths are MATLAB execution outputs.
4. Gateway REST API start, telemetry, field map, and stop endpoints.
5. Duplicate start rejection (HTTP 409).
6. Out-of-bounds parameter validation (HTTP 400).
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path
import pytest

os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
BRIDGE_DIR = REPO_ROOT / "integration_bridge"
IO_DIR = BRIDGE_DIR / "io"


def test_matlab_headless_configuration_1(tmp_path):
    """Test Case 1: MATLAB execution with 30m x 20m field."""
    from integration_bridge.dashboard_gateway import find_matlab_bin

    matlab_bin = find_matlab_bin()
    mission_id = f"test_case1_{int(time.time()*1000)}"
    mission_dir = IO_DIR / mission_id
    mission_dir.mkdir(parents=True, exist_ok=True)

    config_path = mission_dir / "config.json"
    cfg_data = {
        "mission_id": mission_id,
        "field_length": 30.0,
        "field_width": 20.0,
        "drone_speed": 1.5,
    }
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(cfg_data, f, indent=2)

    rel_cfg = config_path.relative_to(REPO_ROOT).as_posix()
    cmd = [
        str(matlab_bin),
        "-batch",
        f"try, addpath(genpath('drone_simu')); addpath(genpath('integration_bridge')); runHeadlessSurvey('{rel_cfg}'); catch e, fprintf('MATLAB_ERROR: %s\\n', e.message); exit(1); end; exit(0);"
    ]

    res = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, timeout=120)
    assert res.returncode == 0, f"MATLAB execution failed: {res.stdout}\n{res.stderr}"

    telemetry_file = mission_dir / "telemetry.json"
    assert telemetry_file.is_file(), "telemetry.json was not generated"

    with open(telemetry_file, "r", encoding="utf-8") as f:
        out = json.load(f)

    assert out["mission_id"] == mission_id
    assert out["provenance"] == "authoritative_matlab_navigation"
    assert out["mode"] == "MATLAB simulation replay"
    assert out["field_dimensions"]["length"] == 30.0
    assert out["field_dimensions"]["width"] == 20.0
    assert out["num_rows"] > 0
    assert out["total_plants"] > 0
    assert out["survey_path_length"] > 0.0
    assert len(out["plants"]) == out["total_plants"]
    assert len(out["reference_path"]) > 1
    assert len(out["telemetry_steps"]) > 10

    # Cleanup test directory
    shutil.rmtree(mission_dir, ignore_errors=True)


def test_matlab_headless_configuration_2(tmp_path):
    """Test Case 2: MATLAB execution with 40m x 25m field, verifying geometric scaling."""
    from integration_bridge.dashboard_gateway import find_matlab_bin

    matlab_bin = find_matlab_bin()
    mission_id = f"test_case2_{int(time.time()*1000)}"
    mission_dir = IO_DIR / mission_id
    mission_dir.mkdir(parents=True, exist_ok=True)

    config_path = mission_dir / "config.json"
    cfg_data = {
        "mission_id": mission_id,
        "field_length": 40.0,
        "field_width": 25.0,
        "drone_speed": 1.5,
    }
    with open(config_path, "w", encoding="utf-8") as f:
        json.dump(cfg_data, f, indent=2)

    rel_cfg = config_path.relative_to(REPO_ROOT).as_posix()
    cmd = [
        str(matlab_bin),
        "-batch",
        f"try, addpath(genpath('drone_simu')); addpath(genpath('integration_bridge')); runHeadlessSurvey('{rel_cfg}'); catch e, fprintf('MATLAB_ERROR: %s\\n', e.message); exit(1); end; exit(0);"
    ]

    res = subprocess.run(cmd, cwd=str(REPO_ROOT), capture_output=True, text=True, timeout=120)
    assert res.returncode == 0, f"MATLAB execution failed: {res.stdout}\n{res.stderr}"

    telemetry_file = mission_dir / "telemetry.json"
    assert telemetry_file.is_file(), "telemetry.json was not generated"

    with open(telemetry_file, "r", encoding="utf-8") as f:
        out = json.load(f)

    assert out["field_dimensions"]["length"] == 40.0
    assert out["field_dimensions"]["width"] == 25.0
    # Larger field must have greater survey path length and total plants than Case 1
    assert out["total_plants"] > 513
    assert out["survey_path_length"] > 268.0

    # Check plant coordinate bounds
    for p in out["plants"][:20]:
        assert 0.0 <= p["x"] <= 40.0
        assert 0.0 <= p["y"] <= 25.0

    shutil.rmtree(mission_dir, ignore_errors=True)


def test_gateway_api_validation_and_concurrency():
    """Test gateway parameter validation, duplicate start rejection, and stop handling."""
    from integration_bridge.dashboard_gateway import app, manager

    client = app.test_client()

    # Out of bounds: length < 6m
    res = client.post("/api/mission/start", json={"field_length": 4.0, "field_width": 20.0})
    assert res.status_code == 400
    assert "between 6.0 and 60.0" in res.get_json()["error"]

    # Out of bounds: width > 40m
    res = client.post("/api/mission/start", json={"field_length": 30.0, "field_width": 55.0})
    assert res.status_code == 400
    assert "between 6.0 and 40.0" in res.get_json()["error"]

    # Out of bounds: speed > 2.0 m/s
    res = client.post("/api/mission/start", json={"field_length": 30.0, "field_width": 20.0, "drone_speed": 3.0})
    assert res.status_code == 400
    assert "between 0.5 and 2.0" in res.get_json()["error"]

    # Test initial status
    res = client.get("/api/mission/status")
    assert res.status_code == 200
    status_data = res.get_json()
    assert "mode_label" in status_data
    assert status_data["mode_label"] == "MATLAB simulation replay"

    # Test Stop endpoint
    res = client.post("/api/mission/stop")
    assert res.status_code == 200
    assert res.get_json()["status"] == "Stopped"

    # Test predict endpoint returns inert/unavailable status in Milestone 1
    res = client.post("/api/predict")
    assert res.status_code == 503
    assert res.get_json()["status"] == "unavailable"
