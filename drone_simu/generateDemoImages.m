function generateDemoImages(cfg, plants)
%GENERATEDEMOIMAGES Create placeholder image files for every plant.
%
%   generateDemoImages(cfg, plants) writes a small synthetic JPG for each
%   plant's ImagePath, ONLY if that file doesn't already exist.
%
%   IMPORTANT: these are NOT real plant photos. They exist purely so
%   Stage 3 can test the actual-file-loading pipeline (open file, read
%   bytes, get an image matrix) before you have a real disease dataset.
%   When you add your real dataset (Section 11 of the spec), replace the
%   files in cfg.imageRoot with real plant images named P001.jpg,
%   P002.jpg, etc. matching each plant's ID, and this function will
%   simply skip generating a placeholder for any file that already
%   exists.

    if ~exist(cfg.imageRoot, 'dir')
        mkdir(cfg.imageRoot);
    end

    numToGenerate = sum(~isfile(plants.ImagePath));
    if numToGenerate == 0
        fprintf('All plant images already exist in %s - nothing to generate.\n', cfg.imageRoot);
        return;
    end

    fprintf('Generating %d placeholder plant images (DEMO ONLY) in:\n  %s\n', ...
        numToGenerate, cfg.imageRoot);

    for i = 1:height(plants)
        imgPath = char(plants.ImagePath(i));
        if isfile(imgPath)
            continue; % don't overwrite existing (possibly real) images
        end

        % Deterministic pseudo-random base color per plant ID so images
        % differ from each other (just for visual variety in the demo).
        seed = double(sum(char(plants.ID(i))));
        rng(seed);
        baseColor = reshape(rand(1,3) * 255, 1, 1, 3);
        img = repmat(baseColor, 32, 32, 1);
        img = img + randn(32,32,3) * 8;      % small texture/noise
        img = uint8(min(255, max(0, img)));

        imwrite(img, imgPath);
    end

    fprintf('Done generating placeholder images.\n');
end
