function assignRealPlantImages(cfg, plants)
%ASSIGNREALPLANTIMAGES Replace synthetic placeholder plant images with
%   REAL leaf photos sampled from your dataset's test set.
%
%   assignRealPlantImages(cfg, plants) overwrites every plant's image
%   file (cfg.imageRoot/P###.jpg) with a randomly chosen real leaf photo
%   from dataset/test/healthy or dataset/test/diseased.
%
%   IMPORTANT: this does NOT claim these are real drone photos of these
%   specific simulated field plants - there is no real field footage in
%   this prototype. It substitutes genuine tomato-leaf photographs (with
%   known ground truth) so REAL ML MODE classifies real image data
%   instead of the random-noise placeholders from generateDemoImages.m.
%   This is what makes the Real ML Mode results meaningful to report.

    healthyDir  = fullfile(cfg.datasetRoot, 'test', 'healthy');
    diseasedDir = fullfile(cfg.datasetRoot, 'test', 'diseased');

    healthyFiles  = dir(fullfile(healthyDir, '*.jpg'));
    diseasedFiles = dir(fullfile(diseasedDir, '*.jpg'));

    if isempty(healthyFiles) || isempty(diseasedFiles)
        error('assignRealPlantImages:noImages', ...
            'No test images found under %s or %s. Run setupDataset first.', ...
            healthyDir, diseasedDir);
    end

    fprintf('Assigning real leaf photos to %d simulated plants...\n', height(plants));

    for i = 1:height(plants)
        destPath = char(plants.ImagePath(i));

        % Randomly assign healthy or diseased leaf photo (roughly 50/50,
        % independent of any "true" label - the point is realistic image
        % INPUT statistics for the model to classify, not a scripted answer).
        if rand() < 0.5
            src = healthyFiles(randi(numel(healthyFiles)));
        else
            src = diseasedFiles(randi(numel(diseasedFiles)));
        end

        srcPath = fullfile(src.folder, src.name);
        copyfile(srcPath, destPath);
    end

    fprintf('Done. Real leaf photos copied into: %s\n', cfg.imageRoot);
    fprintf('Re-run main_stage4 now to see meaningful REAL ML MODE predictions.\n');
end
