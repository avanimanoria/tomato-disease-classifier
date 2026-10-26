"""Integrated Flask Gateway connecting the existing dashboard to the existing MATLAB navigation engine.

Milestone 1: Authoritative MATLAB navigation with synchronized simulation replay.
Milestone 2: Two-pass survey + AI classification + treatment with per-target spray durations.

Zero edits to software_model/ and drone_simu/ (except the approved Stage A patch).
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

from flask import Flask, jsonify, render_template, request
from flask_cors import CORS

# Enforce no bytecode writes in protected directories
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

REPO_ROOT = Path(__file__).resolve().parent.parent
BRIDGE_DIR = REPO_ROOT / "integration_bridge"
IO_DIR = BRIDGE_DIR / "io"
LOGS_DIR = BRIDGE_DIR / "logs"
LOGS_DIR.mkdir(parents=True, exist_ok=True)
IO_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(LOGS_DIR / "gateway.log", encoding="utf-8")
    ]
)
logger = logging.getLogger("dashboard_gateway")

# Configure Flask app: reuse static CSS directly from software_model without copying
app = Flask(
    __name__,
    template_folder=str(BRIDGE_DIR / "templates"),
    static_folder=str(REPO_ROOT / "software_model" / "frontend" / "static")
)
CORS(app)

# ---------------------------------------------------------------------------
# Lazy-load the inference engine once per process (two-pass only)
# ---------------------------------------------------------------------------
_INFERENCE_ENGINE: Any = None
_INFERENCE_ENGINE_LOCK = threading.Lock()


def _get_inference_engine() -> Any:
    """Return the singleton BridgeInferenceEngine, loading it on first call."""
    global _INFERENCE_ENGINE
    with _INFERENCE_ENGINE_LOCK:
        if _INFERENCE_ENGINE is None:
            logger.info("Loading BridgeInferenceEngine for two-pass classification...")
            # Import here to avoid mandatory dependency for navigation-only mode
            bridge_server_dir = BRIDGE_DIR
            if str(bridge_server_dir) not in sys.path:
                sys.path.insert(0, str(bridge_server_dir))

            # Add software_model to sys.path for read-only library imports
            sw_dir = REPO_ROOT / "software_model"
            if str(sw_dir) not in sys.path:
                sys.path.insert(0, str(sw_dir))

            from integration_bridge.server import BridgeInferenceEngine  # type: ignore
            _INFERENCE_ENGINE = BridgeInferenceEngine()
            logger.info("BridgeInferenceEngine loaded successfully.")
    return _INFERENCE_ENGINE


def find_matlab_bin() -> Path:
    """Locate the MATLAB executable on Windows."""
    env_bin = os.environ.get("MATLAB_BIN")
    if env_bin and Path(env_bin).is_file():
        return Path(env_bin)

    which_matlab = shutil.which("matlab")
    if which_matlab and Path(which_matlab).is_file():
        return Path(which_matlab)

    candidates = [
        Path(r"C:\Program Files\MATLAB\R2026b\bin\matlab.exe"),
        Path(r"C:\Program Files\MATLAB\R2025b\bin\matlab.exe"),
        Path(r"C:\Program Files\MATLAB\R2025a\bin\matlab.exe"),
        Path(r"C:\Program Files\MATLAB\R2024b\bin\matlab.exe"),
        Path(r"C:\Program Files\MATLAB\R2024a\bin\matlab.exe"),
    ]
    for c in candidates:
        if c.is_file():
            return c

    raise FileNotFoundError(
        "MATLAB executable not found. Please ensure MATLAB is installed or set MATLAB_BIN."
    )


class MissionManager:
    """Manages MATLAB batch mission runs, replay timekeeping, and state synchronization.

    Supports two modes:
      - navigation_only  : Pass 1 survey only (existing Milestone 1 behavior).
      - two_pass         : Pass 1 survey + Python AI classification + Pass 2 treatment.
    """

    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.status = "Ready"   # Ready | Computing | Running | Completed | Stopped | Failed
        self.mission_id: Optional[str] = None
        self.mission_mode: str = "navigation_only"   # "navigation_only" | "two_pass"
        self.field_length: float = 30.0
        self.field_width: float = 20.0
        self.drone_speed: float = 1.5
        self.matlab_proc: Optional[subprocess.Popen] = None
        self.cancel_requested = False
        self.telemetry_data: Optional[Dict[str, Any]] = None  # navigation_only
        self.timeline_data: Optional[Dict[str, Any]] = None   # two_pass unified timeline
        self.camera_mapping: Optional[Dict[str, Any]] = None
        self.error_message: Optional[str] = None
        self.progress_message: str = ""

        # Replay playback state
        self.playback_start_wall: Optional[float] = None
        self.playback_speed: float = 1.0
        self.current_step_idx: int = 0
        self.is_playing: bool = False

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def start_mission(
        self,
        field_length: float,
        field_width: float,
        drone_speed: float,
        two_pass: bool = False,
        seed: Optional[int] = None,
    ) -> Dict[str, Any]:
        with self.lock:
            if self.status in ["Computing", "Running"]:
                raise RuntimeError(
                    "A mission is already computing or running. Stop it before starting a new one."
                )

            # Validate input parameters against MATLAB uiToConfig limits
            if not (6.0 <= field_length <= 60.0):
                raise ValueError("Field length must be between 6.0 and 60.0 metres.")
            if not (6.0 <= field_width <= 40.0):
                raise ValueError("Field width must be between 6.0 and 40.0 metres.")
            if not (0.5 <= drone_speed <= 2.0):
                raise ValueError("Drone speed must be between 0.5 and 2.0 metres/second.")

            ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
            suffix = int(time.time() * 1000) % 1000
            mission_id = f"mission_{ts}_{suffix:03d}"

            self.mission_id        = mission_id
            self.mission_mode      = "two_pass" if two_pass else "navigation_only"
            self.field_length      = field_length
            self.field_width       = field_width
            self.drone_speed       = drone_speed
            self.status            = "Computing"
            self.cancel_requested  = False
            self.telemetry_data    = None
            self.timeline_data     = None
            self.camera_mapping    = None
            self.error_message     = None
            self.progress_message  = "Starting computation..."
            self.current_step_idx  = 0
            self.is_playing        = False

            # Launch background worker
            if two_pass:
                worker = threading.Thread(
                    target=self._run_two_pass_computation,
                    args=(mission_id, seed),
                    daemon=True
                )
            else:
                worker = threading.Thread(
                    target=self._run_matlab_computation,
                    args=(mission_id,),
                    daemon=True
                )
            worker.start()

            return self.get_status()

    def stop_mission(self) -> Dict[str, Any]:
        with self.lock:
            self.cancel_requested = True
            # Terminate only the process spawned by this gateway
            if self.matlab_proc is not None:
                logger.info(f"Terminating gateway-owned MATLAB PID {self.matlab_proc.pid}")
                try:
                    self.matlab_proc.terminate()
                except Exception as exc:
                    logger.warning(f"Error terminating MATLAB process: {exc}")
                self.matlab_proc = None

            # Write abort signal for two-pass polling loop
            if self.mission_id:
                abort_f = IO_DIR / self.mission_id / "abort.signal"
                try:
                    abort_f.touch()
                except Exception:
                    pass

            self.is_playing = False
            self.status     = "Stopped"
            return {"status": "Stopped"}

    # ------------------------------------------------------------------
    # Navigation-only MATLAB worker (Milestone 1 – preserved unchanged)
    # ------------------------------------------------------------------

    def _run_matlab_computation(self, mission_id: str) -> None:
        mission_dir = IO_DIR / mission_id
        mission_dir.mkdir(parents=True, exist_ok=True)
        config_path = mission_dir / "config.json"
        log_path    = mission_dir / "matlab_stdout.log"

        cfg_payload = {
            "mission_id":   mission_id,
            "field_length": self.field_length,
            "field_width":  self.field_width,
            "drone_speed":  self.drone_speed,
        }
        with open(config_path, "w", encoding="utf-8") as f:
            json.dump(cfg_payload, f, indent=2)

        matlab_bin = find_matlab_bin()
        rel_config = config_path.relative_to(REPO_ROOT).as_posix()
        batch_cmd = (
            f"try, "
            f"addpath(genpath('drone_simu')); "
            f"addpath(genpath('integration_bridge')); "
            f"runHeadlessSurvey('{rel_config}'); "
            f"catch e, fprintf('MATLAB_ERROR: %s\\n', e.message); exit(1); end; exit(0);"
        )

        cmd = [str(matlab_bin), "-batch", batch_cmd]
        logger.info(f"[{mission_id}] Launching navigation-only MATLAB batch: {' '.join(cmd)}")

        t0 = time.time()
        try:
            with open(log_path, "w", encoding="utf-8") as out_f:
                proc = subprocess.Popen(
                    cmd,
                    stdout=out_f,
                    stderr=subprocess.STDOUT,
                    cwd=str(REPO_ROOT),
                    text=True
                )
                with self.lock:
                    self.matlab_proc = proc

                retcode = proc.wait(timeout=120.0)

            duration = time.time() - t0
            logger.info(f"[{mission_id}] MATLAB exited code {retcode} in {duration:.1f}s")

            with self.lock:
                self.matlab_proc = None
                if self.cancel_requested:
                    logger.info(f"[{mission_id}] Cancelled; discarding outputs.")
                    self.status = "Stopped"
                    return

                if retcode != 0:
                    err_text = self._extract_matlab_error(log_path)
                    self.status = "Failed"
                    self.error_message = f"MATLAB execution failed (code {retcode}): {err_text}"
                    logger.error(f"[{mission_id}] {self.error_message}")
                    return

                telemetry_file = mission_dir / "telemetry.json"
                if not telemetry_file.exists():
                    self.status = "Failed"
                    self.error_message = "MATLAB completed but telemetry.json was not generated."
                    logger.error(f"[{mission_id}] {self.error_message}")
                    return

                with open(telemetry_file, "r", encoding="utf-8") as f:
                    self.telemetry_data = json.load(f)

                self.status = "Running"
                self.is_playing = True
                self.current_step_idx = 0
                self.playback_start_wall = time.monotonic()
                logger.info(
                    f"[{mission_id}] Replay initialized: "
                    f"{len(self.telemetry_data.get('telemetry_steps', []))} steps."
                )

        except subprocess.TimeoutExpired:
            logger.error(f"[{mission_id}] MATLAB timed out after 120s")
            with self.lock:
                if self.matlab_proc:
                    try:
                        self.matlab_proc.kill()
                    except Exception:
                        pass
                    self.matlab_proc = None
                self.status = "Failed"
                self.error_message = "MATLAB computation timed out after 120s."

        except Exception as exc:
            logger.exception(f"[{mission_id}] Exception during MATLAB launch: {exc}")
            with self.lock:
                self.status = "Failed"
                self.error_message = f"Gateway exception: {str(exc)}"

    # ------------------------------------------------------------------
    # Two-pass worker: MATLAB survey → Python classify → MATLAB treat
    # ------------------------------------------------------------------

    def _run_two_pass_computation(self, mission_id: str, seed: Optional[int]) -> None:
        """Background thread: runs full two-pass computation, then starts replay."""
        mission_dir = IO_DIR / mission_id
        mission_dir.mkdir(parents=True, exist_ok=True)
        config_path = mission_dir / "config.json"
        log_path    = mission_dir / "matlab_stdout.log"

        def _set_progress(msg: str) -> None:
            with self.lock:
                self.progress_message = msg
            logger.info(f"[{mission_id}] {msg}")

        def _abort_requested() -> bool:
            with self.lock:
                return self.cancel_requested

        try:
            # --- Step 1: Generate camera mapping before MATLAB starts -------
            _set_progress("Generating camera input mapping (75/10/10/5)...")
            from integration_bridge.camera_mapping import generate_mission_camera_mapping  # type: ignore

            # We need plant IDs from MATLAB first; camera mapping is keyed by plant ID.
            # Strategy: run MATLAB survey first, read survey_data.json for plant IDs,
            # then generate mapping. MATLAB polls treatment_targets.json, so it will
            # wait safely while we classify.

            # --- Step 2: Write MATLAB config --------------------------------
            cfg_payload = {
                "mission_id":   mission_id,
                "field_length": self.field_length,
                "field_width":  self.field_width,
                "drone_speed":  self.drone_speed,
            }
            with open(config_path, "w", encoding="utf-8") as f:
                json.dump(cfg_payload, f, indent=2)

            # --- Step 3: Launch MATLAB runHeadlessTwoPass -------------------
            matlab_bin = find_matlab_bin()
            rel_config = config_path.relative_to(REPO_ROOT).as_posix()
            batch_cmd = (
                f"try, "
                f"addpath(genpath('drone_simu')); "
                f"addpath(genpath('integration_bridge')); "
                f"runHeadlessTwoPass('{rel_config}'); "
                f"catch e, fprintf('MATLAB_ERROR: %s\\n', e.message); exit(1); end; exit(0);"
            )
            cmd = [str(matlab_bin), "-batch", batch_cmd]
            logger.info(f"[{mission_id}] Launching two-pass MATLAB: {' '.join(cmd)}")

            _set_progress("Running MATLAB survey pass (Pass 1)...")
            with open(log_path, "w", encoding="utf-8") as out_f:
                proc = subprocess.Popen(
                    cmd,
                    stdout=out_f,
                    stderr=subprocess.STDOUT,
                    cwd=str(REPO_ROOT),
                    text=True
                )
                with self.lock:
                    self.matlab_proc = proc

            # --- Step 4: Wait for survey_data.json, then classify -----------
            _set_progress("Waiting for MATLAB survey output...")
            from integration_bridge.two_pass_orchestrator import (  # type: ignore
                run_two_pass_classification,
                wait_for_file,
            )

            survey_file = mission_dir / "survey_data.json"
            wait_for_file(survey_file, max_wait_s=300, abort_check=_abort_requested)

            if _abort_requested():
                with self.lock:
                    self.status = "Stopped"
                return

            # Read plant IDs from survey data
            with survey_file.open("r", encoding="utf-8") as f:
                survey_peek = json.load(f)
            plant_ids = [p["plant_id"] for p in survey_peek["plants"]]
            logger.info(f"[{mission_id}] {len(plant_ids)} plants in field.")

            # Generate camera mapping with actual plant IDs
            _set_progress(f"Generating camera mapping for {len(plant_ids)} plants...")
            mapping_path = mission_dir / "plant_image_mapping.json"
            cam_mapping = generate_mission_camera_mapping(
                plant_ids=plant_ids,
                seed=seed,
                output_path=mapping_path,
            )
            with self.lock:
                self.camera_mapping = cam_mapping

            props = cam_mapping["proportions"]["actual_counts"]
            _set_progress(
                f"Camera mapping ready (seed={cam_mapping['seed']}): "
                f"H={props['healthy']} EB={props['early_blight']} "
                f"LB={props['late_blight']} fault={props['camera_unavailable']}"
            )

            # Run Python classification + write treatment_targets.json + wait for treatment
            engine = _get_inference_engine()
            _set_progress("Classifying observed plants (Pass 1 AI)...")
            timeline = run_two_pass_classification(
                mission_id=mission_id,
                mission_dir=mission_dir,
                inference_engine=engine,
                camera_mapping=cam_mapping,
                progress_cb=_set_progress,
                abort_check=_abort_requested,
            )

            # --- Step 5: Wait for MATLAB process to finish ------------------
            _set_progress("Waiting for MATLAB treatment pass to complete...")
            t0 = time.time()
            try:
                retcode = proc.wait(timeout=900.0)   # 15-min max for two-pass
            except subprocess.TimeoutExpired:
                try:
                    proc.kill()
                except Exception:
                    pass
                with self.lock:
                    self.matlab_proc = None
                    self.status = "Failed"
                    self.error_message = "Two-pass MATLAB timed out after 900s."
                return

            duration = time.time() - t0
            logger.info(
                f"[{mission_id}] Two-pass MATLAB exited code {retcode} in {duration:.1f}s"
            )

            with self.lock:
                self.matlab_proc = None

            if _abort_requested():
                with self.lock:
                    self.status = "Stopped"
                return

            if retcode != 0:
                err_text = self._extract_matlab_error(log_path)
                with self.lock:
                    self.status = "Failed"
                    self.error_message = (
                        f"Two-pass MATLAB failed (code {retcode}): {err_text}"
                    )
                logger.error(f"[{mission_id}] {self.error_message}")
                return

            # --- Step 6: Save timeline and start replay ---------------------
            timeline_file = mission_dir / "two_pass_timeline.json"
            with timeline_file.open("w", encoding="utf-8") as f:
                json.dump(timeline, f, indent=2)

            all_steps = timeline.get("survey_steps", []) + timeline.get("treatment_steps", [])
            logger.info(
                f"[{mission_id}] Two-pass complete: "
                f"{len(all_steps)} total replay steps, "
                f"{timeline['summary']['n_treatment_targets']} treatment targets."
            )

            with self.lock:
                self.timeline_data    = timeline
                self.status           = "Running"
                self.is_playing       = True
                self.current_step_idx = 0
                self.playback_start_wall = time.monotonic()
                self.progress_message = "Replay started."

        except InterruptedError:
            with self.lock:
                self.status = "Stopped"
                self.progress_message = "Mission stopped by user."

        except Exception as exc:
            logger.exception(f"[{mission_id}] Two-pass exception: {exc}")
            with self.lock:
                # Write abort to unblock MATLAB if it's still polling
                try:
                    (IO_DIR / mission_id / "abort.signal").touch()
                except Exception:
                    pass
                if self.matlab_proc:
                    try:
                        self.matlab_proc.terminate()
                    except Exception:
                        pass
                    self.matlab_proc = None
                self.status = "Failed"
                self.error_message = f"Two-pass computation error: {str(exc)}"

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _extract_matlab_error(log_path: Path) -> str:
        if log_path.exists():
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                lines = [ln.strip() for ln in f if "MATLAB_ERROR" in ln]
            if lines:
                return lines[-1]
        return "Unknown MATLAB error"

    def _all_steps(self) -> list:
        """Return unified step list for the active mission mode."""
        if self.mission_mode == "two_pass" and self.timeline_data:
            return (
                self.timeline_data.get("survey_steps", [])
                + self.timeline_data.get("treatment_steps", [])
            )
        if self.telemetry_data:
            return self.telemetry_data.get("telemetry_steps", [])
        return []

    def _sync_playback(self) -> None:
        """Advance replay cursor based on elapsed wall-clock time."""
        if not self.is_playing:
            return
        steps = self._all_steps()
        if not steps:
            self.status = "Completed"
            self.is_playing = False
            return

        elapsed = time.monotonic() - self.playback_start_wall
        idx = self.current_step_idx
        while idx < len(steps) - 1 and steps[idx]["t"] <= elapsed:
            idx += 1
        self.current_step_idx = idx
        if idx >= len(steps) - 1 and elapsed >= steps[-1]["t"]:
            self.status = "Completed"
            self.is_playing = False

    # ------------------------------------------------------------------
    # Status / telemetry / field map APIs
    # ------------------------------------------------------------------

    def get_status(self) -> Dict[str, Any]:
        with self.lock:
            self._sync_playback()
            area = self.field_length * self.field_width
            progress = 0.0
            elapsed_sec = 0.0

            steps = self._all_steps()
            if steps:
                total_steps = len(steps)
                progress    = round((self.current_step_idx + 1) / total_steps * 100.0, 1)
                elapsed_sec = steps[min(self.current_step_idx, total_steps - 1)]["t"]

            # Two-pass summary stats
            summary: Dict[str, Any] = {}
            if self.mission_mode == "two_pass" and self.timeline_data:
                summary = self.timeline_data.get("summary", {})

            return {
                "status":              self.status,
                "mode_label":          "MATLAB simulation replay",
                "mission_mode":        self.mission_mode,
                "mission_id":          self.mission_id,
                "progress_message":    self.progress_message,
                "field_dimensions":    {"length": self.field_length, "width": self.field_width},
                "total_area_m2":       round(area, 2),
                "covered_area_m2":     round(area * (progress / 100.0), 2),
                "mission_progress":    progress,
                # Navigation-only stub values for Milestone 1 compatibility
                "disease_detected_percent":  summary.get("n_disease_positive", 0),
                "spray_used_ml":             summary.get("total_emitted_volume_mL", 0.0),
                "plants_treated":            summary.get("n_treatment_targets", 0),
                "n_healthy":                 summary.get("n_healthy", 0),
                "n_error":                   summary.get("n_error", 0),
                "elapsed_seconds":           round(elapsed_sec, 1),
                "error":                     self.error_message,
            }

    def get_telemetry(self) -> Dict[str, Any]:
        with self.lock:
            self._sync_playback()
            steps = self._all_steps()
            if not steps:
                return {
                    "status":         self.status,
                    "position":       {"x": 0.0, "y": 0.0},
                    "heading":        90.0,
                    "speed":          0.0,
                    "altitude":       0.0,
                    "battery":        100.0,
                    "cross_track_m":  0.0,
                    "cum_distance_m": 0.0,
                    "step":           0,
                    "total_steps":    0,
                    "pass":           1,
                    "leg_kind":       None,
                    "target_id":      None,
                }

            step = steps[min(self.current_step_idx, len(steps) - 1)]
            battery = max(0.0, round(100.0 - step["t"] * 0.05, 1))
            is_treatment = step.get("leg_kind") in ("treatment", "refill")

            return {
                "status":          self.status,
                "position":        {"x": step["x"], "y": step["y"]},
                "heading":         step["heading"],
                "speed":           step.get("speed", 0.0) if self.status in ["Running", "Completed"] else 0.0,
                "altitude":        2.0,
                "battery":         battery,
                "cross_track_m":   step.get("cross_track_m", 0.0),
                "cum_distance_m":  step.get("cum_distance_m", 0.0),
                "step":            step["step"],
                "total_steps":     len(steps),
                "pass":            2 if is_treatment else 1,
                "leg_kind":        step.get("leg_kind"),
                "target_id":       step.get("target_id"),
                "phase":           step.get("phase"),
                "timestamp":       datetime.now(timezone.utc).isoformat(),
            }

    def get_field_map(self) -> Dict[str, Any]:
        with self.lock:
            self._sync_playback()

            # Navigation-only fallback
            if self.mission_mode == "navigation_only":
                if not self.telemetry_data:
                    return self._empty_field_map()
                steps = self.telemetry_data.get("telemetry_steps", [])
                curr_idx = min(self.current_step_idx, len(steps) - 1)
                trajectory = [[s["x"], s["y"]] for s in steps[:curr_idx + 1]]
                return {
                    "field_dimensions":   self.telemetry_data.get("field_dimensions", {}),
                    "field_polygon":      self.telemetry_data.get("field_polygon", []),
                    "num_rows":           self.telemetry_data.get("num_rows", 0),
                    "total_plants":       self.telemetry_data.get("total_plants", 0),
                    "survey_path_length": self.telemetry_data.get("survey_path_length", 0.0),
                    "plants":             self.telemetry_data.get("plants", []),
                    "reference_path":     self.telemetry_data.get("reference_path", []),
                    "trajectory":         trajectory,
                    "grid_size":          {"rows": self.telemetry_data.get("num_rows", 10), "cols": 10},
                    "cells":              [],
                }

            # Two-pass
            if not self.timeline_data:
                return self._empty_field_map()

            all_steps = (
                self.timeline_data.get("survey_steps", [])
                + self.timeline_data.get("treatment_steps", [])
            )
            curr_idx   = min(self.current_step_idx, len(all_steps) - 1)
            trajectory = [[s["x"], s["y"]] for s in all_steps[:curr_idx + 1]]

            # Current replay time
            curr_t = all_steps[curr_idx]["t"] if all_steps else 0.0

            # Enrich plants with observation/classification state revealed so far
            plants_raw  = self.timeline_data.get("plants", [])
            cls_results = self.timeline_data.get("classification_results", {})
            decisions   = self.timeline_data.get("treatment_decisions", {})
            assessments = self.timeline_data.get("target_assessment_events", {})

            plants_enriched = []
            for pl in plants_raw:
                pid   = pl["plant_id"]
                cr    = cls_results.get(pid, {})
                dec   = decisions.get(pid, {})
                obs_t = pl.get("obs_timestamp")

                # Determine revelation state
                p_out = dict(pl)
                if not pl["seen"] or obs_t is None or curr_t < obs_t:
                    # Not yet revealed
                    p_out["display_state"]  = "unobserved"
                    p_out["predicted_class"] = None
                    p_out["confidence"]      = None
                    p_out["severity_band"]   = None
                    p_out["spray_blocked"]   = None
                elif cr.get("status") == "error" or cr.get("is_injected_fault"):
                    p_out["display_state"]  = "error"
                    p_out["predicted_class"] = None
                    p_out["confidence"]      = None
                    p_out["severity_band"]   = None
                    p_out["spray_blocked"]   = True
                else:
                    pred_class = cr.get("predicted_class")
                    conf       = cr.get("confidence", 0.0)
                    spray_ok   = cr.get("spray_allowed", False)

                    if pred_class == "healthy":
                        p_out["display_state"] = "healthy"
                    elif pred_class in ("early_blight", "late_blight") and spray_ok:
                        p_out["display_state"] = "disease_positive"
                    elif conf is not None and conf < 0.60:
                        p_out["display_state"] = "low_confidence"
                    else:
                        p_out["display_state"] = "observed"

                    p_out["predicted_class"] = pred_class
                    p_out["confidence"]      = conf
                    p_out["spray_blocked"]   = dec.get("spray_blocked")

                    # Reveal severity only at Pass 2 assessment event
                    asmt = assessments.get(pid, {})
                    asmt_t = asmt.get("assessment_timestamp")
                    if asmt_t is not None and curr_t >= asmt_t:
                        p_out["severity_band"] = asmt.get("severity_band")
                        p_out["executed_duration_s"] = asmt.get("executed_duration_s")
                        p_out["emitted_volume_mL"]   = asmt.get("emitted_volume_mL")
                    else:
                        p_out["severity_band"] = None

                plants_enriched.append(p_out)

            return {
                "field_dimensions":   self.timeline_data["field"]["dimensions"],
                "field_polygon":      self.timeline_data["field"]["polygon"],
                "num_rows":           self.timeline_data["field"]["num_rows"],
                "total_plants":       self.timeline_data["field"]["total_plants"],
                "survey_path_length": self.timeline_data["field"]["survey_path_length"],
                "plants":             plants_enriched,
                "reference_path":     self.timeline_data.get("reference_path", []),
                "trajectory":         trajectory,
                "classification_results": cls_results,
                "treatment_decisions":    decisions,
                "target_assessment_events": assessments,
                "grid_size":          {"rows": self.timeline_data["field"]["num_rows"], "cols": 10},
                "cells":              [],
                "disclosure":         self.timeline_data.get("disclosure", ""),
                "summary":            self.timeline_data.get("summary", {}),
            }

    def _empty_field_map(self) -> Dict[str, Any]:
        return {
            "field_dimensions":   {"length": self.field_length, "width": self.field_width},
            "field_polygon":      [
                [0, 0], [self.field_length, 0],
                [self.field_length, self.field_width], [0, self.field_width]
            ],
            "plants":             [],
            "reference_path":     [],
            "trajectory":         [],
            "grid_size":          {"rows": 10, "cols": 10},
            "cells":              [],
        }


# ---------------------------------------------------------------------------
# Flask application singleton
# ---------------------------------------------------------------------------
manager = MissionManager()


@app.get("/")
def index() -> str:
    return render_template("index.html")


@app.post("/api/mission/start")
def start_mission() -> Any:
    payload = request.get_json(silent=True) or {}
    try:
        fl        = float(payload.get("field_length", 30.0))
        fw        = float(payload.get("field_width", 20.0))
        ds        = float(payload.get("drone_speed", 1.5))
        two_pass  = bool(payload.get("two_pass", False))
        seed_raw  = payload.get("seed")
        seed      = int(seed_raw) if seed_raw is not None else None
        status    = manager.start_mission(fl, fw, ds, two_pass=two_pass, seed=seed)
        return jsonify(status), 201
    except RuntimeError as rerr:
        return jsonify({"error": str(rerr)}), 409
    except (ValueError, TypeError) as verr:
        return jsonify({"error": str(verr)}), 400


@app.post("/api/mission/stop")
def stop_mission() -> Any:
    return jsonify(manager.stop_mission())


@app.get("/api/mission/status")
def mission_status() -> Any:
    return jsonify(manager.get_status())


@app.get("/api/drone/telemetry")
def drone_telemetry() -> Any:
    return jsonify(manager.get_telemetry())


@app.get("/api/field/disease_map")
def field_disease_map() -> Any:
    return jsonify(manager.get_field_map())


@app.get("/api/spray/log")
def spray_log() -> Any:
    with manager.lock:
        if manager.mission_mode != "two_pass" or not manager.timeline_data:
            return jsonify([])
        assessments = manager.timeline_data.get("target_assessment_events", {})
        log = []
        for tid, ev in assessments.items():
            log.append({
                "target_id":           tid,
                "assessment_timestamp": ev.get("assessment_timestamp"),
                "severity_band":       ev.get("severity_band"),
                "executed_duration_s": ev.get("executed_duration_s"),
                "emitted_volume_mL":   ev.get("emitted_volume_mL"),
                "recheck_passed":      ev.get("recheck_passed"),
            })
        return jsonify(log)


@app.post("/api/predict")
def predict_leaf() -> Any:
    """Manual classifier endpoint — inactive for navigation milestone.
    Two-pass missions use the /bridge/predict endpoint on port 5005.
    """
    return jsonify({
        "status":  "unavailable",
        "message": (
            "Manual image classification is not available via this endpoint. "
            "Two-pass missions use the pre-loaded model via the bridge server (port 5005)."
        ),
    }), 503


def main():
    parser = argparse.ArgumentParser(description="MATLAB-Connected Dashboard Gateway")
    parser.add_argument("--host", default="127.0.0.1", help="Host to bind (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=5000, help="Port to bind (default: 5000)")
    args = parser.parse_args()

    logger.info(f"Starting MATLAB Dashboard Gateway on http://{args.host}:{args.port}")
    app.run(host=args.host, port=args.port, debug=False, threaded=True)


if __name__ == "__main__":
    main()
