"""Leaf disease severity estimation using experimental image-processing techniques.

Calculates the percentage of visible leaf area affected by lesions:
    affected_leaf_area_percent = 100 * lesion_pixels_inside_leaf / visible_leaf_pixels

IMPORTANT LIMITATIONS:
- This is an experimental image-processing prototype, NOT a clinically or agronomically
  validated disease severity measurement.
- It measures visible surface pixel discoloration within the segmented leaf mask only.
- It does NOT estimate full-plant infection, Percent Disease Index (PDI), or pesticide dosages.
- Shadows, specular reflections, nutrient deficiency, natural senescence, soil particles,
  or physical leaf damage can resemble lesions.
- If leaf/background separation fails or the image is unsuitable, the estimator marks severity
  as 'unavailable' rather than fabricating a percentage.
"""

from __future__ import annotations

import base64
from pathlib import Path
from typing import Any

import cv2
import numpy as np
import yaml


def load_severity_config(config_path: Path | str | None = None) -> dict[str, Any]:
    """Load configuration for severity estimation."""
    if config_path is None:
        config_path = Path(__file__).resolve().parent.parent / "config" / "severity_config.yaml"
    path = Path(config_path)
    if not path.is_file():
        raise FileNotFoundError(f"Severity configuration not found at {path}")
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def assign_severity_band(affected_pct: float | None, config: dict[str, Any] | None = None) -> tuple[str | None, str | None]:
    """Assign a categorical severity band according to configurable thresholds.

    Bands:
      affected_pct == 0.0          -> 'none', 'None'
      0.0 < affected_pct <= 5.0    -> 'very_low', 'Very low'
      5.0 < affected_pct <= 10.0   -> 'low', 'Low'
      10.0 < affected_pct <= 25.0  -> 'medium', 'Medium'
      25.0 < affected_pct <= 50.0  -> 'high', 'High'
      50.0 < affected_pct <= 100.0 -> 'critical', 'Critical'
    """
    if affected_pct is None:
        return None, None

    # Handle float tolerance / clamping
    val = round(float(affected_pct), 4)
    if val <= 0.0:
        return "none", "None"
    elif val <= 5.0:
        return "very_low", "Very low"
    elif val <= 10.0:
        return "low", "Low"
    elif val <= 25.0:
        return "medium", "Medium"
    elif val <= 50.0:
        return "high", "High"
    else:
        return "critical", "Critical"


