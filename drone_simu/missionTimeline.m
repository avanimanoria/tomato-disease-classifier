function tl = missionTimeline(cfg, field, run)
%MISSIONTIMELINE Flatten one Internal-2 run into a per-step replay timeline.
%
%   tl = missionTimeline(cfg, field, run)
%
%   Nothing is re-simulated: every array is the concatenation of the stored logs
%   (run.log1 = survey, run.legLogs = Pass 2), in order, one entry per step.
%
%   INFORMATION BOUNDARY: this is Mission-mode code. It uses only what the drone
%   could know: its own logged positions, plant coordinates, the camera footprint
%   radius, and the detector's OUTPUT (run.targets.plantIdx = the plants it flagged).
%   It never reads the hidden disease labels or any ground-truth evaluation metric.
%
%   Per step: pos (position), t, cross (signed cross-track, m), cumDist (flown
%   distance, m), stage (1 survey, 2 transit, 3 settle, 4 spraying), ord (Pass-2 target
%   ordinal, 0 in Pass 1; a return leg keeps the ordinal of the target just treated),
%   isReturn, tgtPlant (plant row of the current Pass-2 target, 0 in Pass 1),
%   obsPlant (the plant shown as "current observation": the most recently observed
%   plant; if several plants are first covered at the same step the LOWEST plant row
%   is shown - a UI-only rule, the engine's ordering is untouched),
%   sprayDone (completed spray events), sprayStepsCum (cumulative spraying steps).
%   Per plant: firstStep (step the camera footprint first covered it, 0 = never) and
%   flagStep (step the detector flagged it, 0 = not flagged).

    pos = run.log1.truePos;
    t = run.log1.t;
    cross = run.log1.cross;
    stage = ones(size(pos, 1), 1);
    ord = zeros(size(pos, 1), 1);
    isRet = false(size(pos, 1), 1);
    tgtPlant = zeros(size(pos, 1), 1);
    n1 = size(pos, 1);
    isRef = false(n1, 1); refNo = zeros(n1, 1); nRef = 0;
    hasAdv = isfield(run.log1, 'advMass');           % advanced-physics telemetry (enhancement runs only)
    if hasAdv
        am = run.log1.advMass; al = run.log1.advLiquid; ae = run.log1.advEnergy;
        ar = vecnorm(run.log1.advEstErr, 2, 2); aw = vecnorm(run.log1.advWind, 2, 2);
    end

    cur = 0; curPlant = 0;
    for j = 1:numel(run.legLogs)
        L = run.legLogs{j};
        n = numel(L.t);
        refill = isfield(L, 'legKind') && strcmp(L.legKind, 'refill');
        ret = isnan(L.targetIdx) && ~refill;
        if refill, nRef = nRef + 1; end
        if ~isnan(L.targetIdx)
            cur = cur + 1;
            curPlant = run.targets.plantIdx(L.targetIdx);
        end
        pos = [pos; L.truePos]; %#ok<AGROW>
        t = [t; L.t]; %#ok<AGROW>
        cross = [cross; L.cross]; %#ok<AGROW>
        stage = [stage; 1 + L.phase]; %#ok<AGROW>
        ord = [ord; cur * ones(n, 1)]; %#ok<AGROW>
        isRet = [isRet; repmat(ret, n, 1)]; %#ok<AGROW>
        tgtPlant = [tgtPlant; curPlant * ones(n, 1)]; %#ok<AGROW>
        isRef = [isRef; repmat(refill, n, 1)]; %#ok<AGROW>
        refNo = [refNo; nRef * ones(n, 1)]; %#ok<AGROW>
        if hasAdv
            am = [am; L.advMass]; al = [al; L.advLiquid]; ae = [ae; L.advEnergy]; %#ok<AGROW>
            ar = [ar; vecnorm(L.advEstErr, 2, 2)]; aw = [aw; vecnorm(L.advWind, 2, 2)]; %#ok<AGROW>
        end
    end

    tl.pos = pos;
    tl.t = t;
    tl.cross = cross;
    tl.stage = stage;
    tl.ord = ord;
    tl.isReturn = isRet;
    tl.tgtPlant = tgtPlant;
    tl.isRefill = isRef;
    tl.refillNo = refNo;
    if hasAdv
        E = cfg.enhancements;
        tl.adv = struct('mass', am, 'liquid', al, 'energyWh', ae / 3600, 'estErr', ar, 'wind', aw, 'refillNo', refNo, ...
            'tankCap', E.payload.tankCapacity_L, 'batteryWh', E.energy.battery_Wh, ...
            'energyOn', advOn(cfg, 'energy'), 'locOn', advOn(cfg, 'localization'));
    end
    tl.n1 = n1;
    tl.N = size(pos, 1);
    tl.cumDist = [0; cumsum(vecnorm(diff(pos, 1, 1), 2, 2))];
    tl.nTargets = size(run.releasePts, 1);
    tl.dt = cfg.dt;
    tl.nPlants = height(field.plants);

    % observation: first step at which the camera footprint (true position) covers a plant
    P = field.plants;
    R2 = cfg.cameraFovRadius^2;
    p1 = run.log1.truePos;
    within = ((P.X - p1(:, 1)') .^ 2 + (P.Y - p1(:, 2)') .^ 2) <= R2;   % plants x steps
    [seen, idx] = max(within, [], 2);
    tl.firstStep = idx .* seen;
    tl.flagStep = zeros(tl.nPlants, 1);
    tl.flagStep(run.targets.plantIdx) = tl.firstStep(run.targets.plantIdx);

    % "current observation" per step (deterministic UI rule: lowest plant row at a tie)
    obsAt = zeros(tl.N, 1);
    steps = unique(tl.firstStep(tl.firstStep > 0));
    for s = steps(:)'
        obsAt(s) = find(tl.firstStep == s, 1, 'first');
    end
    lastIdx = cummax((obsAt > 0) .* (1:tl.N)');
    tl.obsPlant = zeros(tl.N, 1);
    has = lastIdx > 0;
    tl.obsPlant(has) = obsAt(lastIdx(has));

    % treatment bookkeeping derived from the replay prefix only
    sp = stage == 4;
    ends = sp & [stage(2:end) ~= 4; true];
    tl.sprayDone = cumsum(ends);
    tl.sprayStepsCum = cumsum(sp);
    tl.emitPerStep_mL = cfg.internal2.spray.flowRate * cfg.dt;

    % survey row index from reference arclength s(k) = min((k-1)*v*dt, len)
    cnt = cumsum(cellfun(@(r) size(r, 1), field.rows(:)));
    tl.numRows = field.numRows;
    if size(field.surveyRef.pts, 1) == cnt(end)
        tl.rowEnd = field.surveyRef.cs(cnt);
    else
        tl.rowEnd = [];                    % cannot map arclength to rows reliably
    end
    tl.refStep = cfg.droneSpeed * cfg.dt;
    tl.refLen = field.surveyRef.len;
    tl.routing = cfg.internal2.treat.routing;
end
