function res = matlab_bridge_client(imagePath, plantId, missionId, opts)
%MATLAB_BRIDGE_CLIENT Client for querying the Python tomato disease bridge.
%
%   res = matlab_bridge_client(imagePath, plantId)
%   res = matlab_bridge_client(imagePath, plantId, missionId, opts)
%
%   INPUTS:
%     imagePath : Path to the plant leaf image (relative to repo root or absolute).
%     plantId   : Identifier of the plant (integer, double, or string).
%     missionId : (Optional) Unique mission tag.
%     opts      : (Optional) Configuration options:
%                   opts.mode          : 'rest' (default) or 'file_ipc'
%                   opts.baseUrl       : URL for REST (default: 'http://127.0.0.1:5005')
%                   opts.timeout       : Timeout in seconds (default: 10.0)
%                   opts.ioDir         : Root of IO directory for file IPC
%                   opts.demoThreshold : Configurable demo confidence threshold (default: 0.60)
%
%   OUTPUT:
%     res : Struct containing:
%             status              : 'success' or 'error'
%             predicted_class     : 'early_blight' | 'healthy' | 'late_blight' | 'unknown'
%             confidence          : double in [0.0, 1.0] or NaN
%             class_probabilities : struct with class probabilities
%             severity            : struct with severity estimation details
%             spray_allowed       : logical (true only if diseased and confidence >= demoThreshold)
%             error               : char vector or []
%
%   FAIL-SAFE RULE:
%     Errors, timeouts, or invalid responses NEVER return 'healthy' or spray_allowed = true.
%     Failed inference explicitly returns 'unknown' with spray_allowed = false.

    if nargin < 3 || isempty(missionId)
        missionId = ['mission_matlab_' datestr(now, 'yyyymmdd_HHMMSS')]; %#ok<TNOW1,DATST>
    end
    if nargin < 4 || isempty(opts)
        opts = struct();
    end

    bridgeRoot = fileparts(mfilename('fullpath'));
    if ~isfield(opts, 'mode'),          opts.mode = 'rest'; end
    if ~isfield(opts, 'baseUrl'),       opts.baseUrl = 'http://127.0.0.1:5005'; end
    if ~isfield(opts, 'timeout'),       opts.timeout = 10.0; end
    if ~isfield(opts, 'ioDir'),         opts.ioDir = fullfile(bridgeRoot, 'io'); end
    if ~isfield(opts, 'demoThreshold'), opts.demoThreshold = 0.60; end
    if ~isfield(opts, 'verbose'),       opts.verbose = false; end

    % Generate unique request ID
    requestId = sprintf('req_%s_%06d', datestr(now, 'yyyymmdd_HHMMSS_FFF'), randi(999999)); %#ok<TNOW1,DATST>

    % Default fail-safe error template
    res = struct();
    res.mission_id          = missionId;
    res.request_id          = requestId;
    res.plant_id            = plantId;
    res.status              = 'error';
    res.predicted_class     = 'unknown';
    res.confidence          = NaN;
    res.class_probabilities = struct();
    res.severity            = struct('status', 'unavailable', 'affected_leaf_area_percent', NaN, 'band', []);
    res.spray_allowed       = false;
    res.error               = 'Uninitialized bridge response';

    switch lower(opts.mode)
        case 'rest'
            res = callRestBridge(imagePath, plantId, missionId, requestId, opts, res);
        case 'file_ipc'
            res = callFileIpcBridge(imagePath, plantId, missionId, requestId, opts, res);
        otherwise
            res.error = sprintf('Unsupported bridge mode "%s". Use "rest" or "file_ipc".', opts.mode);
    end
end

