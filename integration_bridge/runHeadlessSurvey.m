function out = runHeadlessSurvey(configJsonPath)
%RUNHEADLESSSURVEY Headless batch runner for authoritative MATLAB survey navigation.
%
%   out = runHeadlessSurvey(configJsonPath)
%
%   INPUT:
%     configJsonPath: Absolute or relative path to a JSON configuration file containing:
%       - mission_id   : Unique string identifier for the mission
%       - field_length : Rectangular field length (m, X direction, 6..60)
%       - field_width  : Rectangular field width (m, Y direction, 6..40)
%       - drone_speed  : Desired flight speed (m/s, 0.5..2.0)
%
%   OUTPUT:
%     Exports integration_bridge/io/mission_<id>/telemetry.json containing:
%       - field_dimensions, field_polygon
%       - plant coordinates, row indices, camera visibility
%       - reference survey path waypoints
%       - actual flight trajectory steps with timestamps, positions, headings, and cross-track errors
%
%   ZERO-EDIT PROTECTION:
%     Reads existing drone_simu/ functions without modifying any files.

    if nargin < 1 || isempty(configJsonPath)
        error('runHeadlessSurvey:noConfig', 'A path to config JSON is required.');
    end

    if ~exist(configJsonPath, 'file')
        error('runHeadlessSurvey:configNotFound', 'Config file not found: %s', configJsonPath);
    end

    fprintf('=================================================================\n');
    fprintf('[MATLAB Gateway] Loading mission configuration: %s\n', configJsonPath);
    fid = fopen(configJsonPath, 'r');
    if fid < 0
        error('runHeadlessSurvey:openFailed', 'Could not open config file: %s', configJsonPath);
    end
    rawText = fread(fid, '*char')';
    fclose(fid);
    cfgIn = jsondecode(rawText);

    % Validate required fields
    reqFields = {'mission_id', 'field_length', 'field_width'};
    for i = 1:numel(reqFields)
        if ~isfield(cfgIn, reqFields{i})
            error('runHeadlessSurvey:missingField', 'Missing required field: %s', reqFields{i});
        end
    end

    missionId   = char(string(cfgIn.mission_id));
    fieldLength = double(cfgIn.field_length);
    fieldWidth  = double(cfgIn.field_width);
    if isfield(cfgIn, 'drone_speed')
        droneSpeed = double(cfgIn.drone_speed);
    else
        droneSpeed = 1.5;
    end

    outputDir = fileparts(configJsonPath);
    if isempty(outputDir)
        outputDir = pwd;
    end

    fprintf('[MATLAB Gateway] Mission ID: %s | Dimensions: %.1fm x %.1fm | Speed: %.1fm/s\n', ...
            missionId, fieldLength, fieldWidth, droneSpeed);

    %% 1. Build authoritative configuration via uiToConfig
    baseCfg = config();
    s = struct();
    s.wind        = false;
    s.pid         = false;
    s.comp        = false;
    s.windSpeed   = 0.0;
    s.windDirDeg  = 90.0;
    s.droneSpeed  = droneSpeed;
    s.rowSpacing  = baseCfg.rowSpacing;
    s.plantSpacing= baseCfg.plantSpacing;
    s.routing     = 'nearestNeighbour';
    s.rowStyle    = 'Straight';
    s.shape       = 'Rectangle';
    s.rect        = struct('length', fieldLength, 'width', fieldWidth);

    c = uiToConfig(s);
    c.internal2.enabled = true;
    c.fieldLength       = fieldLength;
    c.fieldWidth        = fieldWidth;

    %% 2. Generate Field and Compute Survey Flight Pass
    fprintf('[MATLAB Gateway] Generating irregular/polygon field...\n');
    field = generateIrregularField(c);

    fprintf('[MATLAB Gateway] Executing authoritative survey flight pass...\n');
    sv = runSurveyPass(c, field);

    fprintf('[MATLAB Gateway] Evaluating plant camera coverage...\n');
    [~, seen, firstStep] = detectPlants(field, sv.log1, c);

    %% 3. Construct Export Payload
    out = struct();
    out.mission_id         = missionId;
    out.provenance         = 'authoritative_matlab_navigation';
    out.mode               = 'MATLAB simulation replay';
    out.generated_at       = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<TNOW1,DATST>
    out.field_dimensions   = struct('length', fieldLength, 'width', fieldWidth);
    out.field_polygon      = field.polygon;
    out.num_rows           = field.numRows;
    out.total_plants       = height(field.plants);
    out.survey_path_length = round(field.surveyRef.len, 2);
    out.flight_time        = round(sv.time, 2);
    out.flight_distance    = round(sv.distance, 2);
    out.drone_speed        = droneSpeed;
    out.row_spacing        = c.rowSpacing;
    out.plant_spacing      = c.plantSpacing;

    % Export plants
    nPlants = height(field.plants);
    plantsCell = cell(nPlants, 1);
    for p = 1:nPlants
        plantsCell{p} = struct(...
            'id', char(string(field.plants.ID(p))), ...
            'x', round(field.plants.X(p), 3), ...
            'y', round(field.plants.Y(p), 3), ...
            'row', double(field.plants.RowIdx(p)), ...
            'seen', logical(seen(p)), ...
            'first_step', double(firstStep(p)));
    end
    out.plants = plantsCell;

    % Export reference waypoints
    out.reference_path = round(field.surveyRef.pts, 3);

    % Export trajectory steps
    nSteps = size(sv.log1.truePos, 1);
    stepsCell = cell(nSteps, 1);
    lastHeading = 90.0;
    cumDist = 0.0;
    for k = 1:nSteps
        px = sv.log1.truePos(k, 1);
        py = sv.log1.truePos(k, 2);
        if k > 1
            stepDist = norm(sv.log1.truePos(k, :) - sv.log1.truePos(k-1, :));
            cumDist = cumDist + stepDist;
            dx = px - sv.log1.truePos(k-1, 1);
            dy = py - sv.log1.truePos(k-1, 2);
            if norm([dx, dy]) > 0.001
                lastHeading = mod(atan2d(dy, dx), 360);
            end
        end

        stepsCell{k} = struct(...
            'step', k, ...
            't', round(sv.log1.t(k), 3), ...
            'x', round(px, 3), ...
            'y', round(py, 3), ...
            'ref_x', round(sv.log1.refPos(k, 1), 3), ...
            'ref_y', round(sv.log1.refPos(k, 2), 3), ...
            'heading', round(lastHeading, 1), ...
            'speed', round(norm(sv.log1.vCmd(k, :)), 2), ...
            'cross_track_m', round(sv.log1.cross(k), 4), ...
            'cum_distance_m', round(cumDist, 2), ...
            'phase', double(sv.log1.phase(k)));
    end
    out.telemetry_steps = stepsCell;

    %% 4. Atomic Write to Disk
    tmpFile   = fullfile(outputDir, 'telemetry.json.tmp');
    finalFile = fullfile(outputDir, 'telemetry.json');

    jsonStr = jsonencode(out);
    fid = fopen(tmpFile, 'w');
    if fid < 0
        error('runHeadlessSurvey:writeFailed', 'Could not open %s for writing', tmpFile);
    end
    fwrite(fid, jsonStr, 'char');
    fclose(fid);
    movefile(tmpFile, finalFile);

    fprintf('[MATLAB Gateway] SUCCESS: Exported %d telemetry steps, %d plants, path length %.1fm to %s\n', ...
            nSteps, nPlants, out.survey_path_length, finalFile);
    fprintf('=================================================================\n');
end
