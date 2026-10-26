"""Two-pass mission orchestrator (Python side).

Handles all Python logic between MATLAB survey and treatment passes:
 1. Reads survey_data.json produced by runHeadlessTwoPass.
 2. Classifies every observed plant using the pre-loaded BridgeInferenceEngine.
 3. Applies explicit disease recheck + simulation-only severity-to-duration policy.
 4. Writes treatment_targets.json to unblock the MATLAB treatment pass.
 5. Reads treatment_data.json produced by runHeadlessTwoPass.
 6. Returns a unified timeline dict for replay and SSE streaming.

All changes confined to integration_bridge/.
No edits to drone_simu/ or software_model/.
"""
from __future__ import annotations

import json
import logging
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger("two_pass_orchestrator")

REPO_ROOT = Path(__file__).resolve().parent.parent

# Simulation-only severity-to-duration policy.
# dt = 0.1 s (from MATLAB config.m).
DT = 0.1

BAND_TO_RAW_DURATION: Dict[Optional[str], float] = {
    None:        0.0,   # unavailable / missing severity
    "none":      0.0,   # no disease visible
    "very_low":  1.0,
    "low":       2.0,
    "medium":    3.0,
    "high":      4.0,
    "critical":  0.0,   # blocked: requires manual review
}

DISEASE_CLASSES = {"early_blight", "late_blight"}
CONF_THRESHOLD  = 0.60


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _quantize(d: float) -> float:
    """Round to nearest MATLAB timestep (dt = 0.1 s)."""
    return round(round(d / DT) * DT, 10)


def _write_json_atomic(path: Path, obj: Any) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)
    tmp.replace(path)


def _read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def wait_for_file(
    path: Path,
    max_wait_s: float = 300.0,
    poll_s: float = 0.5,
    abort_check: Optional[Callable[[], bool]] = None,
) -> None:
    """Block until *path* exists or timeout / abort fires."""
    elapsed = 0.0
    while not path.is_file():
        time.sleep(poll_s)
        elapsed += poll_s
        if elapsed >= max_wait_s:
            raise TimeoutError(f"Timed out waiting for {path} after {max_wait_s:.0f}s")
        if abort_check and abort_check():
            raise InterruptedError("Mission aborted by caller")


# ---------------------------------------------------------------------------
# Treatment policy
# ---------------------------------------------------------------------------

def apply_treatment_policy(
    pred_result: Dict[str, Any],
    is_injected_fault: bool,
) -> Dict[str, Any]:
    """Determine whether to spray a plant and for how long.

    Applies in strict gate order:
      Gate 1 – Injected camera fault          → block
      Gate 2 – Inference status != 'success'  → block
      Gate 3 – Explicit disease recheck       → block if not disease + conf + spray_allowed
      Gate 4 – Severity unavailable           → block
      Gate 5 – Duration policy by band        → compute or block
      Gate 6 – Zero quantized duration        → block

    Simulation policy:  one configured flow rate (25 mL/s).
    Discloses that Pass 2 reuses the Pass 1 assigned image.
    """
    REUSE_MSG = (
        "Pass 2 reuses Pass 1 assigned image (no physical camera capture). "
        "Severity is precomputed and revealed at treatment-leg arrival during replay."
    )
    plant_id = pred_result.get("plant_id", "unknown")

    def _blocked(reason: str, *, band: Optional[str] = None,
                 pct: Optional[float] = None, recheck: bool = False) -> Dict[str, Any]:
        return dict(plant_id=plant_id, spray_blocked=True, block_reason=reason,
                    duration_s=0.0, executed_duration_s=0.0,
                    severity_band=band, affected_pct=pct,
                    recheck_passed=recheck, image_reuse_disclosure=REUSE_MSG)

    # Gate 1 – injected fault
    if is_injected_fault:
        return _blocked("injected_camera_fault")

    # Gate 2 – inference error
    if pred_result.get("status") != "success":
        return _blocked(f"inference_error:{pred_result.get('error_type', 'unknown')}")

    # Gate 3 – explicit disease recheck
    pred_class  = pred_result.get("predicted_class", "unknown")
    confidence  = float(pred_result.get("confidence") or 0.0)
    spray_ok    = pred_result.get("spray_allowed", False)
    recheck_ok  = (pred_class in DISEASE_CLASSES and confidence >= CONF_THRESHOLD and spray_ok)

    if not recheck_ok:
        return _blocked(
            f"recheck_failed:class={pred_class},conf={confidence:.3f}",
            recheck=False
        )

    # Gate 4 – severity
    sev        = pred_result.get("severity") or {}
    sev_status = sev.get("status", "unavailable")
    band       = sev.get("band")
    pct        = sev.get("affected_leaf_area_percent")

    if sev_status != "estimated" or band is None:
        return _blocked("severity_unavailable", recheck=True)

    # Gate 5 – duration policy
    if band == "critical":
        return _blocked("critical_manual_review", band=band, pct=pct, recheck=True)

    raw_dur  = BAND_TO_RAW_DURATION.get(band, 0.0)
    q_dur    = _quantize(raw_dur)

    if q_dur == 0.0:
        return _blocked(f"zero_duration:band={band}", band=band, pct=pct, recheck=True)

    return dict(
        plant_id=plant_id,
        spray_blocked=False,
        block_reason=None,
        duration_s=q_dur,
        executed_duration_s=q_dur,      # updated with MATLAB-reported value after treatment
        severity_band=band,
        affected_pct=pct,
        recheck_passed=True,
        image_reuse_disclosure=REUSE_MSG,
    )


