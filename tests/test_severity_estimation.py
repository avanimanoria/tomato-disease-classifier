"""Unit tests for leaf disease severity estimation logic.

Tests numerical logic against synthetic masks, boundary conditions,
missing or invalid masks, and error recovery.
NOTE: Synthetic-mask tests verify calculation and threshold logic only;
they do not validate biological/agronomic accuracy on real leaves.
"""

from __future__ import annotations

import numpy as np
import pytest

from src.severity_estimation import (
    assign_severity_band,
    calculate_severity_metrics,
    estimate_leaf_severity,
)


def test_severity_bands_standard_values():
    """Test standard severity percentage assignments per agreed bands:
    - 0% -> None
    - 3% -> Very low
    - 8% -> Low
    - 18% -> Medium
    - 40% -> High
    - 70% -> Critical
    """
    assert assign_severity_band(0.0) == ("none", "None")
    assert assign_severity_band(3.0) == ("very_low", "Very low")
    assert assign_severity_band(8.0) == ("low", "Low")
    assert assign_severity_band(18.0) == ("medium", "Medium")
    assert assign_severity_band(40.0) == ("high", "High")
    assert assign_severity_band(70.0) == ("critical", "Critical")


def test_severity_bands_exact_boundaries():
    """Test exact boundary points: 5.0%, 10.0%, 25.0%, 50.0%, 100.0%."""
    # 5.0 is upper bound of Very low
    assert assign_severity_band(5.0) == ("very_low", "Very low")
    # 5.01 enters Low
    assert assign_severity_band(5.01) == ("low", "Low")

    # 10.0 is upper bound of Low
    assert assign_severity_band(10.0) == ("low", "Low")
    # 10.01 enters Medium
    assert assign_severity_band(10.01) == ("medium", "Medium")

    # 25.0 is upper bound of Medium
    assert assign_severity_band(25.0) == ("medium", "Medium")
    # 25.01 enters High
    assert assign_severity_band(25.01) == ("high", "High")

    # 50.0 is upper bound of High
    assert assign_severity_band(50.0) == ("high", "High")
    # 50.01 enters Critical
    assert assign_severity_band(50.01) == ("critical", "Critical")

    # 100.0 is Critical
    assert assign_severity_band(100.0) == ("critical", "Critical")


def test_synthetic_mask_metrics_exact_pixel_counts():
    """Test exact synthetic pixel counts requested in specification:
    - 0 lesion pixels / 1000 leaf pixels -> 0%, None
    - 30 / 1000 -> 3%, Very low
    - 80 / 1000 -> 8%, Low
    - 180 / 1000 -> 18%, Medium
    - 400 / 1000 -> 40%, High
    - 700 / 1000 -> 70%, Critical
    """
    h, w = 100, 100
    # Exactly 1000 leaf pixels
    leaf_mask = np.zeros((h, w), dtype=np.uint8)
    leaf_mask[0:10, 0:100] = 1  # 10 * 100 = 1000 pixels

    # 1. 0 lesion pixels
    lesion_0 = np.zeros((h, w), dtype=np.uint8)
    res_0 = calculate_severity_metrics(leaf_mask, lesion_0)
    assert res_0["status"] == "estimated"
    assert res_0["affected_leaf_area_percent"] == 0.0
    assert res_0["band"] == "none"

    # 2. 30 lesion pixels
    lesion_30 = np.zeros((h, w), dtype=np.uint8)
    lesion_30[0:3, 0:10] = 1  # 30 pixels inside leaf
    res_30 = calculate_severity_metrics(leaf_mask, lesion_30)
    assert res_30["affected_leaf_area_percent"] == 3.0
    assert res_30["band"] == "very_low"

    # 3. 80 lesion pixels
    lesion_80 = np.zeros((h, w), dtype=np.uint8)
    lesion_80[0:8, 0:10] = 1  # 80 pixels inside leaf
    res_80 = calculate_severity_metrics(leaf_mask, lesion_80)
    assert res_80["affected_leaf_area_percent"] == 8.0
    assert res_80["band"] == "low"

    # 4. 180 lesion pixels
    lesion_180 = np.zeros((h, w), dtype=np.uint8)
    lesion_180[0:9, 0:20] = 1  # 180 pixels inside leaf
    res_180 = calculate_severity_metrics(leaf_mask, lesion_180)
    assert res_180["affected_leaf_area_percent"] == 18.0
    assert res_180["band"] == "medium"

    # 5. 400 lesion pixels
    lesion_400 = np.zeros((h, w), dtype=np.uint8)
    lesion_400[0:4, 0:100] = 1  # 400 pixels inside leaf
    res_400 = calculate_severity_metrics(leaf_mask, lesion_400)
    assert res_400["affected_leaf_area_percent"] == 40.0
    assert res_400["band"] == "high"

    # 6. 700 lesion pixels
    lesion_700 = np.zeros((h, w), dtype=np.uint8)
    lesion_700[0:7, 0:100] = 1  # 700 pixels inside leaf
    res_700 = calculate_severity_metrics(leaf_mask, lesion_700)
    assert res_700["affected_leaf_area_percent"] == 70.0
    assert res_700["band"] == "critical"


def test_lesions_outside_leaf_mask_ignored():
    """Verify that candidate lesion pixels outside the leaf mask do NOT contribute to leaf severity."""
    h, w = 50, 50
    leaf_mask = np.zeros((h, w), dtype=np.uint8)
    leaf_mask[10:20, 10:20] = 1  # 100 leaf pixels

    lesion_mask = np.zeros((h, w), dtype=np.uint8)
    lesion_mask[10:12, 10:20] = 1  # 20 pixels inside leaf (20%)
    lesion_mask[30:45, 30:45] = 1  # 225 pixels outside leaf (background noise/soil)

    res = calculate_severity_metrics(leaf_mask, lesion_mask)
    assert res["status"] == "estimated"
    assert res["affected_leaf_area_percent"] == 20.0
    assert res["band"] == "medium"
    assert res["lesion_pixels_inside_leaf"] == 20
    assert res["lesion_pixels_outside_leaf"] == 225


def test_zero_leaf_pixels_returns_unavailable():
    """When no leaf pixels exist, severity must be unavailable and null, never 0% or NaN."""
    h, w = 50, 50
    leaf_mask = np.zeros((h, w), dtype=np.uint8)
    lesion_mask = np.ones((h, w), dtype=np.uint8)

    res = calculate_severity_metrics(leaf_mask, lesion_mask)
    assert res["status"] == "unavailable"
    assert res["affected_leaf_area_percent"] is None
    assert res["band"] is None
    assert len(res["reasons"]) > 0


def test_mismatched_mask_dimensions_returns_unavailable():
    """When masks have different shapes, must safely return unavailable."""
    leaf_mask = np.ones((50, 50), dtype=np.uint8)
    lesion_mask = np.ones((60, 60), dtype=np.uint8)

    res = calculate_severity_metrics(leaf_mask, lesion_mask)
    assert res["status"] == "unavailable"
    assert res["affected_leaf_area_percent"] is None


def test_invalid_input_to_estimator():
    """Invalid input to estimate_leaf_severity returns unavailable without crashing."""
    res = estimate_leaf_severity("non_existent_file.xyz")
    assert res["status"] == "unavailable"
    assert res["affected_leaf_area_percent"] is None
    assert res["band"] is None
    assert "reasons" in res
