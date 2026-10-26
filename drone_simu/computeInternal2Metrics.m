function m = computeInternal2Metrics(cfg, field, run)
%COMPUTEINTERNAL2METRICS Quantitative metrics for one Internal-2 run.
%
%   Composes the shared metric functions (also used by the experiments):
%     trackingMetrics   cross-track error AND position error (distinct)
%     perceptionMetrics observation rate, recall, precision, FP/FN
%     sprayMetrics      treatment success, target/off-target deposition
%
%   All spray numbers come from the SIMPLIFIED deposition model (assumed
%   parameters, see config.m) and are meaningful only as comparisons between
%   runs, not as absolute predictions.
%
%   Tracking: cross-track error = signed distance from the TRUE position to
%   the active segment of the reference polyline (survey path in Pass 1,
%   the straight leg in Pass 2 transit). "Max deviation" = max |cross-track|.
%   posErr additionally includes along-track (timing) error versus the
%   time-indexed reference point.
%
%   Legacy field names (m.detect.*, m.spray.coverageRate, usefulPct, ...) are
%   kept so existing callers still work; the unambiguous names live in
%   m.perception and the new aliases in m.spray (treatmentSuccess,
%   targetDepositionPct, offTargetPct).

    % ---------------- path tracking ----------------
    m.survey = trackingMetrics(run.log1.cross, run.log1.posErr);

    cr = []; pe = [];
    for j = 1:numel(run.legLogs)
        L = run.legLogs{j};
        mk = L.phase == 1;
        cr = [cr; L.cross(mk)]; %#ok<AGROW>
        pe = [pe; L.posErr(mk)]; %#ok<AGROW>
    end
    m.transit = trackingMetrics(cr, pe);

    % ---------------- perception ----------------
    m.perception = perceptionMetrics(field, run.seen, run.targets);
    m.detect.trueDiseased      = m.perception.nDiseased;
    m.detect.plantsImaged      = m.perception.nSeen;
    m.detect.detectedTrue      = m.perception.TP;
    m.detect.falsePositives    = m.perception.FP;
    m.detect.missedByDetection = m.perception.nDiseased - m.perception.TP;

    % ---------------- treatment + spray ----------------
    m.spray = sprayMetrics(cfg, field, run.grid, run.targets.plantIdx);

    % ---------------- operational efficiency ----------------
    r = run.routes;
    m.route = r;
    m.route.nnSavingVsFullSurveyPct = 100 * (1 - safeDiv(r.nnLength, r.fullSurveyLength));
    m.route.nnSavingVsStage7Pct = 100 * (1 - safeDiv(r.nnLength, r.stage7Length));
    m.route.numTargets = size(run.releasePts, 1);
    m.pass1.time = run.pass1.time;
    m.pass1.distance = run.pass1.distance;
end
