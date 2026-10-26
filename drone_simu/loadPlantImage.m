function img = loadPlantImage(imagePath)
%LOADPLANTIMAGE Load the actual image file for a plant (Section 10/33).
%
%   img = loadPlantImage(imagePath) reads the image from disk. This is
%   the real image-loading step the spec requires - later, detectDisease
%   (Stage 4) will feed this img into the ML model.

    imagePath = char(imagePath);

    if ~isfile(imagePath)
        error('loadPlantImage:missingFile', ...
            'Plant image not found: %s', imagePath);
    end

    try
        img = imread(imagePath);
    catch ME
        error('loadPlantImage:unreadable', ...
            'Could not read image (unsupported format?): %s\n%s', ...
            imagePath, ME.message);
    end
end
