function ok = testAdvancedRouting(projDir)
%TESTADVANCEDROUTING Enhancement 1+2: optional routing algorithms behind
%   cfg.enhancements.enableAdvancedRouting (default false).
    addpath(projDir);
    ok = true;
    function check(cond, msg)
        if cond, fprintf('  PASS  %s\n', msg); else, fprintf('  FAIL  %s\n', msg); ok = false; end
    end

    fprintf('--- defaults: original behaviour ---\n');
    c0 = config();
    check(isfield(c0, 'enhancements') && ~c0.enhancements.enableAdvancedRouting, 'enableAdvancedRouting defaults to false');
    check(strcmp(c0.internal2.treat.routing, 'nearestNeighbour'), 'default routing unchanged (nearestNeighbour)');

    cfg = applyPreset(config(), 'Fully Corrected');
    field = quietField(cfg);
    for m = {'nearestNeighbour2opt', 'cheapestInsertion'}
        c = cfg; c.internal2.treat.routing = m{1};
        try
            runInternal2Scenario(c, field, 'x'); check(false, [m{1} ' rejected while the flag is off']);
        catch ME
            check(strcmp(ME.identifier, 'runTreatmentPass:advancedRoutingDisabled'), [m{1} ' rejected while the flag is off']);
        end
    end
    s = struct('wind', true, 'pid', true, 'comp', true, 'windSpeed', 2, 'windDirDeg', 90, 'routing', 'cheapestInsertion', ...
        'droneSpeed', 1.5, 'rowSpacing', 2, 'plantSpacing', 0.5, 'shape', 'Trapezoid', ...
        'rect', struct('length', 30, 'width', 14), 'trap', struct('bottom', 30, 'top', 18, 'height', 14), 'rowStyle', 'Curved');
    try, uiToConfig(s); check(false, 'uiToConfig rejects advanced routing without opt-in');
    catch ME, check(strcmp(ME.identifier, 'uiToConfig:invalid'), 'uiToConfig rejects advanced routing without opt-in'); end
    s.advancedRouting = true;
    cA = uiToConfig(s);
    check(cA.enhancements.enableAdvancedRouting && strcmp(cA.internal2.treat.routing, 'cheapestInsertion'), 'uiToConfig with opt-in sets flag + routing');

    fprintf('--- the flag alone changes nothing ---\n');
    for r = {'fixedOrder', 'nearestNeighbour', 'stage7Return'}
        cOff = cfg; cOff.internal2.treat.routing = r{1};
        cOn = cOff; cOn.enhancements.enableAdvancedRouting = true;
        check(isequaln(runInternal2Scenario(cOff, field, 'x'), runInternal2Scenario(cOn, field, 'x')), ...
            [r{1} ': run with flag ON is bit-identical to flag OFF']);
    end

    fprintf('--- algorithm validity ---\n');
    stream = RandStream('mt19937ar', 'Seed', 11);
    allOk = true; worse = 0; gaps = zeros(0, 3);
    for trial = 1:60
        M = randi(stream, [2 40]);
        P = rand(stream, M, 2) * 30; s0 = rand(stream, 1, 2) * 30;
        [oNN, lNN] = planTreatmentRoute(s0, P);
        [o2, l2] = planRouteAdvanced(s0, P, 'nearestNeighbour2opt');
        [oI, lI] = planRouteAdvanced(s0, P, 'cheapestInsertion');
        allOk = allOk && isequal(sort(o2), (1:M)') && isequal(sort(oI), (1:M)') ...
            && abs(l2 - plen(s0, P, o2)) < 1e-9 && abs(lI - plen(s0, P, oI)) < 1e-9;
        worse = worse + (l2 > lNN + 1e-9);
        if M <= 7
            opt = bruteForce(s0, P);
            gaps(end+1, :) = [lNN / opt, l2 / opt, lI / opt] - 1; %#ok<AGROW>
        end
        [o2b, l2b] = planRouteAdvanced(s0, P, 'nearestNeighbour2opt');
        allOk = allOk && isequal(o2b, o2) && l2b == l2;
    end
    check(allOk, '60 random sets: valid permutations, reported length = path length, deterministic');
    check(worse == 0, '2-opt never longer than plain nearest-neighbour');
    check(all(gaps(:) >= -1e-9), sprintf('brute-force optimum is a lower bound on %d small sets', size(gaps, 1)));
    fprintf('        mean excess over optimum on small sets: NN %.1f%% | NN+2opt %.1f%% | insertion %.1f%%\n', 100 * mean(gaps));

    fprintf('--- flown runs on the frozen all-diseased target set (Experiment-C setup, equal speed) ---\n');
    cB = config(); cB.internal2.enabled = true; cB.enhancements.enableAdvancedRouting = true;
    fB = quietField(cB);
    P = fB.plants; idx = frozenTargetOrder(fB);
    tgt = struct('plantIdx', idx, 'ID', P.ID(idx), 'XY', [P.X(idx), P.Y(idx)], ...
        'detectTime', zeros(numel(idx), 1), 'isTruePositive', true(numel(idx), 1));
    names = {'fixedOrder', 'nearestNeighbour', 'nearestNeighbour2opt', 'cheapestInsertion'};
    runs = cell(1, 4);
    fprintf('        %-22s %12s %12s %12s\n', 'strategy', 'geometric m', 'flown m', 'travel s');
    for i = 1:4
        c = cB; c.internal2.treat.routing = names{i};
        runs{i} = runInternal2Scenario(c, fB, names{i}, struct('targets', tgt));
        R = runs{i}.routes;
        switch names{i}
            case 'fixedOrder', g = R.detOrderLength;
            case 'nearestNeighbour', g = R.nnLength;
            otherwise, g = R.advancedLength;
        end
        fprintf('        %-22s %12.2f %12.2f %12.1f\n', names{i}, g, R.actualDistance, R.actualFlightTime);
    end
    same1 = all(cellfun(@(r) isequaln(r.log1, runs{1}.log1) && isequaln(r.startXY, runs{1}.startXY), runs));
    check(same1, 'identical survey flight and start state for every strategy (routing isolated)');
    check(runs{3}.routes.advancedLength <= runs{2}.routes.nnLength + 1e-9, '2-opt geometric route <= nearest-neighbour route');

    fprintf('--- dashboard ---\n');
    app = AgriculturalDroneDashboardV2('Visible', 'off', 'AutoPlay', false);
    cl = onCleanup(@() delete(app));
    check(~app.AdvRoutingCheck.Value && isequal(app.RoutingDropDown.Items, {'fixedOrder', 'nearestNeighbour', 'stage7Return'}), ...
        'checkbox off by default; dropdown shows only the original three strategies');
    app.AdvRoutingCheck.Value = true; app.AdvRoutingCheck.ValueChangedFcn([], []);
    check(numel(app.RoutingDropDown.Items) == 7, 'opt-in adds the four advanced strategies');
    app.RoutingDropDown.Value = 'nearestNeighbour2opt';
    app.setSwitches(true, true, true);
    app.generateField(); app.startMission();
    check(strcmp(app.mode, 'PLAYING') && strcmp(app.run.routes.routing, 'nearestNeighbour2opt') && app.cfg.enhancements.enableAdvancedRouting, ...
        'dashboard mission runs with the advanced strategy');
    app.tickOnce(1e9);
    check(strcmp(app.mode, 'DONE'), 'advanced-routing mission replays to completion');
    app.resetMission();
    app.AdvRoutingCheck.Value = false; app.AdvRoutingCheck.ValueChangedFcn([], []);
    check(strcmp(app.RoutingDropDown.Value, 'nearestNeighbour') && numel(app.RoutingDropDown.Items) == 3, ...
        'opting out restores the original list and falls back to nearestNeighbour');

    fprintf('%s\n', ternary(ok, 'ADVANCED ROUTING CHECKS: PASS', 'ADVANCED ROUTING CHECKS: FAIL'));
end

function L = plen(s, P, o)
    Q = [s; P(o, :)];
    L = sum(vecnorm(diff(Q, 1, 1), 2, 2));
end

function best = bruteForce(s, P)
    pr = perms(1:size(P, 1));
    best = inf;
    for i = 1:size(pr, 1)
        best = min(best, plen(s, P, pr(i, :)'));
    end
end

function f = quietField(c)
    evalc('f = generateIrregularField(c);');
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end
