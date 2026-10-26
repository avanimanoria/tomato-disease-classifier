function s = missionSummary(tl)
%MISSIONSUMMARY Operational end-of-mission summary from the replay timeline.
%
%   s = missionSummary(tl)
%
%   Mission-mode only: durations, distances, plants observed, targets flagged and
%   sprayed, spray volume emitted. These are things the drone itself knows. Any
%   evaluation against hidden ground truth (true diseased count, TP/FP/FN, recall,
%   treatment of truly diseased plants) belongs to Experiments mode, not here.
%   Call it only when the replay has finished.

    n1 = tl.n1;
    s.totalTime_s = tl.t(end);
    s.pass1Time_s = tl.t(n1);
    s.pass2Time_s = tl.t(end) - tl.t(n1);
    s.pass1Distance_m = tl.cumDist(n1);
    s.pass2Distance_m = tl.cumDist(end) - tl.cumDist(n1);
    s.totalDistance_m = tl.cumDist(end);
    s.plantsTotal = tl.nPlants;
    s.plantsObserved = nnz(tl.firstStep > 0);
    s.targetsFlagged = nnz(tl.flagStep > 0);
    s.targetsSprayed = tl.sprayDone(end);
    s.sprayEmitted_mL = tl.sprayStepsCum(end) * tl.emitPerStep_mL;
    s.routing = tl.routing;
end
