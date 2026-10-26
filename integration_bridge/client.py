"""Integration Bridge Client.

Provides a Python interface to query disease classification and severity
estimation via localhost REST or file-based IPC.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Optional

# Ensure bytecode is never written to protected directories
os.environ["PYTHONDONTWRITEBYTECODE"] = "1"

BRIDGE_DIR = Path(__file__).resolve().parent
REPO_ROOT = BRIDGE_DIR.parent


class BridgeClient:
    """Client for communicating with the Integration Bridge."""

    def __init__(
        self,
        base_url: str = "http://127.0.0.1:5005",
        timeout_s: float = 10.0,
        mode: str = "rest",
        io_dir: Optional[Path] = None
    ):
        self.base_url = base_url.rstrip("/")
        self.timeout_s = timeout_s
        self.mode = mode
        self.io_dir = io_dir or (BRIDGE_DIR / "io")
        self.req_dir = self.io_dir / "requests"
        self.resp_dir = self.io_dir / "responses"

    def check_health(self) -> Dict[str, Any]:
        """Query the /bridge/health endpoint."""
        url = f"{self.base_url}/bridge/health"
        req = urllib.request.Request(url, headers={"User-Agent": "BridgeClient/1.0"})
        with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def predict_rest(
        self,
        image_path: str | Path,
        mission_id: str = "mission_cli",
        request_id: Optional[str] = None,
        plant_id: Optional[Any] = None
    ) -> Dict[str, Any]:
        """Send prediction request over HTTP REST."""
        req_id = request_id or f"req_{int(time.time()*1000)}"
        url = f"{self.base_url}/bridge/predict"
        payload = {
            "mission_id": mission_id,
            "request_id": req_id,
            "plant_id": plant_id,
            "image_path": str(image_path)
        }
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json", "User-Agent": "BridgeClient/1.0"}
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout_s) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            try:
                err_data = json.loads(e.read().decode("utf-8"))
                return err_data
            except Exception:
                return {
                    "mission_id": mission_id,
                    "request_id": req_id,
                    "plant_id": plant_id,
                    "status": "error",
                    "predicted_class": "unknown",
                    "confidence": None,
                    "class_probabilities": None,
                    "severity": None,
                    "spray_allowed": False,
                    "error": f"HTTP {e.code}: {e.reason}"
                }
        except Exception as exc:
            return {
                "mission_id": mission_id,
                "request_id": req_id,
                "plant_id": plant_id,
                "status": "error",
                "predicted_class": "unknown",
                "confidence": None,
                "class_probabilities": None,
                "severity": None,
                "spray_allowed": False,
                "error": f"Connection error: {str(exc)}"
            }

    def predict_file_ipc(
        self,
        image_path: str | Path,
        mission_id: str = "mission_ipc",
        request_id: Optional[str] = None,
        plant_id: Optional[Any] = None
    ) -> Dict[str, Any]:
        """Send prediction request via atomic file IPC."""
        req_id = request_id or f"req_{int(time.time()*1000)}"
        self.req_dir.mkdir(parents=True, exist_ok=True)
        self.resp_dir.mkdir(parents=True, exist_ok=True)

        req_payload = {
            "mission_id": mission_id,
            "request_id": req_id,
            "plant_id": plant_id,
            "image_path": str(image_path),
            "timestamp": datetime.now(timezone.utc).isoformat()
        }

        # Write request file atomically (.tmp -> .json)
        tmp_req = self.req_dir / f"req_{mission_id}_{req_id}.tmp"
        final_req = self.req_dir / f"req_{mission_id}_{req_id}.json"
        with open(tmp_req, "w", encoding="utf-8") as f:
            json.dump(req_payload, f, indent=2)
        tmp_req.replace(final_req)

        expected_resp = self.resp_dir / f"resp_{mission_id}_{req_id}.json"
        start_time = time.time()

        # Poll for response file with bounded timeout
        while time.time() - start_time < self.timeout_s:
            if expected_resp.exists():
                try:
                    with open(expected_resp, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    expected_resp.unlink(missing_ok=True)
                    return data
                except Exception:
                    pass
            time.sleep(0.1)

        return {
            "mission_id": mission_id,
            "request_id": req_id,
            "plant_id": plant_id,
            "status": "error",
            "predicted_class": "unknown",
            "confidence": None,
            "class_probabilities": None,
            "severity": None,
            "spray_allowed": False,
            "error": f"File IPC timeout after {self.timeout_s:.1f}s waiting for {expected_resp.name}"
        }


def main():
    parser = argparse.ArgumentParser(description="Query Integration Bridge")
    parser.add_argument("--image", required=True, help="Path to leaf image")
    parser.add_argument("--plant-id", default=1, help="Simulated plant ID")
    parser.add_argument("--mission-id", default="mission_cli_test", help="Mission ID")
    parser.add_argument("--mode", default="rest", choices=["rest", "ipc"], help="Transport mode")
    parser.add_argument("--url", default="http://127.0.0.1:5005", help="Bridge server URL")
    args = parser.parse_args()

    client = BridgeClient(base_url=args.url, mode=args.mode)
    if args.mode == "rest":
        res = client.predict_rest(args.image, mission_id=args.mission_id, plant_id=args.plant_id)
    else:
        res = client.predict_file_ipc(args.image, mission_id=args.mission_id, plant_id=args.plant_id)

    print(json.dumps(res, indent=2))
    return 0 if res.get("status") == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