# ---------------------------------------------------------------------------
# Main orchestration entry point
# ---------------------------------------------------------------------------

def run_two_pass_classification(
    mission_id: str,
    mission_dir: Path,
    inference_engine: Any,
    camera_mapping: Dict[str, Any],
    progress_cb: Optional[Callable[[str], None]] = None,
    abort_check: Optional[Callable[[], bool]] = None,
) -> Dict[str, Any]:
    """Run Python-side two-pass orchestration.

    Args:
        mission_id:       Unique mission identifier.
        mission_dir:      Path to io/mission_<id>/ directory.
        inference_engine: BridgeInferenceEngine instance (model loaded once per process).
        camera_mapping:   Output of camera_mapping.generate_mission_camera_mapping().
        progress_cb:      Optional callable(str) for progress messages.
        abort_check:      Optional callable() -> bool; raises InterruptedError if True.

    Returns:
        Unified timeline dict ready for replay and SSE streaming.
    """
    def _p(msg: str) -> None:
        logger.info("[%s] %s", mission_id, msg)
        if progress_cb:
            progress_cb(msg)

    mapping: Dict[str, Any] = camera_mapping["mapping"]

    # ------------------------------------------------------------------ #
    # Step 1 – Wait for MATLAB survey_data.json                           #
    # ------------------------------------------------------------------ #
    survey_file = mission_dir / "survey_data.json"
    _p("Waiting for MATLAB survey_data.json...")
    wait_for_file(survey_file, max_wait_s=300, abort_check=abort_check)
    survey = _read_json(survey_file)
    plants = survey["plants"]
    _p(f"Survey received: {survey['total_plants']} plants, "
       f"{len(survey['telemetry_steps'])} trajectory steps")

    # ------------------------------------------------------------------ #
    # Step 2 – Classify every observed plant                              #
    # ------------------------------------------------------------------ #
    _p("Classifying observed plants using pre-loaded model...")
    classification_results: Dict[str, Any] = {}

    for plant in plants:
        pid = plant["plant_id"]

        if not plant["seen"]:
            classification_results[pid] = {
                "plant_id": pid, "status": "not_observed",
                "obs_timestamp": None, "is_injected_fault": False,
                "spray_allowed": False,
            }
            continue

        plant_map = mapping.get(pid)
        if plant_map is None:
            classification_results[pid] = {
                "plant_id": pid, "status": "error",
                "error_type": "mapping_missing",
                "spray_allowed": False, "is_injected_fault": False,
                "obs_timestamp": plant["obs_timestamp"],
            }
            continue

        if plant_map["is_injected_fault"]:
            # Intentional camera fault – file does not exist on disk (correct behavior)
            classification_results[pid] = {
                "plant_id":         pid,
                "status":           "error",
                "error_type":       "camera_unavailable",
                "spray_allowed":    False,
                "is_injected_fault": True,
                "image_path":       plant_map["image_path"],
                "image_name":       plant_map["image_name"],
                "obs_timestamp":    plant["obs_timestamp"],
                "predicted_class":  None,
                "confidence":       None,
                "severity":         None,
            }
            continue

        # Real image – run inference
        result = inference_engine.predict_single(
            image_path=plant_map["image_path"],
            mission_id=mission_id,
            request_id=f"p1_{pid}",
            plant_id=pid,
        )
        result["is_injected_fault"] = False
        result["obs_timestamp"]     = plant["obs_timestamp"]
        result["image_path"]        = plant_map["image_path"]
        result["image_name"]        = plant_map["image_name"]
        classification_results[pid] = result

    # Tally outcomes
    n_observed   = sum(1 for p in plants if p["seen"])
    n_healthy    = sum(1 for r in classification_results.values()
                       if r.get("predicted_class") == "healthy")
    n_disease    = sum(1 for r in classification_results.values()
                       if r.get("predicted_class") in DISEASE_CLASSES
                       and r.get("spray_allowed"))
    n_error      = sum(1 for r in classification_results.values()
                       if r.get("status") == "error" or r.get("is_injected_fault"))
    n_unobserved = sum(1 for r in classification_results.values()
                       if r.get("status") == "not_observed")
    _p(f"Classification done: {n_healthy} healthy, {n_disease} disease-positive, "
       f"{n_error} error/fault, {n_unobserved} unobserved "
       f"(total observed: {n_observed})")

    # ------------------------------------------------------------------ #
    # Step 3 – Apply treatment policy & build target list                 #
    # ------------------------------------------------------------------ #
    _p("Applying treatment policy and computing per-target spray durations...")
    plant_pos: Dict[str, tuple] = {p["plant_id"]: (p["x"], p["y"]) for p in plants}
    treatment_decisions:  Dict[str, Any]  = {}
    treatment_targets:    List[Dict[str, Any]] = []

    for plant in plants:
        pid = plant["plant_id"]
        cr  = classification_results.get(pid, {})
        is_fault = mapping.get(pid, {}).get("is_injected_fault", False)
        policy   = apply_treatment_policy(cr, is_fault)
        treatment_decisions[pid] = policy

        if not policy["spray_blocked"] and policy["duration_s"] > 0.0:
            px, py = plant_pos[pid]
            treatment_targets.append({
                "plant_id":     pid,
                "x":            px,
                "y":            py,
                "duration_s":   policy["duration_s"],
                "severity_band": policy["severity_band"],
                "affected_pct": policy["affected_pct"],
            })

    _p(f"Treatment targets: {len(treatment_targets)} qualifying target(s)")

    # ------------------------------------------------------------------ #
    # Step 4 – Write treatment_targets.json to unblock MATLAB             #
    # ------------------------------------------------------------------ #
    targets_payload = {
        "mission_id":     mission_id,
        "n_targets":      len(treatment_targets),
        "targets":        treatment_targets,
        "generated_at":   datetime.now(timezone.utc).isoformat(),
        "disclosure": (
            "Targets selected by Python disease classifier using precomputed inference. "
            "Pass 2 reuses Pass 1 assigned images (no physical camera). "
            "Durations are simulation-only (one configured flow rate: 25 mL/s)."
        ),
    }
    _write_json_atomic(mission_dir / "treatment_targets.json", targets_payload)
    _p(f"treatment_targets.json written ({len(treatment_targets)} targets)")

    # ------------------------------------------------------------------ #
    # Step 5 – Wait for MATLAB treatment_data.json                        #
    # ------------------------------------------------------------------ #
    treatment_file = mission_dir / "treatment_data.json"
    _p("Waiting for MATLAB treatment_data.json...")
    wait_for_file(treatment_file, max_wait_s=600, abort_check=abort_check)
    treatment = _read_json(treatment_file)
    tmt_legs: List[Dict[str, Any]] = treatment.get("treatment_legs", [])
    _p(f"Treatment received: {treatment['n_targets']} targets, {len(tmt_legs)} leg(s)")

    # ------------------------------------------------------------------ #
    # Step 6 – Update executed durations from MATLAB-reported leg data    #
    # ------------------------------------------------------------------ #
    for leg in tmt_legs:
        tid = leg.get("target_id")
        if tid and tid != "none" and tid in treatment_decisions:
            dec = treatment_decisions[tid]
            if not dec["spray_blocked"]:
                dec["executed_duration_s"] = leg.get("executed_duration_s", 0.0)

    # ------------------------------------------------------------------ #
    # Step 7 – Build assessment events (severity revealed at arrival)     #
    # ------------------------------------------------------------------ #
    t_offset = survey["flight_time"]   # treatment timestamps are local to Pass 2
    target_assessment_events: Dict[str, Any] = {}

    for leg in tmt_legs:
        if leg.get("leg_kind") != "treatment":
            continue
        tid = leg.get("target_id")
        if not tid or tid == "none":
            continue
        steps_list = leg.get("steps", [])
        first_t = (steps_list[0]["t"] + t_offset) if steps_list else t_offset
        dec = treatment_decisions.get(tid, {})
        cr2 = classification_results.get(tid, {})
        target_assessment_events[tid] = {
            "target_id":             tid,
            "assessment_timestamp":  round(first_t, 3),
            "severity_band":         dec.get("severity_band"),
            "affected_pct":          dec.get("affected_pct"),
            "recheck_passed":        dec.get("recheck_passed"),
            "requested_duration_s":  leg.get("requested_duration_s"),
            "executed_duration_s":   leg.get("executed_duration_s"),
            "emitted_volume_mL":     leg.get("emitted_volume_mL"),
            "image_reuse_disclosure": dec.get("image_reuse_disclosure"),
            "predicted_class":       cr2.get("predicted_class"),
            "confidence":            cr2.get("confidence"),
        }

    # ------------------------------------------------------------------ #
    # Step 8 – Build time-shifted treatment steps for unified replay      #
    # ------------------------------------------------------------------ #
    survey_steps   = survey.get("telemetry_steps", [])
    treatment_steps: List[Dict[str, Any]] = []

    for leg in tmt_legs:
        for step in leg.get("steps", []):
            s2 = dict(step)
            s2["t"]           = round(step["t"] + t_offset, 3)
            s2["leg_id"]      = leg["leg_id"]
            s2["leg_kind"]    = leg["leg_kind"]
            s2["target_id"]   = leg["target_id"]
            treatment_steps.append(s2)

    # ------------------------------------------------------------------ #
    # Step 9 – Compose unified timeline                                   #
    # ------------------------------------------------------------------ #
    total_emitted = sum(
        leg.get("emitted_volume_mL", 0.0)
        for leg in tmt_legs
        if leg.get("leg_kind") == "treatment"
    )
    routes = treatment.get("routes", {})

    timeline = {
        "mission_id": mission_id,
        "provenance": "authoritative_matlab_navigation",
        "mode":       "MATLAB simulation replay",
        "disclosure": (
            "Two-pass mission. All navigation and spray timing executed by MATLAB batch. "
            "Python model classifies images precomputed before replay. "
            "Pass 2 reuses Pass 1 image assignments (no live camera). "
            "Severity is precomputed and revealed at treatment-leg arrival during replay. "
            "Not a live mission."
        ),
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "seed":         camera_mapping.get("seed"),
        "camera_mapping_proportions": camera_mapping.get("proportions"),
        "field": {
            "polygon":            survey.get("field_polygon"),
            "dimensions":         survey.get("field_dimensions"),
            "num_rows":           survey.get("num_rows"),
            "total_plants":       survey.get("total_plants"),
            "survey_path_length": survey.get("survey_path_length"),
        },
        "reference_path":          survey.get("reference_path"),
        "plants":                  plants,
        "classification_results":  classification_results,
        "treatment_decisions":     treatment_decisions,
        "treatment_targets":       treatment_targets,
        "target_assessment_events": target_assessment_events,
        "survey_steps":            survey_steps,
        "treatment_steps":         treatment_steps,
        "summary": {
            "survey_flight_time_s":     survey.get("flight_time"),
            "survey_flight_distance_m": survey.get("flight_distance"),
            "total_plants":             survey.get("total_plants"),
            "plants_observed":          n_observed,
            "n_healthy":                n_healthy,
            "n_disease_positive":       n_disease,
            "n_error":                  n_error,
            "n_unobserved":             n_unobserved,
            "n_treatment_targets":      len(treatment_targets),
            "treatment_flight_time_s":  routes.get("actualTotalTime", 0),
            "treatment_actual_dwell_s": routes.get("actualDwellTime", 0),
            "treatment_distance_m":     routes.get("actualDistance", 0),
            "total_emitted_volume_mL":  total_emitted,
            "flow_rate_mL_per_s":       treatment.get("flow_rate_mL_per_s", 25.0),
        },
    }

    _p("Unified timeline constructed. Two-pass computation complete.")
    return timeline
