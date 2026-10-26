function [targets, seen, firstStep, provenance] = perceptionCNNAdapter(field, log, cfg) %#ok<STOUT,INUSD>
%PERCEPTIONCNNADAPTER Interface for the teammate CNN detector (NOT YET INTEGRATED).
%
%   [targets, seen, firstStep, provenance] = perceptionCNNAdapter(field, log, cfg)
%
%   Contract (same outputs as detectPlants, plus provenance):
%     seen / firstStep : geometric observation (camera footprint over the TRUE position,
%                        identical to detectPlants - visibility is separate from the model)
%     targets          : plants whose IMAGE the CNN classifies as diseased at the configured
%                        confidence threshold; fields plantIdx, ID, XY, detectTime,
%                        isTruePositive (scoring only), confidence
%     provenance       : model file + hash, version, class mapping, threshold, image paths
%   Requirements before this can run (see cnnAvailability): trained model artifact,
%   preprocessing spec, class mapping, licence, and a defined plant -> image linkage with
%   genuinely separated train/test images. Until then this FAILS CLOSED.
    [ok, reason] = cnnAvailability(cfg);
    if ~ok
        error('perceptionCNNAdapter:unavailable', 'Teammate CNN perception is UNAVAILABLE (%s).', reason);
    end
    error('perceptionCNNAdapter:notImplemented', 'CNN artifacts found but the adapter has not been implemented and validated yet.');
end
