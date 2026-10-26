function [ok, reason, info] = cnnAvailability(cfg)
%CNNAVAILABILITY Can the teammate CNN be used for Mission perception? (fail-closed check)
%
%   [ok, reason, info] = cnnAvailability([cfg])
%
%   Integration needs ALL of: a trained model file, its class mapping / preprocessing, and a
%   per-plant image linkage for the simulated field (the Internal-2 field has no images).
%   Until every item exists this returns ok = false and the UI shows the option as
%   UNAVAILABLE. Nothing here fabricates a model, images or predictions.
    if nargin < 1, cfg = config(); end
    info.modelFile = fullfile(cfg.datasetRoot, 'diseaseModel.mat');
    info.imageRoot = cfg.imageRoot;
    info.adapter = 'perceptionCNNAdapter.m (interface only)';
    missing = {};
    if ~isfile(info.modelFile), missing{end+1} = sprintf('trained model (%s)', info.modelFile); end
    if ~isfolder(info.imageRoot), missing{end+1} = sprintf('plant images (%s)', info.imageRoot); end
    missing{end+1} = 'plant-to-image linkage for the Internal-2 field (not defined)';
    missing{end+1} = 'class mapping / preprocessing specification from the model owner';
    ok = false;
    reason = ['missing: ' strjoin(missing, '; ')];
    info.missing = missing;
end
