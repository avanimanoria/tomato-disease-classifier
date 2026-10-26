function plants = generatePlants(cfg, fieldInfo)
%GENERATEPLANTS Create the plant list for the field (Section 4/30).
%
%   plants = generatePlants(cfg, fieldInfo) returns a MATLAB table, one
%   row per plant, using LOCAL coordinates (no GPS). Columns match the
%   data structure required by the spec: ID, X, Y, Disease, Confidence,
%   Severity, ImagePath, State, SprayStatus.

    numRows      = fieldInfo.numRows;
    plantsPerRow = fieldInfo.plantsPerRow;
    totalPlants  = numRows * plantsPerRow;

    ID          = strings(totalPlants,1);
    X           = zeros(totalPlants,1);
    Y           = zeros(totalPlants,1);
    Disease     = strings(totalPlants,1);
    Confidence  = zeros(totalPlants,1);
    Severity    = zeros(totalPlants,1);
    ImagePath   = strings(totalPlants,1);
    State       = strings(totalPlants,1);
    SprayStatus = strings(totalPlants,1);

    idx = 1;
    for r = 0:(numRows-1)
        yPos = r * cfg.rowSpacing;
        for c = 0:(plantsPerRow-1)
            xPos = c * cfg.plantSpacing;

            ID(idx)          = sprintf('P%03d', idx);
            X(idx)           = xPos;
            Y(idx)           = yPos;
            Disease(idx)     = "UNKNOWN";     % set by ML in Stage 4
            Confidence(idx)  = 0;
            Severity(idx)    = 0;
            ImagePath(idx)   = fullfile(cfg.imageRoot, ID(idx) + ".jpg");
            State(idx)       = "NOT_SEEN";    % state machine, Section 5
            SprayStatus(idx) = "NOT_SPRAYED"; % Section 26

            idx = idx + 1;
        end
    end

    plants = table(ID, X, Y, Disease, Confidence, Severity, ...
                   ImagePath, State, SprayStatus);
end
