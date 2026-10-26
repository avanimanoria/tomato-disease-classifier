%% PESTICIDE CAPACITY CALCULATOR - DEMO
% Shows how to call calculatePesticideCapacity.m using example mission
% numbers (taken from an actual Stage 7 run of this project). Replace
% the numbers below with YOUR dashboard's "Mission Stats" / "Severity"
% tab values after a real run to get a report for your own field size.
%
% HOW TO RUN: type main_pesticideCapacity

clear; clc;

cfg = config();
fieldInfo = generateField(cfg); % uses your current config.m field size

% --- EDIT THESE to match a real run's results ---
% (example values shown are from an actual Stage 7 console run)
diseasedCount = 109;
severityCounts.mild     = 0;
severityCounts.moderate = 4;
severityCounts.severe   = 105;

% --- run with default assumptions ---
report = calculatePesticideCapacity(fieldInfo, diseasedCount, severityCounts); %#ok<NASGU>

% --- example: override an assumption, e.g. a larger tank ---
% customParams.tankCapacity_L = 5;
% report2 = calculatePesticideCapacity(fieldInfo, diseasedCount, severityCounts, customParams);
