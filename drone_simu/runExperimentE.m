function res = runExperimentE(cfg, field, verbose)
%RUNEXPERIMENTE Experiment E: the integrated end-to-end mission (original demo).
%
%   res = runExperimentE(cfg, field [, verbose])
%
%   Scenarios come from cfg.experiments.E.scenarios: preset names (see
%   scenarioPresets), 'Custom', or struct(wind, pid, comp). A name is only a
%   label for three switches - nothing here branches on it. Default list:
%     Baseline              wind OFF, PID OFF, compensation OFF
%     No wind + PID         wind OFF, PID ON,  compensation OFF   (control)
%     Disturbed             wind ON,  PID OFF, compensation OFF
%     Navigation Corrected  wind ON,  PID ON,  compensation OFF   (was "PID only")
%     Fully Corrected       wind ON,  PID ON,  compensation ON    (was "Corrected")
%   All use the identical field, wind vector, ground truth and detection
%   draws. Numerically unchanged from the original four (golden-verified).
%   Detection follows cfg.internal2.detect.mode (default 'stochastic').
%
%   res: scn, runs, mets, table (one row per scenario, machine-readable),
%   determinismOK.

    if nargin < 3, verbose = true; end

    specs = cfg.experiments.E.scenarios;
    nS = numel(specs);
    cfgs = cell(1, nS);
    for i = 1:nS
        [cfgs{i}, label] = applyPreset(cfg, specs{i});
        scn(i).name = label; %#ok<AGROW>
        scn(i).wind = cfgs{i}.internal2.wind.enabled;
        scn(i).pid  = cfgs{i}.internal2.ctrl.enabled;
        scn(i).comp = cfgs{i}.internal2.spray.compensate;
    end

    runs = cell(1, nS);
    mets = cell(1, nS);
    for i = 1:nS
        c = cfgs{i};
        if verbose
            fprintf('\nRunning %-14s (wind=%d, PID=%d, compensation=%d) ...\n', ...
                scn(i).name, scn(i).wind, scn(i).pid, scn(i).comp);
        end
        runs{i} = runInternal2Scenario(c, field, scn(i).name);
        mets{i} = computeInternal2Metrics(c, field, runs{i});
    end

    % ---- determinism: re-run the last scenario ----
    cChk = cfgs{nS};
    runChk = runInternal2Scenario(cChk, field, scn(nS).name);
    metChk = computeInternal2Metrics(cChk, field, runChk);
    res.determinismOK = isequaln(metChk, mets{nS});

    res.scn = scn;
    res.runs = runs;
    res.mets = mets;
    res.table = buildTable(scn, mets);

    if verbose
        printComparison(scn, mets);
        if res.determinismOK
            fprintf('\nDETERMINISM CHECK: PASS (re-run of "%s" reproduced identical metrics)\n', scn(nS).name);
        else
            fprintf('\nDETERMINISM CHECK: FAIL (re-run of "%s" differs)\n', scn(nS).name);
        end
        printParameters(cfg);
    end
end

