function fieldInfo = generateField(cfg)
%GENERATEFIELD Compute field geometry and plant-count statistics.
%
%   fieldInfo = generateField(cfg) returns a struct describing the field,
%   with row count / plants-per-row / total plants CALCULATED from cfg
%   (Section 3: "Do NOT hard-code 200 plants").

    % ---- validation (Section 33: error handling) ----
    if cfg.fieldLength <= 0 || cfg.fieldWidth <= 0
        error('generateField:invalidSize', ...
            'Field length and width must be positive numbers.');
    end
    if cfg.rowSpacing <= 0 || cfg.rowSpacing > cfg.fieldWidth
        error('generateField:invalidRowSpacing', ...
            'Row spacing must be positive and not larger than field width.');
    end
    if cfg.plantSpacing <= 0 || cfg.plantSpacing > cfg.fieldLength
        error('generateField:invalidPlantSpacing', ...
            'Plant spacing must be positive and not larger than field length.');
    end

    fieldInfo.length       = cfg.fieldLength;
    fieldInfo.width        = cfg.fieldWidth;
    fieldInfo.rowSpacing   = cfg.rowSpacing;
    fieldInfo.plantSpacing = cfg.plantSpacing;
    fieldInfo.altitude     = cfg.flightAltitude;

    % ---- automatic calculations ----
    fieldInfo.numRows      = floor(cfg.fieldWidth  / cfg.rowSpacing) + 1;
    fieldInfo.plantsPerRow = floor(cfg.fieldLength / cfg.plantSpacing) + 1;
    fieldInfo.totalPlants  = fieldInfo.numRows * fieldInfo.plantsPerRow;

    % Rough estimated path length: N horizontal passes + (N-1) sideways moves
    fieldInfo.estimatedPathLength = fieldInfo.numRows * cfg.fieldLength ...
        + (fieldInfo.numRows - 1) * cfg.rowSpacing;

    fprintf('--- FIELD SUMMARY ---\n');
    fprintf('Field size        : %.1f m x %.1f m\n', fieldInfo.length, fieldInfo.width);
    fprintf('Rows              : %d\n', fieldInfo.numRows);
    fprintf('Plants per row    : %d\n', fieldInfo.plantsPerRow);
    fprintf('Total plants      : %d\n', fieldInfo.totalPlants);
    fprintf('Estimated path len: %.1f m\n', fieldInfo.estimatedPathLength);
end
