function report = calculatePesticideCapacity(fieldInfo, diseasedCount, severityCounts, params)
%CALCULATEPESTICIDECAPACITY Estimate pesticide volume, tank size, and
%   refill requirements for TARGETED spraying, and compare against a
%   BLANKET (spray-every-plant) baseline to quantify the pesticide
%   savings claimed in Objective 3 ("minimizing pesticide use").
%
%   report = calculatePesticideCapacity(fieldInfo, diseasedCount, severityCounts, params)
%
%   fieldInfo      - struct from generateField.m (.totalPlants, .length, .width)
%   diseasedCount  - number of CONFIRMED diseased plants to be sprayed
%   severityCounts - struct with .mild, .moderate, .severe counts
%                    (from the heuristic buckets in calculateSeverity.m)
%   params         - OPTIONAL struct to override default assumptions:
%                       .baseVolumePerPlant_mL     (default 50)
%                       .mildFactor                (default 0.5)
%                       .moderateFactor            (default 1.0)
%                       .severeFactor              (default 1.5)
%                       .safetyMarginPct           (default 20)
%                       .tankCapacity_L            (default 2)
%                       .blanketVolumePerPlant_mL  (default 50)
%
%   ============================ IMPORTANT ============================
%   The per-plant volume and severity scaling factors below are
%   PLACEHOLDER ENGINEERING ASSUMPTIONS for sizing the tank/pump, NOT
%   agronomic recommendations. Real pesticide dosage depends on the
%   specific chemical, crop, and disease, and must follow the actual
%   product label (commonly expressed in L/hectare) or guidance from an
%   agricultural extension officer. Do not build real hardware or apply
%   real pesticide based on these numbers without that verification.
%   =====================================================================

    if nargin < 4
        params = struct();
    end
    defaults.baseVolumePerPlant_mL    = 50;
    defaults.mildFactor               = 0.5;
    defaults.moderateFactor           = 1.0;
    defaults.severeFactor             = 1.5;
    defaults.safetyMarginPct          = 20;
    defaults.tankCapacity_L           = 2;
    defaults.blanketVolumePerPlant_mL = 50;

    fn = fieldnames(defaults);
    for i = 1:numel(fn)
        if ~isfield(params, fn{i})
            params.(fn{i}) = defaults.(fn{i});
        end
    end

    % --- targeted spraying volume (severity-scaled) ---
    mL_mild     = severityCounts.mild     * params.baseVolumePerPlant_mL * params.mildFactor;
    mL_moderate = severityCounts.moderate * params.baseVolumePerPlant_mL * params.moderateFactor;
    mL_severe   = severityCounts.severe   * params.baseVolumePerPlant_mL * params.severeFactor;

    totalTargetedVolume_mL = (mL_mild + mL_moderate + mL_severe) * (1 + params.safetyMarginPct/100);

    % --- blanket spraying baseline (every plant in the field) ---
    totalBlanketVolume_mL = fieldInfo.totalPlants * params.blanketVolumePerPlant_mL;

    % --- tank / refill calculation ---
    tankCapacity_mL = params.tankCapacity_L * 1000;
    numRefills = ceil(totalTargetedVolume_mL / tankCapacity_mL);

    % --- field-area dosage rate (standard agricultural unit) ---
    fieldArea_ha = (fieldInfo.length * fieldInfo.width) / 10000;
    dosageRate_Lperha = (totalTargetedVolume_mL / 1000) / fieldArea_ha;

    % --- pesticide savings vs. blanket spraying ---
    pesticideSavedPct = 100 * (1 - totalTargetedVolume_mL / totalBlanketVolume_mL);

    report.totalTargetedVolume_mL = totalTargetedVolume_mL;
    report.totalBlanketVolume_mL  = totalBlanketVolume_mL;
    report.pesticideSavedPct      = pesticideSavedPct;
    report.tankCapacity_mL        = tankCapacity_mL;
    report.numRefillsNeeded       = numRefills;
    report.dosageRate_Lperha      = dosageRate_Lperha;
    report.diseasedCount          = diseasedCount;
    report.severityCounts         = severityCounts;
    report.params                 = params;

    fprintf('\n=== PESTICIDE CAPACITY REPORT ===\n');
    fprintf('Field: %.0f m x %.0f m (%.4f hectares)\n', fieldInfo.length, fieldInfo.width, fieldArea_ha);
    fprintf('Total plants in field : %d\n', fieldInfo.totalPlants);
    fprintf('Confirmed diseased    : %d (mild=%d, moderate=%d, severe=%d)\n', ...
        diseasedCount, severityCounts.mild, severityCounts.moderate, severityCounts.severe);
    fprintf('\n--- Targeted spraying (this system) ---\n');
    fprintf('Total volume needed   : %.0f mL (%.2f L), incl. %d%% safety margin\n', ...
        totalTargetedVolume_mL, totalTargetedVolume_mL/1000, params.safetyMarginPct);
    fprintf('Tank capacity assumed : %.0f mL (%.1f L)\n', tankCapacity_mL, params.tankCapacity_L);
    fprintf('Refills needed        : %d\n', numRefills);
    fprintf('Effective dosage rate : %.1f L/hectare\n', dosageRate_Lperha);
    fprintf('\n--- Comparison: blanket spraying (every plant, untargeted) ---\n');
    fprintf('Blanket volume needed : %.0f mL (%.2f L)\n', totalBlanketVolume_mL, totalBlanketVolume_mL/1000);
    fprintf('Pesticide saved       : %.1f%%\n', pesticideSavedPct);
    fprintf('==================================\n');
    fprintf(['NOTE: per-plant volume and severity factors are placeholder\n' ...
             'engineering assumptions - confirm against the actual pesticide\n' ...
             'product label before any real-world use.\n']);
end
