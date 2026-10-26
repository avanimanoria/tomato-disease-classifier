function result = calculateSeverity(result)
%CALCULATESEVERITY Heuristic severity ESTIMATE for a DISEASED plant.
%   (Section 14)
%
%   ============================ IMPORTANT ============================
%   Your current dataset has ONLY binary labels: healthy / diseased.
%   It has NO severity ground truth (no mild/moderate/severe labels, no
%   percent-leaf-damage annotations). A model can only learn to measure
%   things it was actually shown examples of - since this dataset never
%   showed the model "what mild disease looks like" vs "what severe
%   disease looks like," nothing trained on it can genuinely measure
%   severity.
%
%   What this function returns is a ROUGH, UNVALIDATED HEURISTIC PROXY,
%   derived only from the classifier's own confidence score (higher
%   confidence "diseased" -> assumed more severe). This is NOT a
%   scientifically measured severity value. It should be clearly labeled
%   as a heuristic/placeholder everywhere it is displayed.
%
%   TO GET REAL SEVERITY: you would need a dataset where images are
%   actually labeled with severity (e.g. mild/moderate/severe folders,
%   or a numeric percent-damage value per image), and train a dedicated
%   severity classifier or regressor on THAT data. This function's
%   input/output shape (result.severity, result.severityLabel) is kept
%   identical to what a real severity model would produce, so you can
%   swap the heuristic below for a real model later without changing
%   any other file in the project.
%   =====================================================================
%
%   result = calculateSeverity(result) takes the struct returned by
%   detectDisease() and adds two fields:
%     result.severity      - 0-100 (heuristic only, see above)
%     result.severityLabel - "Mild (heuristic)" / "Moderate (heuristic)"
%                             / "Severe (heuristic)" / "N/A (Healthy)"

    if result.label == "HEALTHY"
        result.severity = 0;
        result.severityLabel = "N/A (Healthy)";
        return;
    end

    conf = result.confidence; % 0-100, from detectDisease

    % HEURISTIC ONLY: rescale confidence [50-100] -> severity [0-100].
    % This assumes "the model is very sure this is diseased" loosely
    % correlates with "looks more severely diseased" - a reasonable
    % guess, but NOT something this dataset/model was ever trained or
    % validated to measure.
    severity = max(0, min(100, 2 * (conf - 50)));
    result.severity = severity;

    if severity < 30
        result.severityLabel = "Mild (heuristic)";
    elseif severity < 70
        result.severityLabel = "Moderate (heuristic)";
    else
        result.severityLabel = "Severe (heuristic)";
    end
end