function T = buildTable(scn, mets)
%BUILDTABLE One row per scenario with every reported metric (raw numbers).
    rows = cell(numel(scn), 1);
    for i = 1:numel(scn)
        m = mets{i};
        rows{i} = struct( ...
            'scenario', string(scn(i).name), ...
            'wind', double(scn(i).wind), 'pid', double(scn(i).pid), 'compensate', double(scn(i).comp), ...
            'surveyCrossRMSE_m', m.survey.crossRMSE, 'surveyCrossMeanAbs_m', m.survey.crossMeanAbs, ...
            'surveyCrossMaxAbs_m', m.survey.crossMaxAbs, ...
            'surveyPosRMSE_m', m.survey.posRMSE, 'surveyPosMax_m', m.survey.posMax, ...
            'transitCrossRMSE_m', m.transit.crossRMSE, 'transitCrossMaxAbs_m', m.transit.crossMaxAbs, ...
            'transitPosRMSE_m', m.transit.posRMSE, ...
            'nPlants', m.perception.nPlants, 'nDiseased', m.perception.nDiseased, 'nSeen', m.perception.nSeen, ...
            'observationRate', m.perception.observationRate, ...
            'diseasedObservationRate', m.perception.diseasedObservationRate, ...
            'TP', m.perception.TP, 'FP', m.perception.FP, 'FN', m.perception.FN, ...
            'FN_unobserved', m.perception.FNunobserved, 'FN_observedMissed', m.perception.FNobservedMissed, ...
            'recall', m.perception.recall, 'recallGivenObserved', m.perception.recallGivenObserved, ...
            'precision', m.perception.precision, ...
            'treatedTrue', m.spray.treatedTrue, 'treatmentSuccess', m.spray.treatmentSuccess, ...
            'deliveryOfDetected', m.spray.deliveryOfDetected, 'healthyPlantsHit', m.spray.healthyPlantsHit, ...
            'meanTargetDoseFraction', m.spray.meanTargetDoseFraction, ...
            'emitted_mL', m.spray.emitted_mL, 'useful_mL', m.spray.useful_mL, 'wasted_mL', m.spray.wasted_mL, ...
            'targetDepositionPct', m.spray.targetDepositionPct, 'offTargetPct', m.spray.offTargetPct, ...
            'onHealthyPct', m.spray.onHealthyPct, 'onOtherGroundPct', m.spray.onOtherGroundPct, ...
            'nnLength_m', m.route.nnLength, 'nnFlightTime_s', m.route.nnFlightTime, ...
            'detOrderLength_m', m.route.detOrderLength, ...
            'stage7Length_m', m.route.stage7Length, 'stage7FlightTime_s', m.route.stage7FlightTime, ...
            'fullSurveyLength_m', m.route.fullSurveyLength, 'fullSurveyTime_s', m.route.fullSurveyFlightTime, ...
            'actualPass2Distance_m', m.route.actualDistance, 'actualPass2FlightTime_s', m.route.actualFlightTime, ...
            'actualPass2TotalTime_s', m.route.actualTotalTime);
    end
    T = struct2table(vertcat(rows{:}));
end