function res = callRestBridge(imagePath, plantId, missionId, requestId, opts, fallback)
    res = fallback;
    url = [rtrim(opts.baseUrl, '/') '/bridge/predict'];

    reqPayload = struct();
    reqPayload.mission_id = missionId;
    reqPayload.request_id = requestId;
    reqPayload.plant_id   = plantId;
    reqPayload.image_path = imagePath;

    try
        import matlab.net.*
        import matlab.net.http.*
        import matlab.net.http.io.*

        req = RequestMessage(RequestMethod.POST);
        req.Header = [HeaderField('Content-Type', 'application/json'), ...
                      HeaderField('Accept', 'application/json')];
        req.Body = MessageBody(jsonencode(reqPayload));

        uri = URI(url);
        httpOpts = HTTPOptions('ConnectTimeout', opts.timeout);
        response = req.send(uri, httpOpts);

        statusCode = double(response.StatusCode);
        bodyData = [];
        if ~isempty(response.Body) && ~isempty(response.Body.Data)
            bodyData = response.Body.Data;
        end

        % Extract structured JSON payload if present
        rawResp = [];
        if isstruct(bodyData)
            rawResp = bodyData;
        elseif ischar(bodyData) || (isstring(bodyData) && isscalar(bodyData))
            try
                rawResp = jsondecode(char(bodyData));
            catch
                rawResp = [];
            end
        elseif isa(bodyData, 'uint8')
            try
                rawResp = jsondecode(native2unicode(bodyData(:)', 'UTF-8'));
            catch
                rawResp = [];
            end
        end

        % Route valid structured bodies through identity validation & fail-safe parser
        if isstruct(rawResp) && isscalar(rawResp) && isfield(rawResp, 'status')
            res = parseBridgeResponse(rawResp, opts.demoThreshold, missionId, requestId, plantId, fallback);
        else
            % Unstructured or empty response (e.g. HTML 500 error page or transport error)
            res.status = 'error';
            res.predicted_class = 'unknown';
            res.confidence = NaN;
            res.severity = struct();
            res.spray_allowed = false;
            if statusCode >= 200 && statusCode < 300
                res.error = sprintf('REST bridge HTTP %d returned non-JSON payload', statusCode);
            else
                res.error = sprintf('REST bridge call failed: HTTP %d %s', statusCode, char(string(response.StatusCode)));
            end
        end

        if isfield(opts, 'verbose') && opts.verbose
            fprintf('  [REST Client] POST %s -> HTTP %d (%s)\n', url, statusCode, res.status);
            if strcmp(res.status, 'error')
                fprintf('  [REST Client] Rejection: %s (spray_allowed=%d)\n', res.error, res.spray_allowed);
            end
        end

    catch exc
        res.status        = 'error';
        res.predicted_class = 'unknown';
        res.confidence    = NaN;
        res.severity      = struct();
        res.spray_allowed = false;
        res.error         = sprintf('REST bridge call failed: %s', exc.message);
    end
end

function res = callFileIpcBridge(imagePath, plantId, missionId, requestId, opts, fallback)
    res = fallback;
    reqDir  = fullfile(opts.ioDir, 'requests');
    respDir = fullfile(opts.ioDir, 'responses');

    if ~exist(reqDir, 'dir'),  mkdir(reqDir);  end
    if ~exist(respDir, 'dir'), mkdir(respDir); end

    reqPayload = struct();
    reqPayload.mission_id = missionId;
    reqPayload.request_id = requestId;
    reqPayload.plant_id   = plantId;
    reqPayload.image_path = imagePath;

    tmpReqFile   = fullfile(reqDir, sprintf('req_%s_%s.tmp', missionId, requestId));
    finalReqFile = fullfile(reqDir, sprintf('req_%s_%s.json', missionId, requestId));
    respFile     = fullfile(respDir, sprintf('resp_%s_%s.json', missionId, requestId));

    try
        % Atomic write: write to .tmp then rename
        jsonStr = jsonencode(reqPayload);
        fid = fopen(tmpReqFile, 'w');
        if fid < 0, error('Cannot open file for writing: %s', tmpReqFile); end
        fwrite(fid, jsonStr, 'char');
        fclose(fid);
        movefile(tmpReqFile, finalReqFile);
        if isfield(opts, 'verbose') && opts.verbose
            fprintf('  [File IPC Client] Emitted request: %s (mission_id=%s, request_id=%s, plant_id=%s)\n', ...
                    finalReqFile, missionId, requestId, char(string(plantId)));
        end
        % Yield execution to allow pending callbacks/timers to service the new request file
        drawnow;
        pause(0.01);

        % Poll for response with bounded timeout
        tStart = tic;
        found = false;
        while toc(tStart) < opts.timeout
            if exist(respFile, 'file')
                pause(0.02); % Brief settle for file write completion
                try
                    fid = fopen(respFile, 'r');
                    if fid >= 0
                        raw = fread(fid, '*char')';
                        fclose(fid);
                        delete(respFile);
                        rawResp = jsondecode(raw);
                        res = parseBridgeResponse(rawResp, opts.demoThreshold, missionId, requestId, plantId, fallback);
                        found = true;
                        if isfield(opts, 'verbose') && opts.verbose
                            fprintf('  [File IPC Client] Consumed response: %s\n', respFile);
                            if strcmp(res.status, 'error')
                                fprintf('  [File IPC Client] Response rejected: %s (spray_allowed=%d)\n', ...
                                        res.error, res.spray_allowed);
                            else
                                fprintf('  [File IPC Client] Response accepted: class=%s, conf=%.3f (spray_allowed=%d)\n', ...
                                        res.predicted_class, res.confidence, res.spray_allowed);
                            end
                        end
                        break;
                    end
                catch
                    % Retry next loop if file was partially locked
                end
            end
            drawnow;
            pause(0.02);
        end

        if ~found
            res.status = 'error';
            res.predicted_class = 'unknown';
            res.confidence = NaN;
            res.spray_allowed = false;
            res.error = sprintf('File IPC timeout after %.1f s waiting for response.', opts.timeout);
            if exist(finalReqFile, 'file'), delete(finalReqFile); end
            if isfield(opts, 'verbose') && opts.verbose
                fprintf('  [File IPC Client] Timed out after %.1f s waiting for %s\n', opts.timeout, respFile);
            end
        end

    catch exc
        res.status        = 'error';
        res.predicted_class = 'unknown';
        res.confidence    = NaN;
        res.spray_allowed = false;
        res.error         = sprintf('File IPC exception: %s', exc.message);
        if exist(tmpReqFile, 'file'), delete(tmpReqFile); end
        if exist(finalReqFile, 'file'), delete(finalReqFile); end
    end
end

function res = parseBridgeResponse(raw, demoThreshold, expectedMissionId, expectedRequestId, expectedPlantId, fallback)
    res = fallback;
    
    % 1. Validate response is a scalar struct
    if ~isstruct(raw) || ~isscalar(raw)
        res.status = 'error';
        res.predicted_class = 'unknown';
        res.confidence = NaN;
        res.severity = struct();
        res.spray_allowed = false;
        res.error = 'Malformed response: expected scalar struct';
        return;
    end

    % 2. Check common identity fields exist
    commonFields = {'status', 'mission_id', 'request_id', 'plant_id'};
    for i = 1:numel(commonFields)
        if ~isfield(raw, commonFields{i})
            res.status = 'error';
            res.predicted_class = 'unknown';
            res.confidence = NaN;
            res.severity = struct();
            res.spray_allowed = false;
            res.error = sprintf('Malformed response: missing identity field "%s"', commonFields{i});
            return;
        end
    end

    % 3. Validate identity field types safely BEFORE conversion
    if ~isTextScalar(raw.status)
        res.status = 'error'; res.predicted_class = 'unknown'; res.confidence = NaN;
        res.spray_allowed = false; res.error = 'Malformed response: status must be a non-empty text scalar';
        return;
    end
    if ~isTextScalar(raw.mission_id)
        res.status = 'error'; res.predicted_class = 'unknown'; res.confidence = NaN;
        res.spray_allowed = false; res.error = 'Malformed response: mission_id must be a non-empty text scalar';
        return;
    end
    if ~isTextScalar(raw.request_id)
        res.status = 'error'; res.predicted_class = 'unknown'; res.confidence = NaN;
        res.spray_allowed = false; res.error = 'Malformed response: request_id must be a non-empty text scalar';
        return;
    end
    if ~isTextOrNumericScalar(raw.plant_id)
        res.status = 'error'; res.predicted_class = 'unknown'; res.confidence = NaN;
        res.spray_allowed = false; res.error = 'Malformed response: plant_id must be a scalar text or number';
        return;
    end

    % 4. Validate identity matching against expected values
    if ~isequal(char(string(raw.mission_id)), char(string(expectedMissionId)))
        res.status = 'error';
        res.predicted_class = 'unknown';
        res.confidence = NaN;
        res.severity = struct();
        res.spray_allowed = false;
        res.error = sprintf('Mismatched mission_id: expected %s, got %s', ...
                            char(string(expectedMissionId)), char(string(raw.mission_id)));
        return;
    end

    if ~isequal(char(string(raw.request_id)), char(string(expectedRequestId)))
        res.status = 'error';
        res.predicted_class = 'unknown';
        res.confidence = NaN;
        res.severity = struct();
        res.spray_allowed = false;
        res.error = sprintf('Mismatched request_id: expected %s, got %s', ...
                            char(string(expectedRequestId)), char(string(raw.request_id)));
        return;
    end

    if ~isequal(char(string(raw.plant_id)), char(string(expectedPlantId)))
        res.status = 'error';
        res.predicted_class = 'unknown';
        res.confidence = NaN;
        res.severity = struct();
        res.spray_allowed = false;
        res.error = sprintf('Mismatched plant_id: expected %s, got %s', ...
                            char(string(expectedPlantId)), char(string(raw.plant_id)));
        return;
    end

    % 5. Handle explicit error responses FIRST, preserving the server's error message
    statusStr = char(string(raw.status));
    if ~strcmp(statusStr, 'success')
        res.status = 'error';
        res.predicted_class = 'unknown';
        res.confidence = NaN;
        res.severity = struct();
        res.spray_allowed = false;
        if isfield(raw, 'error') && ~isempty(raw.error)
            res.error = char(string(raw.error));
        else
            res.error = 'Inference returned non-success status';
        end
        return;
    end

    % 6. For status == "success", validate success-only fields and types
    successFields = {'predicted_class', 'confidence', 'class_probabilities', 'severity', 'spray_allowed'};
    for i = 1:numel(successFields)
        if ~isfield(raw, successFields{i})
            res.status = 'error';
            res.predicted_class = 'unknown';
            res.confidence = NaN;
            res.severity = struct();
            res.spray_allowed = false;
            res.error = sprintf('Malformed success response: missing field "%s"', successFields{i});
            return;
        end
    end

    if ~isTextScalar(raw.predicted_class)
        res.status = 'error'; res.predicted_class = 'unknown'; res.confidence = NaN;
        res.spray_allowed = false; res.error = 'Malformed response: predicted_class must be a text scalar';
        return;
    end
    if ~islogical(raw.spray_allowed) || ~isscalar(raw.spray_allowed)
        res.status = 'error'; res.predicted_class = 'unknown'; res.confidence = NaN;
        res.spray_allowed = false; res.error = 'Malformed response: spray_allowed must be a logical scalar';
        return;
    end
    if ~isstruct(raw.severity) || ~isscalar(raw.severity)
        res.status = 'error'; res.predicted_class = 'unknown'; res.confidence = NaN;
        res.spray_allowed = false; res.error = 'Malformed response: severity must be a scalar struct';
        return;
    end
    if ~isstruct(raw.class_probabilities) || ~isscalar(raw.class_probabilities)
        res.status = 'error'; res.predicted_class = 'unknown'; res.confidence = NaN;
        res.spray_allowed = false; res.error = 'Malformed response: class_probabilities must be a scalar struct';
        return;
    end

    % 7. Validate predicted_class is a known disease/healthy class
    knownClasses = {'early_blight', 'healthy', 'late_blight'};
    predClass = char(string(raw.predicted_class));
    if ~ismember(predClass, knownClasses)
        res.status = 'error';
        res.predicted_class = 'unknown';
        res.confidence = NaN;
        res.severity = struct();
        res.spray_allowed = false;
        res.error = sprintf('Unknown predicted_class: "%s"', predClass);
        return;
    end

    % 8. Validate confidence is a finite scalar in [0, 1]
    if ~isnumeric(raw.confidence) || ~isscalar(raw.confidence) || ~isfinite(raw.confidence) || ...
       raw.confidence < 0.0 || raw.confidence > 1.0
        res.status = 'error';
        res.predicted_class = 'unknown';
        res.confidence = NaN;
        res.severity = struct();
        res.spray_allowed = false;
        res.error = 'Invalid confidence value: must be a numeric finite scalar in [0, 1]';
        return;
    end
    conf = double(raw.confidence);

    % 9. Validate severity structure (never represent unavailable severity with band='none')
    sev = raw.severity;
    if isfield(sev, 'status') && isequal(char(string(sev.status)), 'unavailable')
        sev.band = [];
        sev.band_label = [];
        sev.affected_leaf_area_percent = NaN;
    end

    % 10. Treatment decision rule:
    % Respect server's spray_allowed AND require local policy pass
    serverSprayAllowed = raw.spray_allowed;
    isDiseased = ismember(predClass, {'early_blight', 'late_blight'});
    localPolicyAllowed = isDiseased && (conf >= demoThreshold);

    res.status              = 'success';
    res.predicted_class     = predClass;
    res.confidence          = conf;
    res.class_probabilities = raw.class_probabilities;
    res.severity            = sev;
    res.spray_allowed       = logical(serverSprayAllowed && localPolicyAllowed);
    res.error               = [];
end

function tf = isTextScalar(val)
    tf = (ischar(val) && isrow(val) && ~isempty(val)) || ...
         (isstring(val) && isscalar(val) && strlength(val) > 0);
end

function tf = isTextOrNumericScalar(val)
    tf = isTextScalar(val) || (isnumeric(val) && isscalar(val) && isfinite(val));
end

function s = rtrim(s, ch)
    while ~isempty(s) && s(end) == ch
        s(end) = [];
    end
end
