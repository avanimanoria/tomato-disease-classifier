function res = runExperimentC(cfg, field)
%RUNEXPERIMENTC Experiment C: routing comparison, FLOWN, on ONE frozen target set.
%
%   res = runExperimentC(cfg, field)
%
%   Frozen set = ALL truly diseased plant coordinates in a fixed boustrophedon
%   order (frozenTargetOrder), independent of detection, wind and navigation:
%   perception cannot influence it. It is injected into the normal mission
%   engine (runInternal2Scenario opts.targets) so every strategy shares the
%   same survey pass, start state, field, vehicle, spray model and seed; ONLY
%   cfg.internal2.treat.routing (and, where stated, the travel-speed factor)
%   differs. Vehicle/wind/PID/compensation switches are those of the supplied cfg.
%
%   Strategies (cfg.internal2.treat.routing):
%     fixedOrder         targets in the supplied order, straight legs
%     nearestNeighbour   greedy NN from the current estimated position
%     stage7Return       supplied order; after EACH target return to the nearest
%                        survey-path point, then approach the next
%   Conditions:
%     historical   travel speed factors as configured (stage7Return = 0.6x, the
%                  original Stage-7 speed; the others 1.0x)
%     equalSpeed   all three strategies at the SAME speed (1.0x)
%
%   res.table: one row per (condition, strategy[, target count]) with the MEASURED
%   flown distance and elapsed times, plus the geometric prediction as a
%   validation reference. res.geometricTable: the straight-line estimates only
%   (nominal, no wind/hover), used by plotExperiments('C'). res.invariance:
%   Gate-3 checks that routing changed nothing else.
%
%   Stage-7 differences (documented, not silently changed): the original
%   confirmation re-reads the same observation and spraying consumed no clock
%   time. Here settle+dwell time is identical for every strategy (needed for
%   deposition), so compare TRAVEL time (measuredTravelTime_s) for routing;
%   measuredElapsedTime_s includes settle+dwell.
%
%   cfg.experiments.C.targetCounts adds seeded subsets of the frozen set.

    E = cfg.experiments.C;
    idx = frozenTargetOrder(field);
    P = field.plants;
    nAll = numel(idx);

    counts = E.targetCounts(:)';
    counts = counts(counts > 0 & counts < nAll);
    counts = [counts, nAll];
    stream = RandStream('mt19937ar', 'Seed', E.subsetSeed);

    strategies = {'fixedOrder', 'nearestNeighbour', 'stage7Return'};
    conditions = {'historical', 'equalSpeed'};

    rows = {};
    geomRows = {};
    runsAll = struct();
    for k = counts
        if k == nAll
            sel = (1:nAll)';
        else
            sel = sort(randperm(stream, nAll, k))';   % keeps the fixed relative order
        end
        pidx = idx(sel);
        targets = struct('plantIdx', pidx, 'ID', P.ID(pidx), 'XY', [P.X(pidx), P.Y(pidx)], ...
                         'detectTime', zeros(numel(pidx), 1), 'isTruePositive', true(numel(pidx), 1));
        for c = 1:numel(conditions)
            for s = 1:numel(strategies)
                cc = cfg;
                cc.internal2.enabled = true;
                cc.internal2.treat.routing = strategies{s};
                if strcmp(conditions{c}, 'equalSpeed')
                    cc.internal2.treat.speedFactor.(strategies{s}) = 1.0;
                end
                run = runInternal2Scenario(cc, field, strategies{s}, struct('targets', targets));
                rows{end+1, 1} = makeRow(conditions{c}, strategies{s}, k, nAll, cc, run); %#ok<AGROW>
                if k == nAll
                    runsAll.(conditions{c}).(strategies{s}) = run;
                    cfgsAll.(conditions{c}).(strategies{s}) = cc;
                end
            end
        end
        % geometric-only estimates (legacy straight-line table, nominal speeds)
        rl = routeLengths(run.startXY, targets.XY, field, cfg);
        geomRows{end+1, 1} = geomRow(k, nAll, 'Stage7-style',       rl.stage7Length,   rl.stage7FlightTime, rl); %#ok<AGROW>
        geomRows{end+1, 1} = geomRow(k, nAll, 'Direct fixed order', rl.detOrderLength, rl.detOrderFlightTime, rl); %#ok<AGROW>
        geomRows{end+1, 1} = geomRow(k, nAll, 'Nearest-neighbour',  rl.nnLength,       rl.nnFlightTime, rl); %#ok<AGROW>
    end

    res.table = struct2table(vertcat(rows{:}));
    res.geometricTable = struct2table(vertcat(geomRows{:}));
    % headline view: route distance and travel time first; elapsed time (incl. the identical
    % settle+dwell overhead, nTargets*(settle+duration)) is SECONDARY.
    res.summary = res.table(:, {'condition', 'strategy', 'targetCount', 'speedFactor', 'measuredDistance_m', ...
        'predictedDistance_m', 'measuredTravelTime_s', 'predictedTravelTime_s', 'measuredElapsedTime_s', 'dwellTime_s'});
    res.frozenPlantIdx = idx;
    res.frozenXY = [P.X(idx), P.Y(idx)];
    res.startXY = runsAll.historical.fixedOrder.startXY;
    res.settings = E;
    res.invariance = checkInvariance(runsAll, cfgsAll, strategies, conditions);

    % determinism: re-fly one configuration and require identical measured numbers
    cc = cfg; cc.internal2.enabled = true; cc.internal2.treat.routing = 'stage7Return';
    tAll = struct('plantIdx', idx, 'ID', P.ID(idx), 'XY', [P.X(idx), P.Y(idx)], ...
                  'detectTime', zeros(nAll, 1), 'isTruePositive', true(nAll, 1));
    r2 = runInternal2Scenario(cc, field, 'stage7Return', struct('targets', tAll));
    r1 = runsAll.historical.stage7Return;
    res.determinismOK = isequaln(r1.routes, r2.routes) && isequaln(r1.finalWorld, r2.finalWorld);
