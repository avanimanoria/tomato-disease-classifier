%% TRAINDISEASEMODEL
% Standalone script - run this ONCE, SEPARATELY from the drone
% simulation, AFTER you have placed your real dataset into:
%   dataset/train/healthy/        dataset/train/diseased/
%   dataset/validation/healthy/   dataset/validation/diseased/
%   dataset/test/healthy/         dataset/test/diseased/
%
% (Run createDatasetFolders(config()) first if those folders don't
% exist yet - see Stage 4 instructions.)
%
% REQUIRES: Deep Learning Toolbox.
%
% HOW TO RUN:
%   Type: trainDiseaseModel
%
% OUTPUT:
%   Saves dataset/diseaseModel.mat containing the trained network as
%   variable "net". detectDisease.m loads this automatically once you
%   set cfg.USE_REAL_MODEL = true in config.m.

clear; clc; close all;
cfg = config();

trainDir = fullfile(cfg.datasetRoot, 'train');
valDir   = fullfile(cfg.datasetRoot, 'validation');
testDir  = fullfile(cfg.datasetRoot, 'test');

folders = {trainDir, valDir, testDir};
for i = 1:numel(folders)
    if ~isfolder(folders{i})
        error('trainDiseaseModel:missingFolder', ...
            ['Expected folder not found: %s\n' ...
             'Run createDatasetFolders(config()) first, then add your images.'], folders{i});
    end
end

if exist('trainNetwork', 'file') ~= 2
    error('trainDiseaseModel:missingToolbox', ...
        'Deep Learning Toolbox does not appear to be installed. Install it via Home > Add-Ons > Get Add-Ons.');
end

%% Load datasets
imdsTrain = imageDatastore(trainDir, 'IncludeSubfolders', true, 'LabelSource', 'foldernames');
imdsVal   = imageDatastore(valDir,   'IncludeSubfolders', true, 'LabelSource', 'foldernames');
imdsTest  = imageDatastore(testDir,  'IncludeSubfolders', true, 'LabelSource', 'foldernames');

fprintf('Training images   : %d\n', numel(imdsTrain.Files));
fprintf('Validation images : %d\n', numel(imdsVal.Files));
fprintf('Test images        : %d\n', numel(imdsTest.Files));

if numel(imdsTrain.Files) == 0
    error('trainDiseaseModel:emptyDataset', 'No training images found in %s', trainDir);
end

classNames = categories(imdsTrain.Labels);
fprintf('Classes found: %s\n', strjoin(cellstr(classNames), ', '));

if ~isequal(sort(classNames), sort({'diseased';'healthy'}))
    warning(['Expected exactly two classes named "healthy" and "diseased" ' ...
             '(from your folder names). Found: %s'], strjoin(cellstr(classNames), ', '));
end

%% Balance classes (avoid a model that just always predicts the majority class)
fprintf('\nClass balance BEFORE balancing:\n');
disp(countEachLabel(imdsTrain));

minCountTrain = min(countEachLabel(imdsTrain).Count);
imdsTrain = splitEachLabel(imdsTrain, minCountTrain, 'randomize');

minCountVal = min(countEachLabel(imdsVal).Count);
imdsVal = splitEachLabel(imdsVal, minCountVal, 'randomize');

minCountTest = min(countEachLabel(imdsTest).Count);
imdsTest = splitEachLabel(imdsTest, minCountTest, 'randomize');

fprintf('Class balance AFTER balancing (train set):\n');
disp(countEachLabel(imdsTrain));

%% Pick a pretrained network based on what is actually installed
inputSize = [224 224 3];
baseNet = [];
netName = '';

if isempty(baseNet) && exist('resnet18', 'file') == 2
    try
        baseNet = resnet18();
        netName = 'ResNet-18';
    catch
    end
end

if isempty(baseNet) && exist('mobilenetv2', 'file') == 2
    try
        baseNet = mobilenetv2();
        netName = 'MobileNet-v2';
    catch
    end
end

useTransferLearning = ~isempty(baseNet);

if useTransferLearning
    fprintf('Using transfer learning with: %s\n', netName);
else
    fprintf('No supported pretrained network found (resnet18/mobilenetv2 add-ons not installed).\n');
    fprintf('Falling back to a small custom CNN trained from scratch.\n');
end

%% Preprocessing (resize + force RGB to match network input)
augTrain = augmentedImageDatastore(inputSize(1:2), imdsTrain, 'ColorPreprocessing','gray2rgb');
augVal   = augmentedImageDatastore(inputSize(1:2), imdsVal,   'ColorPreprocessing','gray2rgb');
augTest  = augmentedImageDatastore(inputSize(1:2), imdsTest,  'ColorPreprocessing','gray2rgb');

numClasses = numel(classNames);

%% Build the network
if useTransferLearning
    try
        lgraph = layerGraph(baseNet);
        layers = baseNet.Layers;

        fcIdx  = find(arrayfun(@(l) isa(l,'nnet.cnn.layer.FullyConnectedLayer'), layers), 1, 'last');
        clsIdx = find(arrayfun(@(l) isa(l,'nnet.cnn.layer.ClassificationOutputLayer'), layers), 1, 'last');

        newFC = fullyConnectedLayer(numClasses, 'Name','new_fc', ...
            'WeightLearnRateFactor',10, 'BiasLearnRateFactor',10);
        lgraph = replaceLayer(lgraph, layers(fcIdx).Name, newFC);

        newCls = classificationLayer('Name','new_output');
        lgraph = replaceLayer(lgraph, layers(clsIdx).Name, newCls);

        netLayers = lgraph;
    catch ME
        warning('Transfer learning setup failed (%s). Falling back to a custom CNN.', ME.message);
        useTransferLearning = false;
    end
end

if ~useTransferLearning
    netLayers = [
        imageInputLayer(inputSize)

        convolution2dLayer(3,8,'Padding','same')
        batchNormalizationLayer
        reluLayer
        maxPooling2dLayer(2,'Stride',2)

        convolution2dLayer(3,16,'Padding','same')
        batchNormalizationLayer
        reluLayer
        maxPooling2dLayer(2,'Stride',2)

        convolution2dLayer(3,32,'Padding','same')
        batchNormalizationLayer
        reluLayer

        fullyConnectedLayer(numClasses)
        softmaxLayer
        classificationLayer];
end

%% Training options
options = trainingOptions('adam', ...
    'InitialLearnRate', 1e-4, ...
    'MaxEpochs', 10, ...
    'MiniBatchSize', 16, ...
    'ValidationData', augVal, ...
    'ValidationFrequency', 10, ...
    'Verbose', true, ...
    'Plots', 'training-progress');

%% Train
fprintf('Starting training...\n');
net = trainNetwork(augTrain, netLayers, options);

%% Evaluate on the held-out test set
evaluateDiseaseModel(net, augTest, imdsTest.Labels, classNames);

%% Save
modelPath = fullfile(cfg.datasetRoot, 'diseaseModel.mat');
save(modelPath, 'net');
fprintf('\nModel saved to: %s\n', modelPath);
fprintf('Set cfg.USE_REAL_MODEL = true in config.m to start using it.\n');
