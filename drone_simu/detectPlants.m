function [targets, seen, firstStep] = detectPlants(field, log, cfg, mode)
%DETECTPLANTS Image plants from TRUE positions and flag disease targets.
%
%   [targets, seen, firstStep] = detectPlants(field, log, cfg [, mode])
%
%   OBSERVATION (identical in every mode): a plant is imaged the first time
%   the camera footprint (radius cfg.cameraFovRadius, centred on the TRUE
%   position) covers it. A plant that never enters the footprint is
%   unobserved, hence undetected, in EVERY mode.
%
%   CLASSIFICATION of imaged plants (mode, default cfg.internal2.detect.mode):
%     'stochastic'     parametric stand-in: flag with probability
%                      pDetectDiseased / pFalsePositive using the plant's
%                      fixed draw field.detectU (identical across runs for any
%                      plant that was imaged).
%     'perfectVisible' perfect classification CONDITIONAL ON OBSERVATION: every
%                      imaged diseased plant is flagged, no imaged healthy plant
%                      is flagged. It does NOT grant knowledge of plants the
%                      camera never covered.
%
%   targets: plantIdx, ID, XY, detectTime, isTruePositive (ordered by first
%   imaging step, ties by plant index).

    if nargin < 4 || isempty(mode)
        mode = cfg.internal2.detect.mode;
    end
    P = field.plants;
    N = height(P);
    D = cfg.internal2.detect;
    R2 = cfg.cameraFovRadius^2;

    seen = false(N, 1);
    firstStep = zeros(N, 1);
    for k = 1:numel(log.t)
        d2 = (P.X - log.truePos(k, 1)).^2 + (P.Y - log.truePos(k, 2)).^2;
        newly = ~seen & d2 <= R2;
        firstStep(newly) = k;
        seen = seen | newly;
    end

    isDis = P.TrueDisease == "DISEASED";
    switch mode
        case 'stochastic'
            flagged = seen & ((isDis & field.detectU < D.pDetectDiseased) | ...
                              (~isDis & field.detectU < D.pFalsePositive));
        case 'perfectVisible'
            flagged = seen & isDis;
        otherwise
            error('detectPlants:badMode', 'Unknown detect mode "%s" (use stochastic | perfectVisible).', mode);
    end
    idx = find(flagged);
    [~, o] = sortrows([firstStep(idx), idx]);
    idx = idx(o);

    targets.plantIdx = idx;
    targets.ID = P.ID(idx);
    targets.XY = [P.X(idx), P.Y(idx)];
    targets.detectTime = log.t(firstStep(idx));
    targets.isTruePositive = isDis(idx);
end