end

function r = makeRow(cond, strat, k, nAll, cc, run)
    R = run.routes;
    I = cc.internal2;
    sf = R.speedFactor;
    switch strat
        case 'fixedOrder',       predD = R.detOrderLength;
        case 'nearestNeighbour', predD = R.nnLength;
        case 'stage7Return',     predD = R.stage7Length;
    end
    predT = predD / (cc.droneSpeed * sf);
    nT = size(run.releasePts, 1);
    r = struct('condition', string(cond), 'strategy', string(strat), 'targetCount', k, 'frozenSetSize', nAll, ...
        'speedFactor', sf, 'travelSpeed_mps', cc.droneSpeed * sf, ...
        'wind', double(I.wind.enabled), 'pid', double(I.ctrl.enabled), 'compensate', double(I.spray.compensate), ...
        'measuredDistance_m', R.actualDistance, ...
        'measuredTravelTime_s', R.actualFlightTime, ...
        'measuredElapsedTime_s', R.actualTotalTime, ...
        'dwellTime_s', R.actualDwellTime, ...
        'predictedDistance_m', predD, ...
        'distanceDiscrepancy_m', R.actualDistance - predD, ...
        'distanceDiscrepancyPct', 100 * (R.actualDistance - predD) / predD, ...
        'predictedTravelTime_s', predT, ...
        'travelTimeDiscrepancy_s', R.actualFlightTime - predT, ...
        'nLegs', numel(run.legLogs), 'nTargets', nT, ...
        'fullSurveyDistance_m', R.fullSurveyLength);
end

function r = geomRow(k, nAll, algo, dist, tFlight, rl)
    r = struct('targetCount', k, 'frozenSetSize', nAll, 'algorithm', string(algo), ...
        'distance_m', dist, 'flightTime_s', tFlight, ...
        'fullSurveyDistance_m', rl.fullSurveyLength, 'fullSurveyTime_s', rl.fullSurveyFlightTime);
end

function inv = checkInvariance(runsAll, cfgsAll, strategies, conditions)
%CHECKINVARIANCE Gate 3: routing/speed must be the ONLY differences between runs.
    ref = runsAll.historical.fixedOrder;
    refCfg = stripRouting(cfgsAll.historical.fixedOrder);
    inv = struct('sameSurveyFlight', true, 'sameStartState', true, ...
                 'sameDetection', true, 'sameConfigExceptRouting', true, 'sameTargetSet', true);
    for c = 1:numel(conditions)
        for s = 1:numel(strategies)
            run = runsAll.(conditions{c}).(strategies{s});
            cc  = cfgsAll.(conditions{c}).(strategies{s});
            inv.sameSurveyFlight = inv.sameSurveyFlight && isequaln(run.log1, ref.log1);
            inv.sameStartState   = inv.sameStartState && isequaln(run.startXY, ref.startXY);
            inv.sameDetection    = inv.sameDetection && isequaln(run.seen, ref.seen);
            inv.sameTargetSet    = inv.sameTargetSet && isequaln(sortrows(run.targets.XY), sortrows(ref.targets.XY)) ...
                                   && isequaln(sortrows(run.releasePts), sortrows(ref.releasePts));
            inv.sameConfigExceptRouting = inv.sameConfigExceptRouting && isequaln(stripRouting(cc), refCfg);
        end
    end
    inv.allPass = all(structfun(@(x) x, inv));
end

function cfg = stripRouting(cfg)
    cfg.internal2.treat = rmfield(cfg.internal2.treat, {'routing', 'speedFactor'});
end