def calculate_severity_metrics(
    leaf_mask: np.ndarray,
    lesion_mask: np.ndarray,
    config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Calculate numerical metrics strictly from leaf and lesion binary masks.

    Parameters
    ----------
    leaf_mask : np.ndarray
        Binary mask (uint8 or bool, >0 indicates leaf).
    lesion_mask : np.ndarray
        Binary mask (uint8 or bool, >0 indicates candidate lesion).
    config : dict, optional
        Configuration dictionary.

    Returns
    -------
    dict
        Numerical results including counts, percentage, band, and validation status.
    """
    if leaf_mask is None or lesion_mask is None:
        return {
            "status": "unavailable",
            "affected_leaf_area_percent": None,
            "band": None,
            "band_label": None,
            "leaf_pixels": 0,
            "lesion_pixels_inside_leaf": 0,
            "lesion_pixels_outside_leaf": 0,
            "reasons": ["Invalid or missing mask input."],
        }

    if leaf_mask.shape != lesion_mask.shape:
        return {
            "status": "unavailable",
            "affected_leaf_area_percent": None,
            "band": None,
            "band_label": None,
            "leaf_pixels": 0,
            "lesion_pixels_inside_leaf": 0,
            "lesion_pixels_outside_leaf": 0,
            "reasons": [f"Leaf mask shape {leaf_mask.shape} != lesion mask shape {lesion_mask.shape}."],
        }

    leaf_bin = (leaf_mask > 0).astype(np.uint8)
    lesion_bin = (lesion_mask > 0).astype(np.uint8)

    leaf_pixels = int(np.sum(leaf_bin))
    if leaf_pixels == 0:
        return {
            "status": "unavailable",
            "affected_leaf_area_percent": None,
            "band": None,
            "band_label": None,
            "leaf_pixels": 0,
            "lesion_pixels_inside_leaf": 0,
            "lesion_pixels_outside_leaf": int(np.sum(lesion_bin)),
            "reasons": ["No visible leaf pixels detected in leaf mask."],
        }

    # Intersect lesion mask strictly with leaf mask
    lesion_inside = np.logical_and(leaf_bin == 1, lesion_bin == 1)
    lesion_outside = np.logical_and(leaf_bin == 0, lesion_bin == 1)

    lesion_inside_pixels = int(np.sum(lesion_inside))
    lesion_outside_pixels = int(np.sum(lesion_outside))

    raw_pct = (lesion_inside_pixels / leaf_pixels) * 100.0
    # Strict clamping between 0 and 100
    affected_pct = max(0.0, min(100.0, float(raw_pct)))
    affected_pct_rounded = round(affected_pct, 1)

    band, band_label = assign_severity_band(affected_pct, config)

    return {
        "status": "estimated",
        "affected_leaf_area_percent": affected_pct_rounded,
        "band": band,
        "band_label": band_label,
        "leaf_pixels": leaf_pixels,
        "lesion_pixels_inside_leaf": lesion_inside_pixels,
        "lesion_pixels_outside_leaf": lesion_outside_pixels,
        "reasons": [],
    }


def validate_image_and_mask_quality(
    image_rgb: np.ndarray,
    leaf_mask: np.ndarray,
    config: dict[str, Any],
) -> list[str]:
    """Validate image and segmentation quality against prototype thresholds.

    Returns a list of warning/failure reasons.
    """
    reasons: list[str] = []
    cfg_img = config.get("image_quality", {})

    h, w = image_rgb.shape[:2]
    min_w = cfg_img.get("min_width", 64)
    min_h = cfg_img.get("min_height", 64)
    if w < min_w or h < min_h:
        reasons.append(f"Image dimensions ({w}x{h}) are too small for reliable analysis (min {min_w}x{min_h}).")
        return reasons

    # Brightness / saturation check
    gray = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2GRAY)
    mean_val = float(np.mean(gray))
    b_min = cfg_img.get("brightness_min", 25.0)
    b_max = cfg_img.get("brightness_max", 240.0)
    if mean_val < b_min:
        reasons.append(f"Image is excessively dark (mean luminance {mean_val:.1f} < {b_min}).")
    elif mean_val > b_max:
        reasons.append(f"Image is excessively saturated/bright (mean luminance {mean_val:.1f} > {b_max}).")

    # Focus / blur check
    laplacian_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    blur_th = cfg_img.get("blur_laplacian_var_threshold", 40.0)
    if laplacian_var < blur_th:
        reasons.append(f"Image may be severely blurred (focus score {laplacian_var:.1f} < {blur_th}).")

    # Leaf mask ratio checks
    total_pixels = h * w
    leaf_pixels = int(np.sum(leaf_mask > 0))
    leaf_ratio = leaf_pixels / total_pixels if total_pixels > 0 else 0.0

    min_ratio = cfg_img.get("min_leaf_pixel_ratio", 0.05)
    max_ratio = cfg_img.get("max_leaf_pixel_ratio", 0.98)
    if leaf_ratio < min_ratio:
        reasons.append(f"Visible leaf area is too small ({leaf_ratio*100:.1f}% < {min_ratio*100:.1f}% of image).")
    elif leaf_ratio > max_ratio:
        reasons.append(f"Leaf mask fills almost entire image ({leaf_ratio*100:.1f}% > {max_ratio*100:.1f}%), background separation may have failed.")

    # Boundary touch ratio
    border_pixels = 2 * (h + w)
    border_leaf = (
        np.sum(leaf_mask[0, :] > 0)
        + np.sum(leaf_mask[-1, :] > 0)
        + np.sum(leaf_mask[:, 0] > 0)
        + np.sum(leaf_mask[:, -1] > 0)
    )
    border_touch_ratio = border_leaf / border_pixels if border_pixels > 0 else 0.0
    max_border = cfg_img.get("max_boundary_touch_ratio", 0.35)
    if border_touch_ratio > max_border:
        reasons.append(f"Leaf mask touches {border_touch_ratio*100:.1f}% of frame perimeter (leaf may be truncated).")

    return reasons


def segment_leaf_and_lesions(
    image_rgb: np.ndarray,
    config: dict[str, Any],
) -> tuple[np.ndarray, np.ndarray]:
    """Segment leaf mask (including chlorotic/necrotic areas) and candidate lesion pixels.

    Returns
    -------
    leaf_mask : np.ndarray (uint8, 0 or 255)
    lesion_mask : np.ndarray (uint8, 0 or 255)
    """
    hsv = cv2.cvtColor(image_rgb, cv2.COLOR_RGB2HSV)
    h, w = image_rgb.shape[:2]

    # --- 1. Leaf Mask Generation ---
    # Leaf area must include healthy green, chlorotic yellow/brown, and necrotic brown
    cfg_leaf = config.get("leaf_segmentation", {})
    ranges = cfg_leaf.get("hsv_ranges", {})

    leaf_mask = np.zeros((h, w), dtype=np.uint8)
    for part_name, r in ranges.items():
        lower = np.array(r["lower"], dtype=np.uint8)
        upper = np.array(r["upper"], dtype=np.uint8)
        part_mask = cv2.inRange(hsv, lower, upper)
        leaf_mask = cv2.bitwise_or(leaf_mask, part_mask)

    # Morphological clean-up
    morph_cfg = cfg_leaf.get("morphology", {})
    k_size = morph_cfg.get("kernel_size", 5)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k_size, k_size))
    open_it = morph_cfg.get("open_iterations", 1)
    close_it = morph_cfg.get("close_iterations", 2)

    leaf_mask = cv2.morphologyEx(leaf_mask, cv2.MORPH_OPEN, kernel, iterations=open_it)
    leaf_mask = cv2.morphologyEx(leaf_mask, cv2.MORPH_CLOSE, kernel, iterations=close_it)

    if cfg_leaf.get("fill_holes", True):
        # Fill internal holes (e.g. inner chlorotic spots that were missed by leaf hue)
        contours, _ = cv2.findContours(leaf_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        cv2.drawContours(leaf_mask, contours, -1, 255, thickness=cv2.FILLED)

    # --- 2. Candidate Lesion Detection ---
    cfg_lesion = config.get("lesion_detection", {})
    lesion_ranges = cfg_lesion.get("hsv_ranges", {})

    lesion_raw = np.zeros((h, w), dtype=np.uint8)
    for r_name, r in lesion_ranges.items():
        lower = np.array(r["lower"], dtype=np.uint8)
        upper = np.array(r["upper"], dtype=np.uint8)
        m = cv2.inRange(hsv, lower, upper)
        lesion_raw = cv2.bitwise_or(lesion_raw, m)

    # Intersect with leaf mask strictly
    lesion_mask = cv2.bitwise_and(lesion_raw, leaf_mask)

    # Morphological clean-up on lesions
    l_morph = cfg_lesion.get("morphology", {})
    lk_size = l_morph.get("kernel_size", 3)
    l_kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (lk_size, lk_size))
    lesion_mask = cv2.morphologyEx(lesion_mask, cv2.MORPH_OPEN, l_kernel, iterations=l_morph.get("open_iterations", 1))
    lesion_mask = cv2.morphologyEx(lesion_mask, cv2.MORPH_CLOSE, l_kernel, iterations=l_morph.get("close_iterations", 1))

    return leaf_mask, lesion_mask


def generate_overlay_image(
    image_rgb: np.ndarray,
    leaf_mask: np.ndarray,
    lesion_mask: np.ndarray,
) -> str:
    """Generate a lightweight RGB overlay with leaf contours and lesion highlighting, encoded as base64 PNG."""
    overlay = image_rgb.copy()

    # Dim the background pixels outside the leaf mask slightly to highlight the leaf
    non_leaf = leaf_mask == 0
    overlay[non_leaf] = (overlay[non_leaf] * 0.45).astype(np.uint8)

    # Draw leaf boundary in teal/cyan
    contours, _ = cv2.findContours(leaf_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    cv2.drawContours(overlay, contours, -1, (40, 220, 180), 2)

    # Color candidate lesion pixels with transparent red/orange highlight
    lesion_inside = np.logical_and(leaf_mask > 0, lesion_mask > 0)
    if np.any(lesion_inside):
        highlight = overlay.copy()
        highlight[lesion_inside] = [235, 75, 55]  # Red-orange highlight
        overlay = cv2.addWeighted(highlight, 0.65, overlay, 0.35, 0)

    # Encode to base64 JPEG or PNG for safe web transfer
    # Use JPEG with quality 85 to keep response compact
    bgr = cv2.cvtColor(overlay, cv2.COLOR_RGB2BGR)
    success, buffer = cv2.imencode(".jpg", bgr, [int(cv2.IMWRITE_JPEG_QUALITY), 85])
    if not success:
        return ""
    b64_str = base64.b64encode(buffer).decode("ascii")
    return f"data:image/jpeg;base64,{b64_str}"


def estimate_leaf_severity(
    image_input: str | Path | np.ndarray,
    predicted_class: str | None = None,
    config: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Estimate visible leaf disease severity from an image and predicted class.

    Parameters
    ----------
    image_input : str, Path, or np.ndarray
        File path or preloaded RGB uint8 image array.
    predicted_class : str, optional
        Classifier predicted class ('healthy', 'early_blight', 'late_blight').
    config : dict, optional
        Loaded configuration dictionary.

    Returns
    -------
    dict
        Structured severity response per specification.
    """
    if config is None:
        try:
            config = load_severity_config()
        except Exception:
            config = {}

    disclaimer_text = (
        "Experimental visual estimate of visible leaf lesion area, NOT classifier confidence, "
        "full-plant severity, or a pesticide instruction. Not clinically or agronomically validated."
    )

    # 1. Read / convert image
    if isinstance(image_input, (str, Path)):
        img_bgr = cv2.imread(str(image_input))
        if img_bgr is None:
            return {
                "status": "unavailable",
                "affected_leaf_area_percent": None,
                "band": None,
                "band_label": None,
                "method": "experimental_image_processing",
                "validated": False,
                "reliability": "unavailable",
                "reasons": ["Image file could not be read or decoded."],
                "disclaimer": disclaimer_text,
                "overlay_image": None,
            }
        image_rgb = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB)
    elif isinstance(image_input, np.ndarray):
        image_rgb = image_input
    else:
        return {
            "status": "unavailable",
            "affected_leaf_area_percent": None,
            "band": None,
            "band_label": None,
            "method": "experimental_image_processing",
            "validated": False,
            "reliability": "unavailable",
            "reasons": ["Unsupported image input type."],
            "disclaimer": disclaimer_text,
            "overlay_image": None,
        }

    try:
        # 2. Segment leaf and lesions
        leaf_mask, lesion_mask = segment_leaf_and_lesions(image_rgb, config)

        # 3. Quality & validity checks
        reasons = validate_image_and_mask_quality(image_rgb, leaf_mask, config)

        # 4. Calculate metrics
        metrics = calculate_severity_metrics(leaf_mask, lesion_mask, config)

        if metrics["status"] == "unavailable":
            combined_reasons = reasons + metrics.get("reasons", [])
            return {
                "status": "unavailable",
                "affected_leaf_area_percent": None,
                "band": None,
                "band_label": None,
                "method": "experimental_image_processing",
                "validated": False,
                "reliability": "unavailable",
                "reasons": combined_reasons if combined_reasons else ["Leaf/background separation was unreliable."],
                "disclaimer": disclaimer_text,
                "overlay_image": None,
            }

        affected_pct = metrics["affected_leaf_area_percent"]
        band = metrics["band"]
        band_label = metrics["band_label"]

        # Check for disagreement between healthy prediction and detected lesions
        if predicted_class == "healthy" and affected_pct is not None and affected_pct > 2.0:
            reasons.append(
                f"Classifier predicted healthy, but image analysis identified {affected_pct}% candidate lesion area. "
                "Manual review required."
            )

        reliability = "requires_manual_review" if reasons else "experimental_estimate"

        # Generate visual overlay
        overlay_b64 = generate_overlay_image(image_rgb, leaf_mask, lesion_mask)

        return {
            "status": "estimated",
            "affected_leaf_area_percent": affected_pct,
            "band": band,
            "band_label": band_label,
            "leaf_pixels": metrics["leaf_pixels"],
            "lesion_pixels_inside_leaf": metrics["lesion_pixels_inside_leaf"],
            "method": "experimental_image_processing",
            "validated": False,
            "reliability": reliability,
            "reasons": reasons,
            "disclaimer": disclaimer_text,
            "overlay_image": overlay_b64,
        }

    except Exception as exc:
        return {
            "status": "unavailable",
            "affected_leaf_area_percent": None,
            "band": None,
            "band_label": None,
            "method": "experimental_image_processing",
            "validated": False,
            "reliability": "unavailable",
            "reasons": [f"Severity analysis encountered an internal error: {str(exc)}"],
            "disclaimer": disclaimer_text,
            "overlay_image": None,
        }
