function p = perceptionMetrics(field, seen, targets)
%PERCEPTIONMETRICS Observation and detection metrics (no spray, no "coverage").
%
%   p = perceptionMetrics(field, seen, targets)
%
%   seen    : Nx1 logical, plant entered the camera footprint
%   targets : detectPlants output (uses .isTruePositive)
%
%   observationRate          seen / all plants
%   diseasedObservationRate  seen diseased / all diseased
%   recall                   TP / (TP+FN) over ALL truly diseased, so diseased
%                            plants never imaged count as false negatives
%   recallGivenObserved      TP / seen diseased (classifier quality alone)
%   precision                TP / (TP+FP)
%   FN is split into FNunobserved (never imaged) and FNobservedMissed
%   (imaged but not flagged).

    isDis = field.plants.TrueDisease == "DISEASED";
    TP = sum(targets.isTruePositive);
    FP = sum(~targets.isTruePositive);

    p.nPlants        = numel(isDis);
    p.nDiseased      = sum(isDis);
    p.nSeen          = sum(seen);
    p.nSeenDiseased  = sum(seen & isDis);
    p.observationRate         = safeDiv(p.nSeen, p.nPlants);
    p.diseasedObservationRate = safeDiv(p.nSeenDiseased, p.nDiseased);
    p.TP = TP;
    p.FP = FP;
    p.FN = p.nDiseased - TP;
    p.FNunobserved     = p.nDiseased - p.nSeenDiseased;
    p.FNobservedMissed = p.nSeenDiseased - TP;
    p.recall              = safeDiv(TP, p.nDiseased);
    p.recallGivenObserved = safeDiv(TP, p.nSeenDiseased);
    p.precision           = safeDiv(TP, TP + FP);
end
