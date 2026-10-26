function run = bridge_mission_orchestrator(cfg, field, opts)
%BRIDGE_MISSION_ORCHESTRATOR End-to-end Python-MATLAB mission orchestrator.
%
%   run = bridge_mission_orchestrator()
%   run = bridge_mission_orchestrator(cfg, field)
%   run = bridge_mission_orchestrator(cfg, field, opts)
%
%   WORKFLOW:
%     1. Executes Pass 1 survey flight (runSurveyPass) EXACTLY ONCE.
%     2. Gathers camera visibility observations via detectPlants(field, sv.log1, cfg).
%     3. Feeds images for observed plants to the Python tomato-disease bridge.
%     4. Constructs an AI-driven target set based strictly on model classification.
%     5. Executes Pass 2 treatment flight (runTreatmentPass) using the REUSED survey state.
%     6. Returns a standardized run struct with full telemetry and bridge metadata.
%
%   HONEST TARGET LOCALIZATION:
%     aiTargets.XY reuses simulated plant coordinates for flight simulation.
%     This does NOT demonstrate image-based target localization; it is labeled:
%     aiTargets.XY_source = 'true_simulated_plant_coordinates'.
%
%   FAIL-SAFE RULE:
%     Plants with failed inference, unknown class, or low confidence are NEVER sprayed.

    if nargin < 1 || isempty(cfg)
        cfg = config();
        cfg.internal2.enabled = true;
    end
    if nargin < 2 || isempty(field)
        field = generateIrregularField(cfg);
    end
    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    bridgeRoot = fileparts(mfilename('fullpath'));
    repoRoot   = fileparts(bridgeRoot);

    if ~isfield(opts, 'missionId'),     opts.missionId = ['mission_' datestr(now, 'yyyymmdd_HHMMSS')]; end %#ok<TNOW1,DATST>
    if ~isfield(opts, 'mode'),          opts.mode = 'rest'; end
    if ~isfield(opts, 'demoThreshold'), opts.demoThreshold = 0.60; end
    if ~isfield(opts, 'mapPath')
        opts.mapPath = fullfile(bridgeRoot, 'config', 'plant_image_map.json');
    end

    % Derived spray footprint
    cfg.internal2.spray.footprintRadius = ...
        cfg.internal2.spray.releaseHeight * tand(cfg.internal2.spray.nozzleHalfAngle);

    fprintf('=================================================================\n');
    fprintf('STARTING INTEGRATED PYTHON-MATLAB MISSION: %s\n', opts.missionId);
    fprintf('Bridge transport mode: %s | Demo threshold: %.2f\n', opts.mode, opts.demoThreshold);
    fprintf('=================================================================\n');

    %% Step 1: Execute Survey Pass (Pass 1) ONCE
    fprintf('[Pass 1] Executing survey reference flight...\n');
    sv = runSurveyPass(cfg, field);
    fprintf('[Pass 1] Completed. Flight time: %.1fs, Distance: %.1fm\n', sv.time, sv.distance);

    %% Step 2: Determine Observed Plants from Camera Footprint
    % detectPlants evaluates physical camera coverage (distance <= cameraFovRadius)
    [~, seen, firstStep] = detectPlants(field, sv.log1, cfg);
    obsIndices = find(seen);
    nObserved  = numel(obsIndices);
    fprintf('[Perception] Camera covered %d of %d plants in the field.\n', nObserved, height(field.plants));

    %% Step 3: Load Plant-to-Image Mapping (Evaluation / Test Mapping)
    imageMap = loadPlantImageMap(opts.mapPath, repoRoot);

    %% Step 4: Query Python Bridge for Observed Plants
    fprintf('[Perception] Querying Python bridge for %d observed plants...\n', nObserved);
    bridgePredictions = cell(nObserved, 1);
    targetFlags       = false(nObserved, 1);

    for k = 1:nObserved
        pIdx    = obsIndices(k);
        pID     = field.plants.ID(pIdx);
        pIDStr  = char(string(pID));
        keyName = ['k_' pIDStr];

        % Resolve image path
        if isfield(imageMap, keyName)
            imgPath = imageMap.(keyName).image_path;
            % Query bridge (REST or File IPC)
            res = matlab_bridge_client(imgPath, pIDStr, opts.missionId, opts);
        else
            % Unmapped plant ID: explicit fail-safe policy (no image mapped -> no spray)
            res = struct('mission_id', opts.missionId, 'request_id', sprintf('unmapped_%s', pIDStr), ...
                         'plant_id', pIDStr, 'status', 'error', 'predicted_class', 'unknown', ...
                         'confidence', NaN, 'class_probabilities', struct(), ...
                         'severity', struct(), 'spray_allowed', false, ...
                         'error', sprintf('Plant ID %s is unmapped: no leaf image associated', pIDStr));
        end
        bridgePredictions{k} = res;

        % Treatment decision rule
        if strcmp(res.status, 'success') && res.spray_allowed && ...
           ismember(res.predicted_class, {'early_blight', 'late_blight'}) && ...
           (res.confidence >= opts.demoThreshold)
            targetFlags(k) = true;
            fprintf('  Plant %s: [%s] conf=%.3f -> TARGET FOR TREATMENT\n', ...
                    pIDStr, res.predicted_class, res.confidence);
        else
            fprintf('  Plant %s: [%s] -> NO SPRAY (%s)\n', ...
                    pIDStr, res.predicted_class, res.status);
        end
    end

    %% Step 5: Construct AI Targets Struct
    targetIndices = obsIndices(targetFlags);
    nT = numel(targetIndices);

    % Order targets by first camera imaging step (matching detectPlants contract)
    if nT > 0
        [~, sortOrder] = sortrows([firstStep(targetIndices), targetIndices]);
        sortedIdx         = targetIndices(sortOrder);
        % Reorder bridge_decisions using the exact same permutation
        selectedDecisions = bridgePredictions(targetFlags);
        sortedDecisions   = selectedDecisions(sortOrder);
    else
        sortedIdx       = [];
        sortedDecisions = cell(0, 1);
    end

    aiTargets = struct();
    aiTargets.plantIdx         = sortedIdx;
    aiTargets.ID               = field.plants.ID(sortedIdx);
    aiTargets.XY               = [field.plants.X(sortedIdx), field.plants.Y(sortedIdx)];
    aiTargets.XY_source        = 'true_simulated_plant_coordinates'; % Explicit honest label
    aiTargets.detectTime       = sv.log1.t(firstStep(sortedIdx));
    % Diagnostic evaluation only: compare AI prediction against simulation ground truth
    aiTargets.isTruePositive   = (field.plants.TrueDisease(sortedIdx) == "DISEASED");
    aiTargets.bridge_decisions = sortedDecisions;

    fprintf('[Perception] AI target selection complete: %d treatment targets selected.\n', nT);

    %% Step 6: Execute Treatment Pass (Pass 2) Reusing Exact Survey State
    fprintf('[Pass 2] Executing treatment flight over %d targets...\n', nT);
    tp = runTreatmentPass(cfg, field, sv, aiTargets);
    fprintf('[Pass 2] Completed. Drift: [%.2f, %.2f] m\n', tp.driftTrue(1), tp.driftTrue(2));

    %% Step 7: Package Standard Mission Struct
    pass1.time     = sv.time;
    pass1.distance = sv.distance;

    run.name       = ['integrated_' opts.missionId];
    run.flags      = struct('wind', cfg.internal2.wind.enabled, ...
                            'pid', cfg.internal2.ctrl.enabled, ...
                            'compensate', cfg.internal2.spray.compensate);
    run.windVel    = tp.windVel;
    run.driftTrue  = tp.driftTrue;
    run.compVec    = tp.compVec;
    run.log1       = sv.log1;
    run.legLogs    = tp.legLogs;
    run.pass1      = pass1;
    run.seen       = seen;
    run.targets    = aiTargets;
    run.order      = tp.order;
    run.releasePts = tp.releasePts;
    run.grid       = tp.grid;
    run.routes     = tp.routes;
    run.startXY    = tp.startXY;
    run.finalWorld = tp.finalWorld;

    % Attach Bridge Integration Metadata
    run.bridge = struct();
    run.bridge.missionId       = opts.missionId;
    run.bridge.transportMode   = opts.mode;
    run.bridge.demoThreshold   = opts.demoThreshold;
    run.bridge.observedCount   = nObserved;
    run.bridge.targetCount     = nT;
    run.bridge.predictions     = bridgePredictions;

    fprintf('=================================================================\n');
    fprintf('MISSION COMPLETED SUCCESSFULLY: %s\n', opts.missionId);
    fprintf('=================================================================\n');
end

function mapStruct = loadPlantImageMap(jsonPath, repoRoot)
    mapStruct = struct();
    if exist(jsonPath, 'file')
        fid = fopen(jsonPath, 'r');
        raw = fread(fid, '*char')';
        fclose(fid);
        data = jsondecode(raw);
        fields = fieldnames(data);
        for i = 1:numel(fields)
            fn = fields{i};
            item = data.(fn);
            pIdStr = char(string(item.plant_id));
            relPath = item.image_path;
            entry = struct('plant_id', pIdStr, 'image_path', fullfile(repoRoot, relPath));
            mapStruct.(['k_' pIdStr]) = entry;
            if isfield(item, 'numeric_index')
                mapStruct.(['k_' num2str(item.numeric_index)]) = entry;
            end
        end
    end
end
