# Tomato Disease Classifier & Drone Simulation Integration Bridge

A clean, non-invasive integration bridge that connects the Python tomato disease classification software (`software_model/`) and the MATLAB agricultural drone simulation (`drone_simu/`) into an end-to-end workflow without modifying any existing files.

---

## 1. Architecture & Design Principles

```
tomato_disease_classifier/
├── software_model/               # Strictly READ-ONLY (Python models, configs, inference)
├── drone_simu/                   # Strictly READ-ONLY (MATLAB flight dynamics, routing, spray physics)
└── integration_bridge/           # NEW EXTERNAL BRIDGE LAYER
    ├── config/                   # Bridge configuration & deterministic plant-image maps
    ├── io/                       # Atomic request/response buffers for file IPC
    ├── logs/                     # Bridge execution logs and mission output records
    ├── server.py                 # REST server & File IPC processor
    ├── client.py                 # Python client CLI
    ├── matlab_bridge_client.m    # MATLAB REST & File IPC client
    ├── bridge_mission_orchestrator.m # Single-survey mission orchestrator
    └── tests/                    # Python and MATLAB acceptance test suites
```

### Key Technical Guarantees:
1. **Zero Existing-File Modifications**: Both `software_model/` and `drone_simu/` remain completely read-only.
2. **Single Survey Pass**: The orchestrator executes `runSurveyPass()` **exactly once**, evaluating physical camera coverage (`seen`), and passes the resulting survey state directly to `runTreatmentPass()`. No duplicate survey flights occur.
3. **Observation Gating**: Only plants whose physical coordinates were covered by the drone camera footprint during Pass 1 ($d \le R_{\text{fov}}$) are eligible for image classification. Plants outside the camera footprint remain unobserved.
4. **Exact Preprocessing Reuse**: Uses `load_image_array()` directly without adding manual division by 255.0, preserving identical Keras model preprocessing.
5. **Fail-Safe Behavior**: If an image is missing, corrupted, or an inference times out, the bridge returns `predicted_class: "unknown"` with `spray_allowed: false`. Errors are never converted to healthy or severity 0.
6. **Honest Target Provenance**: In simulation, target release coordinates reuse simulated plant locations. This is explicitly labeled as `XY_source = 'true_simulated_plant_coordinates'` and does not claim image-based target localization.
7. **Unvalidated Demo Threshold**: The default `0.60` confidence threshold is a configurable demonstration threshold in `config/config.json`, not an agronomically proven safety boundary.

---

## 2. Environment & Execution Requirements

- **Python Environment**: Python 3.10+ (tested on Python 3.12 with `tensorflow`, `numpy`, `pillow`, `flask`, `pytest`).
- **MATLAB Environment**: **MATLAB Desktop or MATLAB Online** is required to run `.m` scripts. (A standalone MATLAB Runtime without the Desktop environment cannot execute raw `.m` files unless a separately compiled executable is built).

### Transport Modes & Network Boundaries:
- **Mode A: Localhost REST (`http://127.0.0.1:5005`)**: Supported when running MATLAB Desktop locally on the same host as Python.
- **Mode B: File-based JSON IPC (`integration_bridge/io/`)**: Uses atomic file writes (`.tmp` $\rightarrow$ `.json`) and bounded polling. Requires a shared filesystem. (MATLAB Online cannot see the laptop's local disk without configured cloud storage sync; transport to MATLAB Online is pending separate configuration).

---

## 3. How to Run

### Step 1: Start the Python Bridge Server
In a terminal at the project root:
```bash
python -m integration_bridge.server --config integration_bridge/config/config.json
```
*Loads `software_model/models/best_model.keras` into memory once and listens on `http://127.0.0.1:5005`.*

### Step 2: Run Python Bridge Verification Tests
In a separate terminal:
```bash
python -m pytest -o cache_dir=integration_bridge/.pytest_cache integration_bridge/tests/test_bridge_python.py -v
```

### Step 3: Run the Integrated Mission in MATLAB Desktop or Online
Inside your MATLAB command window:
```matlab
cd('c:/Users/avani manoria/OneDrive/Desktop/tomato_disease_classifier');
addpath(genpath('drone_simu'));
addpath(genpath('integration_bridge'));

% Run the integrated end-to-end mission:
run = bridge_mission_orchestrator();

% Or run the MATLAB acceptance test suite:
results = test_matlab_integration();
```

---

## 4. Disclosures & Scope Limits

1. **Dashboard Telemetry**: The web dashboard in `software_model/frontend/app.py` has no external telemetry input endpoints. External drone telemetry cannot be rendered in that dashboard under the zero-edit constraint. Mission telemetry is preserved in `run` and logged to `integration_bridge/logs/`.
2. **Ground Truth Firewall**: `field.plants.TrueDisease` is never used by the classifier or orchestrator to select treatment targets. Post-mission scoring against truth labels is for diagnostic evaluation only.
3. **Execution Status**: Python bridge tests have been executed live and verified locally. MATLAB tests remain marked **PENDING** until executed within an active MATLAB Desktop or Online session.
