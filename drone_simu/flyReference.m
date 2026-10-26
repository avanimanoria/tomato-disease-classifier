function [world, ctrl, log, dwellState] = flyReference(world, ref, ctrl, cfg, opts)
%FLYREFERENCE Fly a polyline reference, then optionally settle and dwell.
%
%   [world, ctrl, log, dwellState] = flyReference(world, ref, ctrl, cfg, opts)
%
%   The reference point advances along `ref` at cfg.droneSpeed (time-
%   parametrised). Each step:
%       est  = getEstimatedState(world)            (what the drone knows)
%       vCmd = pidCrossTrackController(est, ref)   (what is commanded)
%       world = stepVehicle(world, vCmd, wind)     (what actually happens)
%   Phases: 1 = travel along ref, 2 = settle at the end point, 3 = dwell
%   (hold at end point; opts.dwellFcn is called after every dwell step).
%
%   opts (all optional): settleTime (s), dwellTime (s),
%        dwellFcn   - @(dwellState, world) -> dwellState
%        dwellState - initial state handed to dwellFcn
%        speedFactor - multiplies cfg.droneSpeed for the travel phase (default 1)
%
%   log fields (one row per step): t, truePos, estPos, refPos, vCmd,
%   cross (signed cross-track vs active segment, m), eAlong (reference
%   minus estimate along tangent, m), posErr (|true - time-indexed ref|, m),
%   phase.

    if nargin < 5 || isempty(opts), opts = struct(); end
    settle = optGet(opts, 'settleTime', 0);
    dwell  = optGet(opts, 'dwellTime', 0);
    dwellFcn   = optGet(opts, 'dwellFcn', []);
    dwellState = optGet(opts, 'dwellState', []);

    v  = cfg.droneSpeed * optGet(opts, 'speedFactor', 1);
    dt = cfg.dt;
    W  = cfg.internal2.metrics.crossTrackWindow;

    nTravel = ceil(ref.len / (v * dt));
    nSettle = round(settle / dt);
    nDwell  = round(dwell / dt);
    nTot = nTravel + nSettle + nDwell;

    log.t        = zeros(nTot, 1);
    log.truePos  = zeros(nTot, 2);
    log.estPos   = zeros(nTot, 2);
    log.refPos   = zeros(nTot, 2);
    log.vCmd     = zeros(nTot, 2);
    log.cross    = zeros(nTot, 1);
    log.eAlong   = zeros(nTot, 1);
    log.posErr   = zeros(nTot, 1);
    log.phase    = zeros(nTot, 1);
    adv = isfield(world, 'adv');       % ENHANCEMENT (opt-in): extra telemetry, payload draw-down
    if adv
        log.advMass   = zeros(nTot, 1);
        log.advLiquid = zeros(nTot, 1);
        log.advEnergy = zeros(nTot, 1);
        log.advEstErr = zeros(nTot, 2);
        log.advWind   = zeros(nTot, 2);
        log.advEstVar = zeros(nTot, 1);
        if isfield(world.adv, 'sf'), log.advEstP = zeros(nTot, 3); end   % EKF position covariance [Pxx Pxy Pyy]
    end

    usePP = adv && advOn(cfg, 'guidance') && strcmp(cfg.enhancements.guidance.mode, 'purePursuit');   % ENHANCEMENT (opt-in)
    ctrl.prevCross = NaN; % derivative restarts each leg; integral carries over
    [pEnd, tauEnd] = sampleReference(ref, ref.len);

    for k = 1:nTot
        windVel = windVector(cfg, world.time);
        est = getEstimatedState(world, cfg);

        if k <= nTravel
            s = min((k - 1) * v * dt, ref.len);
            [pRef, tau] = sampleReference(ref, s);
            vFF = v * tau;
            phase = 1;
        else
            s = ref.len;
            pRef = pEnd;
            tau = tauEnd;
            vFF = [0 0];
            if k <= nTravel + nSettle
                phase = 2;
            else
                phase = 3;
            end
        end

        if usePP
            [vCmd, dg] = purePursuitController(est.pos, ref, s, pRef, tau, v, k > nTravel, cfg);
        else
            [vCmd, ctrl, dg] = pidCrossTrackController(est.pos, pRef, tau, vFF, ctrl, cfg);
        end
        cross = crossTrackToReference(ref, world.pos, s, W);

        log.t(k)         = world.time;
        log.truePos(k,:) = world.pos;
        log.estPos(k,:)  = est.pos;
        log.refPos(k,:)  = pRef;
        log.vCmd(k,:)    = vCmd;
        log.cross(k)     = cross;
        log.eAlong(k)    = dg.eAlong;
        log.posErr(k)    = norm(world.pos - pRef);
        log.phase(k)     = phase;
        if adv
            log.advMass(k)     = advMass(world, cfg);
            log.advLiquid(k)   = world.adv.liquid_L;
            log.advEnergy(k)   = world.adv.energy_J;
            log.advEstErr(k,:) = world.adv.estErr;
            log.advWind(k,:)   = windVel;
            log.advEstVar(k)   = world.adv.P;
            if isfield(world.adv, 'sf'), log.advEstP(k, :) = world.adv.sf.P([1 2 8]); end   % (1,1) (2,1) (2,2) of the 6x6 covariance
        end

        world = stepVehicle(world, vCmd, windVel, cfg);
        if adv && phase == 3 && world.adv.payloadOn      % tank empties at the pump flow rate while spraying
            world.adv.liquid_L = max(0, world.adv.liquid_L - cfg.internal2.spray.flowRate * dt / 1000);
        end

        if phase == 3 && ~isempty(dwellFcn)
            dwellState = dwellFcn(dwellState, world);
        end
    end
end

function val = optGet(opts, name, default)
    if isfield(opts, name)
        val = opts.(name);
    else
        val = default;
    end
end
