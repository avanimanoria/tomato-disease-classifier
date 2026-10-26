function out = runHeadlessTwoPass(configJsonPath)
%RUNHEADLESSTWOPASS Two-pass headless mission runner.
%
%   out = runHeadlessTwoPass(configJsonPath)
%
%   PASS 1: Survey navigation (runSurveyPass + detectPlants).
%     Exports survey_data.json containing the full trajectory, per-plant
%     observation timestamps, and image assignment stubs.
%     Sets awaiting_classification=true to indicate Python should classify.
%
%   PASS 2: Treatment flight (runTreatmentPass with per-target durations).
%     Waits for treatment_targets.json written by the Python orchestrator.
%     Exports treatment_data.json with leg-level spray accounting.
%
%   INPUT:
%     configJsonPath: path to JSON with fields:
%       mission_id, field_length, field_width, drone_speed (opt, default 1.5)
%
%   ZERO-EDIT PROTECTION:
%     Reads drone_simu/ functions without modifying any files.
%     No changes to software_model/.

    if nargin < 1 || isempty(configJsonPath)
        error('runHeadlessTwoPass:noConfig', 'A path to config JSON is required.');
    end
    if ~exist(configJsonPath, 'file')
        error('runHeadlessTwoPass:configNotFound', 'Config file not found: %s', configJsonPath);
    end

    fprintf('=================================================================\n');
    fprintf('[MATLAB 2-Pass] Loading config: %s\n', configJsonPath);

    fid = fopen(configJsonPath, 'r');
    if fid < 0
        error('runHeadlessTwoPass:openFailed', 'Cannot open config: %s', configJsonPath);
    end
    rawText = fread(fid, '*char')';
    fclose(fid);
    cfgIn = jsondecode(rawText);

    % Required fields
    reqFields = {'mission_id', 'field_length', 'field_width'};
    for ri = 1:numel(reqFields)
        if ~isfield(cfgIn, reqFields{ri})
            error('runHeadlessTwoPass:missingField', 'Missing required field: %s', reqFields{ri});
        end
    end

    missionId   = char(string(cfgIn.mission_id));
    fieldLength = double(cfgIn.field_length);
    fieldWidth  = double(cfgIn.field_width);
    droneSpeed  = 1.5;
    if isfield(cfgIn, 'drone_speed')
        droneSpeed = double(cfgIn.drone_speed);
    end

    % Output directory is the same folder as configJsonPath
    outputDir = fileparts(configJsonPath);
    if isempty(outputDir)
        outputDir = pwd;
    end

    fprintf('[MATLAB 2-Pass] Mission ID: %s | %.1fm x %.1fm | %.1fm/s\n', ...
            missionId, fieldLength, fieldWidth, droneSpeed);

    %% 1. Build configuration via uiToConfig (same pattern as runHeadlessSurvey)
    baseCfg = config();
    s = struct();
    s.wind        = false;
    s.pid         = false;
    s.comp        = false;
    s.windSpeed   = 0.0;
    s.windDirDeg  = 90.0;
    s.droneSpeed  = droneSpeed;
    s.rowSpacing  = baseCfg.rowSpacing;
    s.plantSpacing = baseCfg.plantSpacing;
    s.routing     = 'nearestNeighbour';
    s.rowStyle    = 'Straight';
    s.shape       = 'Rectangle';
    s.rect        = struct('length', fieldLength, 'width', fieldWidth);

    c = uiToConfig(s);
    c.internal2.enabled = true;
    c.fieldLength = fieldLength;
    c.fieldWidth  = fieldWidth;

    dt = c.dt;

    %% 2. Pass 1 – Survey flight
    fprintf('[MATLAB 2-Pass] Generating field...\n');
    field = generateIrregularField(c);

    fprintf('[MATLAB 2-Pass] Executing survey flight pass...\n');
    sv = runSurveyPass(c, field);

    fprintf('[MATLAB 2-Pass] Evaluating plant camera coverage...\n');
    [~, seen, firstStep] = detectPlants(field, sv.log1, c);

    nPlants = height(field.plants);
    nSteps  = size(sv.log1.truePos, 1);

    fprintf('[MATLAB 2-Pass] Survey complete: %d plants, %d steps, %.1fs flight\n', ...
            nPlants, nSteps, sv.time);

    %% 3. Build plant list (convert firstStep indices to timestamps)
    plantsCell = cell(nPlants, 1);
    for p = 1:nPlants
        pid = char(string(field.plants.ID(p)));
        if seen(p)
            obsT = sv.log1.t(firstStep(p));
        else
            obsT = NaN;
        end
        plantsCell{p} = struct(...
            'plant_id',      pid, ...
            'plant_idx',     p, ...
            'x',             round(field.plants.X(p), 3), ...
            'y',             round(field.plants.Y(p), 3), ...
            'row',           double(field.plants.RowIdx(p)), ...
            'seen',          logical(seen(p)), ...
            'first_step',    double(firstStep(p)), ...
            'obs_timestamp', obsT);
    end

    %% 4. Build survey trajectory steps
    stepsCell = cell(nSteps, 1);
    lastHeading = 90.0;
    cumDist = 0.0;
    for k = 1:nSteps
        px = sv.log1.truePos(k, 1);
        py = sv.log1.truePos(k, 2);
        if k > 1
            stepDist = norm(sv.log1.truePos(k, :) - sv.log1.truePos(k-1, :));
            cumDist  = cumDist + stepDist;
            dx = px - sv.log1.truePos(k-1, 1);
            dy = py - sv.log1.truePos(k-1, 2);
            if norm([dx, dy]) > 0.001
                lastHeading = mod(atan2d(dy, dx), 360);
            end
        end
        stepsCell{k} = struct(...
            'step',            k, ...
            't',               round(sv.log1.t(k), 3), ...
            'x',               round(px, 3), ...
            'y',               round(py, 3), ...
            'ref_x',           round(sv.log1.refPos(k, 1), 3), ...
            'ref_y',           round(sv.log1.refPos(k, 2), 3), ...
            'heading',         round(lastHeading, 1), ...
            'speed',           round(norm(sv.log1.vCmd(k, :)), 2), ...
            'cross_track_m',   round(sv.log1.cross(k), 4), ...
            'cum_distance_m',  round(cumDist, 2), ...
            'phase',           double(sv.log1.phase(k)));
    end

    %% 5. Write survey_data.json atomically
    surveyOut = struct();
    surveyOut.mission_id            = missionId;
    surveyOut.provenance            = 'authoritative_matlab_navigation';
    surveyOut.mode                  = 'MATLAB simulation replay';
    surveyOut.pass                  = 'survey';
    surveyOut.generated_at          = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<TNOW1,DATST>
    surveyOut.field_dimensions      = struct('length', fieldLength, 'width', fieldWidth);
    surveyOut.field_polygon         = field.polygon;
    surveyOut.num_rows              = field.numRows;
    surveyOut.total_plants          = nPlants;
    surveyOut.survey_path_length    = round(field.surveyRef.len, 2);
    surveyOut.flight_time           = round(sv.time, 2);
    surveyOut.flight_distance       = round(sv.distance, 2);
    surveyOut.drone_speed           = droneSpeed;
    surveyOut.row_spacing           = c.rowSpacing;
    surveyOut.plant_spacing         = c.plantSpacing;
    surveyOut.dt                    = dt;
    surveyOut.reference_path        = round(field.surveyRef.pts, 3);
    surveyOut.plants                = plantsCell;
    surveyOut.telemetry_steps       = stepsCell;
    surveyOut.awaiting_classification = true;

    tmpSurvey   = fullfile(outputDir, 'survey_data.json.tmp');
    finalSurvey = fullfile(outputDir, 'survey_data.json');
    jsonStr = jsonencode(surveyOut);
    fid = fopen(tmpSurvey, 'w');
    if fid < 0
        error('runHeadlessTwoPass:writeFailed', 'Cannot write %s', tmpSurvey);
    end
    fwrite(fid, jsonStr, 'char');
    fclose(fid);
    movefile(tmpSurvey, finalSurvey);

    fprintf('[MATLAB 2-Pass] survey_data.json written: %d plants, %d steps -> %s\n', ...
            nPlants, nSteps, finalSurvey);

    %% 6. Poll for treatment_targets.json from Python orchestrator
    targetsFile = fullfile(outputDir, 'treatment_targets.json');
    abortFile   = fullfile(outputDir, 'abort.signal');
    maxWait     = 600;    % 10 minutes
    pollInterval = 0.5;   % seconds
    elapsed      = 0.0;

    fprintf('[MATLAB 2-Pass] Waiting for treatment_targets.json (max %ds)...\n', maxWait);
    while ~exist(targetsFile, 'file')
        pause(pollInterval);
        elapsed = elapsed + pollInterval;
        if elapsed >= maxWait
            error('runHeadlessTwoPass:timeout', ...
                  'Timed out waiting for treatment_targets.json after %ds.', maxWait);
        end
        if exist(abortFile, 'file')
            error('runHeadlessTwoPass:aborted', 'Mission aborted via abort.signal.');
        end
    end
    pause(0.1); % grace period for atomic writes

    fprintf('[MATLAB 2-Pass] treatment_targets.json received after %.1fs.\n', elapsed);

    %% 7. Read treatment targets from Python
    fid = fopen(targetsFile, 'r');
    if fid < 0
        error('runHeadlessTwoPass:readFailed', 'Cannot read %s', targetsFile);
    end
    tRaw = fread(fid, '*char')';
    fclose(fid);
    tData = jsondecode(tRaw);

    nT = numel(tData.targets);
    fprintf('[MATLAB 2-Pass] %d treatment target(s) received.\n', nT);

    %% 8. Prepare treatment output struct
    tpOut = struct();
    tpOut.mission_id              = missionId;
    tpOut.pass                    = 'treatment';
    tpOut.n_targets               = nT;
    tpOut.dt                      = dt;
    tpOut.flow_rate_mL_per_s      = c.internal2.spray.flowRate;

    if nT == 0
        fprintf('[MATLAB 2-Pass] No qualifying treatment targets. Skipping treatment flight.\n');
        tpOut.order          = [];
        tpOut.target_ids     = {};
        tpOut.treatment_legs = {};
        tpOut.routes = struct(...
            'actualDwellTime', 0.0, ...
            'actualFlightTime', 0.0, ...
            'actualTotalTime', 0.0, ...
            'actualDistance', 0.0);
    else
        %% 9. Build targets struct for runTreatmentPass
        XY        = zeros(nT, 2);
        durations = zeros(nT, 1);
        targetIds = cell(nT, 1);

        for j = 1:nT
            XY(j, 1)   = tData.targets(j).x;
            XY(j, 2)   = tData.targets(j).y;
            durations(j) = tData.targets(j).duration_s;
            targetIds{j} = char(string(tData.targets(j).plant_id));
        end

        tStruct.XY       = XY;
        tStruct.duration = durations;   % per-target, picked up by Stage A patch

        fprintf('[MATLAB 2-Pass] Executing treatment pass with %d target(s)...\n', nT);
        tp = runTreatmentPass(c, field, sv, tStruct);

        %% 10. Serialize treatment legs with per-leg accounting
        nLeg = numel(tp.legLogs);
        legsCell = cell(nLeg, 1);
        flowRate = c.internal2.spray.flowRate;

        for k = 1:nLeg
            leg = tp.legLogs{k};
            nls = numel(leg.t);
            legSteps = cell(nls, 1);
            lastH2   = 90.0;
            cumD2    = 0.0;

            for ls = 1:nls
                lx = leg.truePos(ls, 1);
                ly = leg.truePos(ls, 2);
                if ls > 1
                    ldx = lx - leg.truePos(ls-1, 1);
                    ldy = ly - leg.truePos(ls-1, 2);
                    cumD2 = cumD2 + norm([ldx, ldy]);
                    if norm([ldx, ldy]) > 0.001
                        lastH2 = mod(atan2d(ldy, ldx), 360);
                    end
                end
                legSteps{ls} = struct(...
                    'step',    ls, ...
                    't',       round(leg.t(ls), 3), ...
                    'x',       round(lx, 3), ...
                    'y',       round(ly, 3), ...
                    'heading', round(lastH2, 1), ...
                    'phase',   double(leg.phase(ls)));
            end

            nDwell  = sum(leg.phase == 3);
            nSettle = sum(leg.phase == 2);
            tIdx    = leg.targetIdx;   % scalar; NaN for refill legs

            if isnan(tIdx)
                % Refill or return leg
                legKind     = 'refill';
                if isfield(leg, 'legKind')
                    legKind = char(string(leg.legKind));
                end
                targetIdStr = 'none';
                reqDur      = 0.0;
                execDur     = nDwell * dt;
            else
                % Treatment approach leg: recover slot via tp.order
                legKind     = 'treatment';
                targetIdStr = targetIds{tIdx};
                reqDur      = durations(tIdx);
                execDur     = nDwell * dt;
            end

            emittedVol = nDwell * dt * flowRate;

            legsCell{k} = struct(...
                'leg_id',              k, ...
                'leg_kind',            legKind, ...
                'target_id',           targetIdStr, ...
                'target_idx',          tIdx, ...
                'requested_duration_s', reqDur, ...
                'executed_duration_s',  execDur, ...
                'n_dwell_steps',        nDwell, ...
                'n_settle_steps',       nSettle, ...
                'emitted_volume_mL',    emittedVol, ...
                'steps',               {legSteps});
        end

        tpOut.order          = tp.order;
        tpOut.target_ids     = targetIds;
        tpOut.treatment_legs = legsCell;
        tpOut.routes = struct(...
            'actualDwellTime',  round(tp.routes.actualDwellTime, 3), ...
            'actualFlightTime', round(tp.routes.actualFlightTime, 3), ...
            'actualTotalTime',  round(tp.routes.actualTotalTime, 3), ...
            'actualDistance',   round(tp.routes.actualDistance, 3));
    end

    %% 11. Write treatment_data.json atomically
    tmpT   = fullfile(outputDir, 'treatment_data.json.tmp');
    finalT = fullfile(outputDir, 'treatment_data.json');
    jsonStr2 = jsonencode(tpOut);
    fid = fopen(tmpT, 'w');
    if fid < 0
        error('runHeadlessTwoPass:writeFailed', 'Cannot write %s', tmpT);
    end
    fwrite(fid, jsonStr2, 'char');
    fclose(fid);
    movefile(tmpT, finalT);

    fprintf('[MATLAB 2-Pass] treatment_data.json written -> %s\n', finalT);
    fprintf('=================================================================\n');

    out.mission_id     = missionId;
    out.survey_file    = finalSurvey;
    out.treatment_file = finalT;
    out.status         = 'complete';
end
