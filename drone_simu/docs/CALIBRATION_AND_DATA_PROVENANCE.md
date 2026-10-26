# Calibration and data provenance

**Bottom line: nothing in this simulator is calibrated against real measurements.**
- Every sensor, hardware, spray and detector value is a synthetic assumption, marked `[ASSUMED]` in `config.m`.
- The exceptions are a few values inherited from earlier project code, marked `[EXISTING]`. Those are also not measured.
- Results are **relative comparisons inside the model**. No real-world validation is claimed.

| Area | Status | Where the numbers come from | What would calibrate it |
|---|---|---|---|
| Detector (perception) | **SYNTHETIC** | Parametric: P(detect \| diseased, imaged) 0.95, P(false positive) 0.03. Fixed per-plant random draws (`detectPlants.m`) | The teammate CNN with images and labels (`cnnAvailability.m` lists what is missing) |
| Camera footprint | SYNTHETIC | `cameraFovRadius` 0.6 m; altitude model `[ASSUMED]` | Camera FOV and altitude from the airframe |
| IMU / optical flow / LiDAR (sensorFusion) | **SYNTHETIC** | `config.m`, `enhancements.localization`: accel noise 0.05 m/s², bias 0.005 m/s², flow noise 0.05 m/s, scale error 1 %, dropout 5 %, LiDAR 0.05 m at 1 Hz within 25 m. Landmarks are the field corner posts at exactly known positions | Sensor datasheets plus logged flight data with ground truth (RTK) to fit noise, bias and dropout |
| Vehicle / hardware | **SYNTHETIC** | `profiles/assumedDefault.json`: every parameter has `sourceType: synthetic`. Dry mass 5 kg, tank 2 L, thrust/weight 2.0, battery 222 Wh, rotor disk 0.45 m², efficiency 0.6 | Sourced profiles: copy `profiles/TEMPLATE_sourced_profile.json.txt`. A manufacturer or literature value without a citation is rejected (`hardwareProfile:uncited`) |
| Spray deposition kernel | **UNCALIBRATED** | Circular Gaussian, σ = 0.5 × footprint radius (release height 1 m, 15° half-angle); droplet fall speed 1.5 m/s; drift factor 1.0; wind-stretched ellipse 0.3 per m/s | A deposition / drift dataset (crop, nozzle, VMD, height, speed, crosswind, measurement method), fitted on a calibration subset and validated on a held-out subset. The `calibrated` kernel stays UNAVAILABLE until then |
| Spray sensitivity | Bounded study | `results/spray_uncalibrated_v1/summary.md`, with bounds assumed around the defaults | — |
| Atmosphere / evaporation | SYNTHETIC | 30 °C, 50 % RH, VMD 250 µm, downwash factor 0.1 | Measurements or a sourced evaporation model |
| Wind / gusts | SYNTHETIC | Steady wind plus seeded zero-mean gusts (σ 0.5 m/s per axis by default) | On-site anemometer logs |
| Field / crop | SYNTHETIC | Trapezoid or rectangle or UShape; curved rows 2 m apart, plants 0.5 m; 15 % diseased; canopy radius 0.2 m | Field survey and crop geometry |
| Valve delay | SYNTHETIC | 0.5 s default (`actuation.valveDelay_s`), same order as reported PWM lag but not measured | Bench measurement of the pump and valve |

## What the bounded spray study supports, and what it does not

**Supports:**
- Within the stated bounds, wind compensation improves target deposition in 30 of 30 parameter cells, so the *direction* is robust.
- The compensator knows the true drift parameters, so the benefit *magnitudes* (+19 to +78 pp) are upper bounds and must not be quoted as physical numbers.

**Valve delay, by release mode:**
- Stopped release, 0.5 s delay: −9.7 pp deposition.
- Moving release at 1.5 m/s, 0.5 s delay: −28.5 pp canopy capture (kernel level).
- Lag compensation with a known delay restores the zero-delay result in both cases.

**Does not support:**
- Any absolute deposition percentage.
- Any claim of real-world spray efficacy.
- Any claim about "plant recovery".

## Data that was requested but not supplied

1. CNN:
   - trained model `dataset/diseaseModel.mat`,
   - images `dataset/plant_images`,
   - plant-to-image linkage for the Internal-2 field,
   - class mapping and preprocessing specification, model version and licence.
2. Deposition / drift measurements with metadata (manual M4).
3. Datasheets for at least two real airframes, sprayers and sensors (manual M5).
4. Crop canopy and row geometry for the target crop.
