function res = runExperimentAB(cfg, field)
%RUNEXPERIMENTAB Experiments A+B: vehicle-disturbance sweep and its perception consequence.
%
%   res = runExperimentAB(cfg, field)
%
%   For every (wind speed, PID state) in cfg.experiments.A, fly ONE Pass-1
%   survey (identical field, ground truth and detection draws; nothing here
%   draws random numbers), then score that single flight with each detector
%   mode in cfg.experiments.A.detectModes:
%     A: cross-track error and position error (distinct), max deviation
%     B: plant observation rate, disease recall/precision, FP/FN
%   'perfectVisible' = perfect classification CONDITIONAL ON OBSERVATION, so
%   recall there equals the diseased-plant observation rate by construction.
%   wind speed 0 is the no-wind control (with PID on = controller effect
%   without disturbance). Wind enters the vehicle only via
%   cfg.internal2.vehicle.windCoupling; the resulting ground disturbance is
%   recorded alongside wind speed. No Pass 2 / spray here.
%
%   res.table : long table, one row per (windSpeed, pid, detectMode).

    E = cfg.experiments.A;
    modes = E.detectModes;
    coupling = cfg.internal2.vehicle.windCoupling;

    rows = {};
    for pid = E.pidStates(:)'
        for ws = E.windSpeeds(:)'
            c = applyScenario(cfg, true, pid, false, ws);
            sv = runSurveyPass(c, field);
            trk = trackingMetrics(sv.log1.cross, sv.log1.posErr);
            for k = 1:numel(modes)
                [tg, seen] = detectPlants(field, sv.log1, c, modes{k});
                pm = perceptionMetrics(field, seen, tg);
                rows{end+1, 1} = makeRow(ws, coupling * ws, pid, modes{k}, trk, pm, sv); %#ok<AGROW>
            end
        end
    end
    res.table = struct2table(vertcat(rows{:}));
    res.settings = E;
    res.windCoupling = coupling;
    res.determinismOK = checkDeterminism(cfg, field, res.table);
end

function r = makeRow(ws, groundDist, pid, mode, trk, pm, sv)
    r = struct( ...
        'windSpeed_mps', ws, ...
        'groundDisturbance_mps', groundDist, ...
        'pid', double(pid), ...
        'detectMode', string(mode), ...
        'crossRMSE_m', trk.crossRMSE, ...
        'crossMeanAbs_m', trk.crossMeanAbs, ...
        'crossMaxAbs_m', trk.crossMaxAbs, ...
        'posRMSE_m', trk.posRMSE, ...
        'posMax_m', trk.posMax, ...
        'observationRate', pm.observationRate, ...
        'diseasedObservationRate', pm.diseasedObservationRate, ...
        'nPlants', pm.nPlants, ...
        'nSeen', pm.nSeen, ...
        'nDiseased', pm.nDiseased, ...
        'nSeenDiseased', pm.nSeenDiseased, ...
        'TP', pm.TP, 'FP', pm.FP, 'FN', pm.FN, ...
        'FN_unobserved', pm.FNunobserved, ...
        'FN_observedMissed', pm.FNobservedMissed, ...
        'recall', pm.recall, ...
        'recallGivenObserved', pm.recallGivenObserved, ...
        'precision', pm.precision, ...
        'surveyTime_s', sv.time, ...
        'surveyDistance_m', sv.distance);
end

function ok = checkDeterminism(cfg, field, T)
%CHECKDETERMINISM Re-fly the last (wind, PID) point and compare its table rows.
    E = cfg.experiments.A;
    ws = E.windSpeeds(end);
    pid = E.pidStates(end);
    c = applyScenario(cfg, true, pid, false, ws);
    sv = runSurveyPass(c, field);
    trk = trackingMetrics(sv.log1.cross, sv.log1.posErr);
    coupling = cfg.internal2.vehicle.windCoupling;
    rows = {};
    for k = 1:numel(E.detectModes)
        [tg, seen] = detectPlants(field, sv.log1, c, E.detectModes{k});
        rows{end+1, 1} = makeRow(ws, coupling * ws, pid, E.detectModes{k}, trk, perceptionMetrics(field, seen, tg), sv); %#ok<AGROW>
    end
    Tchk = struct2table(vertcat(rows{:}));
    sel = T.windSpeed_mps == ws & T.pid == double(pid);
    ok = isequaln(T(sel, :), Tchk);
end
