%% INTERNAL-2 EXPERIMENTAL DRIVER  (Experiment E: integrated end-to-end mission)
% Deterministic comparison on a trapezoidal field with gently curved rows:
%   1. Baseline              : wind OFF, PID OFF, compensation OFF  (ideal reference)
%   2. No wind + PID         : wind OFF, PID ON,  compensation OFF  (control: controller effect alone)
%   3. Disturbed             : wind ON,  PID OFF, compensation OFF  (open-loop)
%   4. Navigation Corrected  : wind ON,  PID ON,  compensation OFF  (isolates the PID effect)
%   5. Fully Corrected       : wind ON,  PID ON,  compensation ON   (PID + upwind spray offset)
% These names are presets (scenarioPresets.m): labels for switch settings, edited in
% cfg.experiments.E.scenarios in config.m.
%
% Runs with wind use the IDENTICAL wind vector, field, ground truth and detection
% draws; only the switches differ. Nothing in this script draws random
% numbers (field truth/detection use a private seeded stream), so repeated
% runs give identical numbers (checked at the end).
%
% The controlled sweeps that justify this demo (Experiments A-D) live in
% main_experiments.m. The simulation logic is in runExperimentE.m.
%
% HOW TO RUN: type main_internal2
%
% IMPORTANT LIMITS (also printed at the end):
%   - Estimated position == ground truth (getEstimatedState passthrough).
%     GPS-independent localization is NOT implemented in this driver.
%   - Pass-1 detection is a parametric stand-in (assumed rates), not the CNN.
%   - Spray deposition is a simplified relative model, not CFD, not validated.
%   - Every physical constant is an [ASSUMED] placeholder in config.m.
%   - PID OFF = open-loop reference-velocity feed-forward (no position feedback).

clear; clc; close all;

cfgBase = config();
cfgBase.internal2.enabled = true;

field = generateIrregularField(cfgBase);

E = runExperimentE(cfgBase, field);

plotInternal2(cfgBase, field, E.runs, E.mets);

fprintf('\n--- LIMITS OF THIS DEMO ---\n');
fprintf('* Estimated position equals ground truth (getEstimatedState passthrough): NO GPS-independent localization is claimed.\n');
fprintf('* Pass-1 detection uses assumed detection/false-positive rates, not the trained CNN.\n');
fprintf('* Spray deposition is a simplified relative model (not CFD, not validated). Compare runs; do not read absolute values.\n');
fprintf('* No parameter here is literature- or experimentally-validated.\n');
