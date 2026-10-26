function createDatasetFolders(cfg)
%CREATEDATASETFOLDERS Create the expected dataset folder tree (Section 11).
%
%   createDatasetFolders(cfg) creates:
%     dataset/train/healthy/        dataset/train/diseased/
%     dataset/validation/healthy/   dataset/validation/diseased/
%     dataset/test/healthy/         dataset/test/diseased/
%
%   Run this ONCE now, so when your real dataset arrives you can just
%   drop images straight into the matching folders - no need to build
%   the folder structure by hand.

    subsets = {'train','validation','test'};
    classes = {'healthy','diseased'};

    for i = 1:numel(subsets)
        for j = 1:numel(classes)
            p = fullfile(cfg.datasetRoot, subsets{i}, classes{j});
            if ~exist(p, 'dir')
                mkdir(p);
            end
        end
    end

    fprintf('Dataset folder structure created under:\n  %s\n', cfg.datasetRoot);
    fprintf('Place HEALTHY plant photos into the "healthy" folders,\n');
    fprintf('and DISEASED plant photos into the "diseased" folders,\n');
    fprintf('splitting roughly 70%% train / 15%% validation / 15%% test.\n');
end
