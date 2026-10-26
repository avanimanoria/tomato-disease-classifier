function setupDataset(sourceRoot, cfg)
%SETUPDATASET Reorganize a downloaded class-folder dataset (e.g. the
%   Kaggle "tomatoleaf" dataset) into this project's
%   dataset/train|validation|test/healthy|diseased structure.
%
%   setupDataset(sourceRoot, cfg)
%
%   sourceRoot must be the folder that directly contains "train" and
%   "val" subfolders, each of which contains one subfolder per disease
%   class (e.g. Tomato__healthy, Tomato__Bacterial_spot, ...).
%
%   Example:
%     cfg = config();
%     setupDataset('C:\Users\user\OneDrive\Desktop\tomato_dataset\tomato', cfg);
%
%   This MERGES train+val together per class, shuffles, and re-splits
%   70% train / 15% validation / 15% test, copying files into
%   cfg.datasetRoot. A folder is treated as "healthy" if its name
%   contains "healthy" (case-insensitive); every other class folder is
%   treated as "diseased" (Section 11: binary healthy/diseased dataset).

    rng(42); % fixed seed so the split is reproducible if re-run

    if ~isfolder(sourceRoot)
        error('setupDataset:missingSource', 'Source folder not found: %s', sourceRoot);
    end

    splitFolders = {'train','val'};
    imagePatterns = {'*.jpg','*.jpeg','*.png'}; % case-insensitive match on Windows

    %% Collect all image files per class, merging train + val
    classMap = containers.Map();

    for s = 1:numel(splitFolders)
        splitPath = fullfile(sourceRoot, splitFolders{s});
        if ~isfolder(splitPath)
            fprintf('Note: %s not found, skipping.\n', splitPath);
            continue;
        end

        classFolders = dir(splitPath);
        classFolders = classFolders([classFolders.isdir] & ~ismember({classFolders.name}, {'.','..'}));

        for c = 1:numel(classFolders)
            className = classFolders(c).name;
            classPath = fullfile(splitPath, className);

            files = [];
            for p = 1:numel(imagePatterns)
                files = [files; dir(fullfile(classPath, imagePatterns{p}))]; %#ok<AGROW>
            end
            fullPaths = unique(fullfile({files.folder}, {files.name}));

            if isKey(classMap, className)
                classMap(className) = unique([classMap(className), fullPaths]);
            else
                classMap(className) = fullPaths;
            end
        end
    end

    classNames = keys(classMap);
    if isempty(classNames)
        error('setupDataset:noClasses', 'No class folders found under %s\\train or \\val', sourceRoot);
    end

    fprintf('Found %d classes:\n', numel(classNames));
    for i = 1:numel(classNames)
        fprintf('  %-50s %d images\n', classNames{i}, numel(classMap(classNames{i})));
    end

    %% Prepare destination folders
    createDatasetFolders(cfg);

    totalHealthy = 0;
    totalDiseased = 0;

    %% Split and copy each class
    for i = 1:numel(classNames)
        className = classNames{i};
        files = classMap(className);
        files = files(randperm(numel(files))); % shuffle

        n = numel(files);
        nTrain = round(0.70 * n);
        nVal   = round(0.15 * n);
        % remainder (n - nTrain - nVal) goes to test

        isHealthy = contains(lower(className), 'healthy');
        if isHealthy
            label = 'healthy';
            totalHealthy = totalHealthy + n;
        else
            label = 'diseased';
            totalDiseased = totalDiseased + n;
        end

        splitNames = {'train','validation','test'};
        idxRanges  = {1:nTrain, (nTrain+1):(nTrain+nVal), (nTrain+nVal+1):n};

        for sIdx = 1:3
            destDir = fullfile(cfg.datasetRoot, splitNames{sIdx}, label);
            idxs = idxRanges{sIdx};
            for k = idxs
                srcFile = files{k};
                [~, name, ext] = fileparts(srcFile);
                % prefix with class name to avoid filename collisions
                % between classes (e.g. two classes both having "1.JPG")
                destFile = fullfile(destDir, sprintf('%s_%s%s', className, name, ext));
                copyfile(srcFile, destFile);
            end
        end
    end

    fprintf('\nDone reorganizing dataset.\n');
    fprintf('Total healthy images  : %d\n', totalHealthy);
    fprintf('Total diseased images : %d\n', totalDiseased);
    fprintf('Copied into: %s\n', cfg.datasetRoot);
    fprintf('You can now run: trainDiseaseModel\n');
end
