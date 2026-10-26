function tp = runTreatmentPass_pristine(cfg, field, sv, targets)
%RUNTREATMENTPASS Pass 2: route over a GIVEN target set, fly, settle, spray.
%
%   tp = runTreatmentPass(cfg, field, sv, targets)
%
%   sv      : survey-pass result (runSurveyPass) supplying the end world/ctrl
%   targets : struct with XY (Mx2) - from detectPlants, or a frozen set
%
%   Release point = target, or target shifted upwind when
%   cfg.internal2.spray.compensate. Nearest-neighbour order from the
%   ESTIMATED position, straight legs, settle, spray; no per-target return to
%   the survey path. Draws no random numbers.

    I = cfg.internal2;
    S = I.spray;
    dt = cfg.dt;

    [windVel, driftTrue, compVec] = sprayContext(cfg);
    world = sv.world;
    ctrl  = sv.ctrl;
    advAny = advOn(cfg, 'any');        % ENHANCEMENT (opt-in); false = original code path
    if advAny
        [driftTrue, compVec] = advSprayPlan(cfg, world);
    end

    releasePts = targets.XY + compVec;
    nT = size(releasePts, 1);
    grid = initDepositionGrid(cfg, field);
    startXY = getEstimatedState(world, cfg).pos;

    rl = routeLengths(startXY, releasePts, field, cfg);
    routing = I.treat.routing;
    advLen = [];
    switch routing
        case 'nearestNeighbour', order = rl.nnOrder;
        case {'fixedOrder', 'stage7Return'}, order = (1:nT)';
        case {'nearestNeighbour2opt', 'cheapestInsertion', 'nearestNeighbourOrOpt', 'antColony'}
            % ENHANCEMENT (opt-in): only reachable with cfg.enhancements.enableAdvancedRouting
            if ~(isfield(cfg, 'enhancements') && cfg.enhancements.enableAdvancedRouting)
                error('runTreatmentPass:advancedRoutingDisabled', ...
                    'Routing "%s" needs cfg.enhancements.enableAdvancedRouting = true.', routing);
            end
            [order, advLen] = planRouteAdvanced(startXY, releasePts, routing);
        otherwise
            error('runTreatmentPass:badRouting', ...
                'Unknown cfg.internal2.treat.routing "%s" (fixedOrder | nearestNeighbour | stage7Return).', routing);
    end
    returnToSurvey = strcmp(routing, 'stage7Return');
    if isfield(I.treat.speedFactor, routing)
        speedFactor = I.treat.speedFactor.(routing);
    else
        speedFactor = 1.0;            % advanced strategies fly at normal speed
    end

    t2 = world.time;
    d2 = world.distance;
    legLogs = cell(0, 1);
    dwellFcn = @(g, w) depositSpray(g, w.pos, driftTrue, S.flowRate * dt, cfg);
    if advAny
        dwellFcn = @(g, w) advDeposit(g, w, cfg);
    end
    advAct = advAny && advOn(cfg, 'actuation');
    if advAct
        dwellFcn = @(g, w) g;      % ENHANCEMENT: deposition evaluated after the flight with the valve delay (advActuatedDeposition)
    end
    opts = struct('settleTime', I.treat.settleTime, 'dwellTime', S.duration, 'dwellFcn', dwellFcn, ...
                  'speedFactor', speedFactor);
    optsReturn = struct('speedFactor', speedFactor);
    advPay = advAny && advOn(cfg, 'payload');
    extraDwell = 0;
    if advPay
        P = cfg.enhancements.payload;
        dose_L = S.flowRate * S.duration / 1000;
        if P.tankCapacity_L < dose_L
            error('runTreatmentPass:tankTooSmall', 'Tank (%.3f L) is smaller than one dose (%.3f L).', P.tankCapacity_L, dose_L);
        end
        refillXY = field.surveyRef.pts(1, :);     % refill station = take-off point
        optsRefill = struct('settleTime', P.refillTime_s, 'speedFactor', speedFactor);
    end

    % ENHANCEMENT (opt-in): obstacle-aware legs - each leg follows freeSpacePath around
    % no-fly obstacles / concave boundary; a leg with no free path stays straight and is counted.
    freeLegs = isfield(I.treat, 'freeSpaceLegs') && I.treat.freeSpaceLegs;
    nDetour = 0; nBlocked = 0;
    if freeLegs
        obst = {}; if isfield(field, 'obstacles'), obst = field.obstacles; end
        clrL = cfg.internal2.coverage.clearance_m;
    end
    legPts = @(a, b) [a; b];
    if freeLegs, legPts = @(a, b) freeLeg(a, b); end

    nLeg = 0;
    for j = 1:nT
        if advPay && world.adv.liquid_L < dose_L - 1e-12
            % ENHANCEMENT: not enough liquid for the next target -> fly to the refill point, refill, continue
            est = getEstimatedState(world, cfg);
            [world, ctrl, rLog] = flyReference(world, makeReference(legPts(est.pos, refillXY)), ctrl, cfg, optsRefill);
            world.adv.liquid_L = P.tankCapacity_L;
            world.adv.refills = world.adv.refills + 1;
            nLeg = nLeg + 1;
            rLog.legId = nLeg * ones(numel(rLog.t), 1);
            rLog.targetIdx = NaN;
            rLog.legKind = 'refill';
            legLogs{nLeg, 1} = rLog;
            extraDwell = extraDwell + P.refillTime_s;
        end
        est = getEstimatedState(world, cfg);
        legRef = makeReference(legPts(est.pos, releasePts(order(j), :)));
        opts.dwellState = grid;
        [world, ctrl, legLog, grid] = flyReference(world, legRef, ctrl, cfg, opts);
        nLeg = nLeg + 1;
        legLog.legId = nLeg * ones(numel(legLog.t), 1);
        legLog.targetIdx = order(j);
        legLogs{nLeg, 1} = legLog;

        if returnToSurvey
            % Original Stage 7: after spraying, rejoin the nearest survey-path point (from the
            % release point, where the drone just hovered), same travel speed, no dwell.
            est = getEstimatedState(world, cfg);
            nearest = findNearestPathPoint([releasePts(order(j), :), 0], field.surveyPath3);
            retRef = makeReference(legPts(est.pos, nearest(1:2)));
            [world, ctrl, retLog] = flyReference(world, retRef, ctrl, cfg, optsReturn);
            nLeg = nLeg + 1;
            retLog.legId = nLeg * ones(numel(retLog.t), 1);
            retLog.targetIdx = NaN;     % return leg: not a target approach
            legLogs{nLeg, 1} = retLog;
        end
    end

    if advAct
        grid = advActuatedDeposition(grid, cfg, legLogs, world);
    end

    routes = rl;
    routes.routing = routing;
    routes.speedFactor = speedFactor;
    if ~isempty(advLen)
        routes.advancedLength = advLen;   % geometric length of the advanced order (enhancement runs only)
    end
    if freeLegs
        routes.freeSpaceDetours = nDetour;     % legs routed around an obstacle / notch
        routes.freeSpaceBlocked = nBlocked;    % legs with no free path (endpoint outside free field): flown straight
    end
    routes.actualDistance    = world.distance - d2;
    routes.actualTotalTime   = world.time - t2;
    routes.actualDwellTime   = nT * (I.treat.settleTime + S.duration);
    if extraDwell > 0
        routes.actualDwellTime = routes.actualDwellTime + extraDwell;   % refill waits (enhancement runs only)
    end
    routes.actualFlightTime  = routes.actualTotalTime - routes.actualDwellTime;

    tp.windVel     = windVel;
    tp.driftTrue   = driftTrue;
    tp.compVec     = compVec;
    tp.legLogs     = legLogs;
    tp.order       = order;
    tp.releasePts  = releasePts;
    tp.grid        = grid;
    tp.routes      = routes;
    tp.startXY     = startXY;
    tp.finalWorld  = world;

    function P = freeLeg(a, b)
        [P, det] = freeSpacePath(a, b, field.polygon, obst, clrL, 1.5 * clrL);
        if isempty(P)
            P = [a; b]; nBlocked = nBlocked + 1;
        else
            nDetour = nDetour + det;
        end
    end
end
