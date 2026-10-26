function s = sprayMetrics(cfg, field, grid, targetPlantIdx)
%SPRAYMETRICS Treatment and deposition metrics from a deposition grid.
%
%   s = sprayMetrics(cfg, field, grid, targetPlantIdx)
%
%   targetPlantIdx : plants that were TARGETED (rows of field.plants).
%
%   All numbers come from the SIMPLIFIED deposition model (assumed
%   parameters) and are only meaningful as comparisons between runs.
%
%   Treatment success   treated diseased / all truly diseased. "Treated" =
%                       canopy disc received >= treatedDoseFraction of one
%                       nominal spray volume. (Legacy name: coverageRate.)
%   Target deposition   mass on truly diseased canopies / emitted. (Legacy
%                       name: usefulPct.)
%   Off-target          healthy canopies and other ground, % of emitted.
%   meanTargetDoseFraction  mean dose / nominal over targeted diseased plants.

    I = cfg.internal2;
    S = I.spray;
    P = field.plants;
    N = height(P);
    isDis = P.TrueDisease == "DISEASED";

    dose = plantDose(cfg, field, grid);
    nominal = S.flowRate * S.duration;          % mL per spray event
    treated = dose >= I.metrics.treatedDoseFraction * nominal;
    wasTargeted = false(N, 1);
    wasTargeted(targetPlantIdx) = true;

    trueDiseased = sum(isDis);
    detectedTrue = sum(isDis(targetPlantIdx));

    s.nominalPerTarget_mL = nominal;
    s.treatedTrue = sum(treated & isDis);
    s.coverageRate = safeDiv(s.treatedTrue, trueDiseased);        % legacy name
    s.treatmentSuccess = s.coverageRate;
    s.missedTargets = trueDiseased - s.treatedTrue;
    s.deliveryOfDetected = safeDiv(sum(treated & isDis & wasTargeted), detectedTrue);
    s.healthyPlantsHit = sum(treated & ~isDis);
    s.meanTargetDoseFraction = safeDiv(sum(dose(isDis & wasTargeted)), sum(isDis & wasTargeted)) / nominal;

    emitted = grid.emitted;
    useful = sum(dose(isDis));
    onHealthy = sum(dose(~isDis));
    s.emitted_mL = emitted;
    s.useful_mL = useful;
    s.wasted_mL = emitted - useful;
    s.onHealthyPlants_mL = onHealthy;
    s.onOtherGround_mL = emitted - useful - onHealthy;
    s.usefulPct = 100 * safeDiv(useful, emitted);                 % legacy name
    s.targetDepositionPct = s.usefulPct;
    s.wastedPct = 100 * safeDiv(emitted - useful, emitted);
    s.offTargetPct = s.wastedPct;
    s.onHealthyPct = 100 * safeDiv(onHealthy, emitted);
    s.onOtherGroundPct = 100 * safeDiv(emitted - useful - onHealthy, emitted);
end
