"""Deterministic mock UAV mission simulator for the dashboard."""

from __future__ import annotations

import random
import threading
import time
from datetime import datetime, timezone
from typing import Any


class MissionSimulator:
    """Simulate a lawnmower flight, detections, and variable-rate spraying."""

    ROWS = 10
    COLS = 10
    DETECTION_INTERVAL_SECONDS = 2.0

    def __init__(self, field_length: float, field_width: float, drone_speed: float = 1.0) -> None:
        if field_length <= 0 or field_width <= 0:
            raise ValueError("Field dimensions must be greater than zero")
        if drone_speed <= 0:
            raise ValueError("Drone speed must be greater than zero")
        self.field_length = float(field_length)
        self.field_width = float(field_width)
        self.drone_speed = float(drone_speed)
        self._lock = threading.RLock()
        self._reset_state()

    def _reset_state(self) -> None:
        seed = int(self.field_length * 100 + self.field_width * 10)
        generator = random.Random(seed)
        self._severity = [
            [round(generator.betavariate(1.4, 5.5) * 40, 1) for _ in range(self.COLS)]
            for _ in range(self.ROWS)
        ]
        self._sprayed = [[False] * self.COLS for _ in range(self.ROWS)]
        self._revealed = [[False] * self.COLS for _ in range(self.ROWS)]
        self._spray_log: list[dict[str, Any]] = []
        self._x = 0.0
        self._y = 0.0
        self._row = 0
        self._direction = 1
        self._heading = 90.0
        self._covered_distance = 0.0
        self._last_detection_at = -self.DETECTION_INTERVAL_SECONDS
        self._started_at: float | None = None
        self._last_update = time.monotonic()
        self._running = False
        self._complete = False

    def start(self) -> None:
        with self._lock:
            self._reset_state()
            self._started_at = time.time()
            self._last_update = time.monotonic()
            self._running = True

    def stop(self) -> None:
        with self._lock:
            self._running = False

    def update(self) -> None:
        with self._lock:
            if not self._running or self._complete:
                return
            now = time.monotonic()
            elapsed = min(now - self._last_update, 1.5)
            self._last_update = now
            distance = elapsed * self.drone_speed
            self._move(distance)
            if now - self._last_detection_at >= self.DETECTION_INTERVAL_SECONDS:
                self._detect_current_cell(now)

    def _move(self, distance: float) -> None:
        row_height = self.field_width / self.ROWS
        remaining = distance
        while remaining > 0 and not self._complete:
            edge_distance = self.field_length - self._x if self._direction > 0 else self._x
            step = min(remaining, edge_distance)
            self._x += step * self._direction
            self._covered_distance += step
            remaining -= step
            if step < edge_distance:
                continue
            if self._row == self.ROWS - 1:
                self._complete = True
                self._running = False
                self._y = self.field_width
                break
            self._row += 1
            self._y = min(self.field_width, self._row * row_height)
            self._direction *= -1
            self._heading = 90.0 if self._direction > 0 else 270.0

    def _detect_current_cell(self, now: float) -> None:
        col = min(self.COLS - 1, int(self._x / self.field_length * self.COLS))
        row = min(self.ROWS - 1, int(self._y / self.field_width * self.ROWS))
        severity = self._severity[row][col]
        self._revealed[row][col] = True
        self._last_detection_at = now
        if severity <= 5 or self._sprayed[row][col]:
            return
        if severity <= 15:
            level, rate, duration = "Low", 2.0, 2
        elif severity <= 30:
            level, rate, duration = "Medium", 4.0, 4
        else:
            level, rate, duration = "High", 6.0, 6
        self._sprayed[row][col] = True
        self._spray_log.append({
            "timestamp": self._timestamp(),
            "position": {"x": round(self._x, 2), "y": round(self._y, 2)},
            "severity": severity,
            "spray_amount_ml": rate * duration,
            "severity_level": level,
        })

    @staticmethod
    def _timestamp() -> str:
        return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    def get_telemetry(self) -> dict[str, Any]:
        with self._lock:
            self.update()
            elapsed = time.time() - self._started_at if self._started_at else 0.0
            return {
                "timestamp": self._timestamp(),
                "position": {"x": round(self._x, 2), "y": round(self._y, 2)},
                "heading": self._heading,
                "speed": self.drone_speed if self._running else 0.0,
                "altitude": 2.0,
                "battery": max(0, round(100 - elapsed * 0.08, 1)),
                "status": self.status,
            }

    def get_disease_map(self) -> dict[str, Any]:
        with self._lock:
            cells = []
            for row in range(self.ROWS):
                for col in range(self.COLS):
                    cells.append({
                        "row": row,
                        "col": col,
                        "severity": self._severity[row][col] if self._revealed[row][col] else 0.0,
                        "sprayed": self._sprayed[row][col],
                        "scanned": self._revealed[row][col],
                    })
            return {
                "field_dimensions": {"length": self.field_length, "width": self.field_width},
                "grid_size": {"rows": self.ROWS, "cols": self.COLS},
                "cells": cells,
            }

    def get_spray_log(self) -> list[dict[str, Any]]:
        with self._lock:
            return list(reversed(self._spray_log))

    @property
    def status(self) -> str:
        if self._complete:
            return "Completed"
        if self._running:
            return "Running"
        return "Ready"

    def get_status(self) -> dict[str, Any]:
        with self._lock:
            self.update()
            area = self.field_length * self.field_width
            progress = min(100.0, self._covered_distance / (self.field_length * self.ROWS) * 100)
            scanned = sum(sum(row) for row in self._revealed)
            diseased = sum(self._severity[r][c] > 5 for r in range(self.ROWS) for c in range(self.COLS) if self._revealed[r][c])
            return {
                "status": self.status,
                "field_dimensions": {"length": self.field_length, "width": self.field_width},
                "total_area_m2": round(area, 2),
                "covered_area_m2": round(area * progress / 100, 2),
                "mission_progress": round(progress, 1),
                "disease_detected_percent": round(diseased / scanned * 100, 1) if scanned else 0.0,
                "spray_used_ml": round(sum(event["spray_amount_ml"] for event in self._spray_log), 1),
                "plants_treated": len(self._spray_log),
                "elapsed_seconds": round(time.time() - self._started_at, 1) if self._started_at else 0.0,
            }

    def is_complete(self) -> bool:
        with self._lock:
            return self._complete