function printComparison(scn, mets)
    nS = numel(scn);
    rows = {
     'PASS 1 - SURVEY TRACKING (vs reference survey path)', [], ''
     '  Cross-track RMSE (m)',            @(m) m.survey.crossRMSE,    '%22.3f'
     '  Mean |cross-track| (m)',          @(m) m.survey.crossMeanAbs, '%22.3f'
     '  Max deviation = max |cross| (m)', @(m) m.survey.crossMaxAbs,  '%22.3f'
     '  Position RMSE vs timed ref (m)',  @(m) m.survey.posRMSE,      '%22.3f'
     'PASS 2 - TRANSIT TRACKING (vs straight leg)', [], ''
     '  Cross-track RMSE (m)',            @(m) m.transit.crossRMSE,   '%22.3f'
     '  Max deviation (m)',               @(m) m.transit.crossMaxAbs, '%22.3f'
     'PERCEPTION', [], ''
     '  Truly diseased plants',           @(m) m.perception.nDiseased,        '%22d'
     '  Plants observed (of all)',        @(m) m.perception.nSeen,            '%22d'
     '  Plant observation rate',          @(m) 100*m.perception.observationRate, '%21.1f%%'
     '  Disease recall (TP/true diseased)', @(m) 100*m.perception.recall,     '%21.1f%%'
     '  Recall given observed',           @(m) 100*m.perception.recallGivenObserved, '%21.1f%%'
     '  Detection precision (TP/(TP+FP))', @(m) 100*m.perception.precision,   '%21.1f%%'
     '  True positives',                  @(m) m.perception.TP,               '%22d'
     '  False positives',                 @(m) m.perception.FP,               '%22d'
     '  False negatives (unobserved+missed)', @(m) m.perception.FN,          '%22d'
     'TREATMENT AND DEPOSITION', [], ''
     '  Diseased plants treated',         @(m) m.spray.treatedTrue,           '%22d'
     '  Treatment success (treated/true diseased)', @(m) 100*m.spray.treatmentSuccess, '%21.1f%%'
     '  Delivery (treated/detected diseased)', @(m) 100*m.spray.deliveryOfDetected, '%21.1f%%'
     '  Healthy plants receiving dose',   @(m) m.spray.healthyPlantsHit,      '%22d'
     '  Emitted (mL)',                    @(m) m.spray.emitted_mL,            '%22.1f'
     '  Useful: on diseased plants (mL)', @(m) m.spray.useful_mL,             '%22.1f'
     '  Wasted = emitted - useful (mL)',  @(m) m.spray.wasted_mL,             '%22.1f'
     '  Target deposition (% of emitted)', @(m) m.spray.targetDepositionPct,  '%21.1f%%'
     '  Off-target: healthy plants (%)',  @(m) m.spray.onHealthyPct,          '%21.1f%%'
     '  Off-target: other ground (%)',    @(m) m.spray.onOtherGroundPct,      '%21.1f%%'
     'TREATMENT ROUTE (same target set within each column; geometric = straight-line, nominal, no wind/hover)', [], ''
     '  [planned] NN route (m)',          @(m) m.route.nnLength,              '%22.1f'
     '  [planned] NN flight time (s)',    @(m) m.route.nnFlightTime,          '%22.1f'
     '  [geometric] detection order, no return (m)', @(m) m.route.detOrderLength, '%22.1f'
     '  [geometric] Stage-7-style: det. order + return-to-path (m)', @(m) m.route.stage7Length, '%22.1f'
     '  [geometric] Stage-7-style time @0.6x speed (s)', @(m) m.route.stage7FlightTime, '%22.1f'
     '  [reference] repeat full survey (m)',      @(m) m.route.fullSurveyLength,     '%22.1f'
     '  [reference] repeat full survey time (s)', @(m) m.route.fullSurveyFlightTime, '%22.1f'
     '  NN saving vs full survey (%)',    @(m) m.route.nnSavingVsFullSurveyPct, '%21.1f%%'
     '  NN saving vs Stage-7-style (%)',  @(m) m.route.nnSavingVsStage7Pct,     '%21.1f%%'
     '  [ACTUAL flown] Pass-2 distance (m)',      @(m) m.route.actualDistance,   '%22.1f'
     '  [ACTUAL flown] Pass-2 flight time (s)',   @(m) m.route.actualFlightTime, '%22.1f'
     '  [ACTUAL flown] Pass-2 total incl. hover (s)', @(m) m.route.actualTotalTime, '%22.1f'
    };
    w = 62 + 22 * nS;
    fprintf('\n%s\n', repmat('=', 1, w));
    fprintf('%-62s', 'EXPERIMENT E - INTEGRATED MISSION');
    for i = 1:nS, fprintf('%22s', scn(i).name); end
    fprintf('\n%s\n', repmat('=', 1, w));
    for r = 1:size(rows, 1)
        fprintf('%-62s', rows{r,1});
        if ~isempty(rows{r,2})
            for i = 1:nS
                fprintf(rows{r,3}, rows{r,2}(mets{i}));
            end
        end
        fprintf('\n');
    end
    fprintf('%s\n', repmat('=', 1, w));
    fprintf('Route labels: [planned] = what this mission will fly; [geometric] = straight-line estimate\n');
    fprintf('of an alternative behaviour over the same targets; [reference] = repeating the whole survey;\n');
    fprintf('[ACTUAL flown] = measured from the simulated (wind-disturbed) trajectory.\n');
    fprintf('Target sets differ between columns (detection depends on where the drone really flew).\n');
end

function printParameters(cfg)
    I = cfg.internal2;
    fprintf('\n--- PARAMETERS USED (all [ASSUMED] placeholders; see config.m) ---\n');
    fprintf('Wind: %.1f m/s toward %.0f deg | vehicle wind coupling %.3f -> ground disturbance %.3f m/s\n', ...
        I.wind.speed, I.wind.dirDeg, I.vehicle.windCoupling, I.vehicle.windCoupling * I.wind.speed);
    fprintf('PID gains: Kp %.2f Ki %.2f Kd %.2f | along Kp %.2f\n', I.ctrl.Kp, I.ctrl.Ki, I.ctrl.Kd, I.ctrl.KpAlong);
    fprintf('Spray: height %.1f m, half-angle %.0f deg (footprint r %.2f m), drift shift %.2f m (compensated runs shift upwind by this)\n', ...
        I.spray.releaseHeight, I.spray.nozzleHalfAngle, I.spray.releaseHeight * tand(I.spray.nozzleHalfAngle), ...
        norm(sprayDriftVector(cfg, I.wind.speed * [cosd(I.wind.dirDeg), sind(I.wind.dirDeg)])));
    fprintf('Detector mode: %s\n', I.detect.mode);
end
