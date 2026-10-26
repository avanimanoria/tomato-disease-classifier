function net = loadDiseaseModel(cfg)
%LOADDISEASEMODEL Load the trained disease-detection network (Section 33).

    modelPath = fullfile(cfg.datasetRoot, 'diseaseModel.mat');

    if ~isfile(modelPath)
        error('loadDiseaseModel:missingModel', ...
            ['Real ML mode requires a trained model, but none was found at:\n  %s\n' ...
             'Run trainDiseaseModel.m first, or set cfg.USE_REAL_MODEL = false ' ...
             'in config.m to use Demo Mode instead.'], modelPath);
    end

    loaded = load(modelPath, 'net');
    if ~isfield(loaded, 'net')
        error('loadDiseaseModel:corruptModel', ...
            'File %s does not contain a variable named "net".', modelPath);
    end

    net = loaded.net;
end
