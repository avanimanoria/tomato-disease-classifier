function result = detectDisease(img, cfg)
%DETECTDISEASE Analyse a plant image and return a disease prediction.
%   (Section 12 / 32)
%
%   result = detectDisease(img, cfg) returns:
%     result.label      - "HEALTHY" or "DISEASED"
%     result.confidence - 0-100 (percent)
%
%   The mode is controlled ENTIRELY by cfg.USE_REAL_MODEL. Every other
%   file in the project calls this function the same way regardless of
%   mode - navigation code never needs to know which one is active.

    if cfg.USE_REAL_MODEL
        result = detectDiseaseReal(img, cfg);
    else
        result = detectDiseaseDemo();
    end
end

function result = detectDiseaseDemo()
%DETECTDISEASEDEMO  DEMO MODE - plausible fake prediction, NO real model.
%   Used only to test navigation/target/spray logic before a trained
%   model exists.

    if rand() < 0.15   % ~15% of plants come back "diseased" in demo runs
        result.label = "DISEASED";
        result.confidence = 70 + 25*rand();   % 70-95%
    else
        result.label = "HEALTHY";
        result.confidence = 75 + 24*rand();   % 75-99%
    end
end

function result = detectDiseaseReal(img, cfg)
%DETECTDISEASEREAL  REAL ML MODE - uses the actual trained network.
%   Requires dataset/diseaseModel.mat to exist (run trainDiseaseModel.m
%   first). Loaded once and cached for the rest of the session.

    persistent net inputSize
    if isempty(net)
        net = loadDiseaseModel(cfg);
        try
            inputSize = net.Layers(1).InputSize;
        catch
            inputSize = [224 224 3]; % sensible fallback
        end
    end

    imgResized = imresize(img, inputSize(1:2));
    if size(imgResized,3) == 1
        imgResized = repmat(imgResized, 1, 1, 3); % grayscale -> RGB
    end

    [label, scores] = classify(net, imgResized);
    result.label = upper(string(label));
    result.confidence = 100 * max(scores);
end
