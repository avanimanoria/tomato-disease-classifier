function [order, totalLength] = planRouteAdvanced(startXY, points, method, seed)
%PLANROUTEADVANCED Optional Pass-2 visiting orders (enhancement; off by default).
%
%   [order, totalLength] = planRouteAdvanced(startXY, points, method [, seed])
%
%   method:
%     'nearestNeighbour2opt'  nearest-neighbour order (planTreatmentRoute, unchanged)
%                             improved by 2-opt segment reversals until no reversal
%                             shortens the route (open path, fixed start)
%     'cheapestInsertion'     start from the drone position; repeatedly insert the
%                             point whose cheapest insertion (between two consecutive
%                             route nodes, or at the end) adds the least length
%     'nearestNeighbourOrOpt' nearest-neighbour + 2-opt, then Or-opt moves (relocate runs of 1-3
%                             consecutive targets) until no move shortens the route
%     'antColony'             ant colony optimisation (open path from the start; 20 ants x 80
%                             iterations, alpha 1, beta 3, evaporation 0.1, elitist deposit) with
%                             2-opt local search on the best route. Seeded (default seed 1) -> deterministic.
%   Straight-line legs, open path (no return to start), deterministic (ties -> lowest
%   index). Only used when cfg.enhancements.enableAdvancedRouting is true; the original
%   strategies (fixedOrder / nearestNeighbour / stage7Return) never call this file.

    M = size(points, 1);
    order = zeros(M, 1);
    totalLength = 0;
    if M == 0, return; end
    s = startXY(:)';

    switch method
        case 'nearestNeighbour2opt'
            order = planTreatmentRoute(s, points);
            order = twoOpt(s, points, order);
        case 'cheapestInsertion'
            order = cheapestInsertion(s, points);
        case 'nearestNeighbourOrOpt'
            order = planTreatmentRoute(s, points);
            order = orOpt(s, points, twoOpt(s, points, order));
        case 'antColony'
            if nargin < 4 || isempty(seed), seed = 1; end
            order = twoOpt(s, points, antColony(s, points, seed));
        otherwise
            error('planRouteAdvanced:badMethod', ...
                'Unknown advanced routing "%s" (nearestNeighbour2opt | cheapestInsertion | nearestNeighbourOrOpt | antColony).', method);
    end
    totalLength = pathLength(s, points, order);
end

function L = pathLength(s, P, order)
    Q = [s; P(order, :)];
    L = sum(vecnorm(diff(Q, 1, 1), 2, 2));
end

function order = twoOpt(s, P, order)
%TWOOPT Open-path 2-opt with a fixed start node; first improvement, repeat to a local optimum.
    M = numel(order);
    if M < 2, return; end
    tol = 1e-12;
    for pass = 1:1000                      % safety cap; converges far earlier in practice
        improved = false;
        Q = [s; P(order, :)];              % node 1 = start, nodes 2..M+1 = targets
        for i = 2:M
            for j = i+1:M+1
                a = Q(i-1, :); b = Q(i, :); c = Q(j, :);
                delta = norm(a - c) - norm(a - b);
                if j < M + 1
                    d = Q(j+1, :);
                    delta = delta + norm(b - d) - norm(c - d);
                end
                if delta < -tol
                    order(i-1:j-1) = order(j-1:-1:i-1);
                    Q = [s; P(order, :)];
                    improved = true;
                end
            end
        end
        if ~improved, break; end
    end
end

function order = cheapestInsertion(s, P)
%CHEAPESTINSERTION Grow an open path from the start by the globally cheapest insertion.
    M = size(P, 1);
    route = zeros(0, 1);                   % indices into P, in visiting order
    left = true(M, 1);
    for step = 1:M
        Q = [s; P(route, :)];
        bestCost = inf; bestPt = 0; bestPos = 0;
        for p = find(left)'
            x = P(p, :);
            for pos = 1:size(Q, 1)         % insert after node pos (pos = size(Q,1) -> append)
                if pos < size(Q, 1)
                    cost = norm(Q(pos, :) - x) + norm(x - Q(pos+1, :)) - norm(Q(pos, :) - Q(pos+1, :));
                else
                    cost = norm(Q(pos, :) - x);
                end
                if cost < bestCost - 1e-12
                    bestCost = cost; bestPt = p; bestPos = pos;
                end
            end
        end
        route = [route(1:bestPos-1); bestPt; route(bestPos:end)];
        left(bestPt) = false;
    end
    order = route;
end

function order = orOpt(s, P, order)
%OROPT Relocate runs of 1-3 consecutive targets to a better position (open path, fixed start).
    M = numel(order);
    if M < 3, return; end
    L0 = pathLength(s, P, order);
    improved = true;
    guard = 0;
    while improved && guard < 500
        improved = false; guard = guard + 1;
        for segLen = 1:3
            for i = 1:M - segLen + 1
                seg = order(i:i+segLen-1);
                rest = order([1:i-1, i+segLen:M]);
                for jpos = 0:numel(rest)
                    if jpos == i - 1, continue; end          % same place
                    for rev = 0:1
                        sg = seg; if rev, sg = flipud(seg(:)); end
                        cand = [rest(1:jpos); sg(:); rest(jpos+1:end)];
                        Lc = pathLength(s, P, cand);
                        if Lc < L0 - 1e-9
                            order = cand; L0 = Lc; improved = true;
                            break;
                        end
                    end
                    if improved, break; end
                end
                if improved, break; end
            end
            if improved, break; end
        end
    end
end

function best = antColony(s, P, seed)
%ANTCOLONY Ant colony optimisation for an open path from s through all points P.
    M = size(P, 1);
    best = (1:M)';
    if M < 2, return; end
    rs = RandStream('mt19937ar', 'Seed', seed);
    nAnts = 20; nIt = 80; alpha = 1; beta = 3; rho = 0.1;
    Q = [s; P];                                         % node 1 = start
    D = sqrt((Q(:, 1) - Q(:, 1)').^2 + (Q(:, 2) - Q(:, 2)').^2);
    eta = 1 ./ max(D, 1e-6);
    Lnn = pathLength(s, P, planTreatmentRoute(s, P));
    tau = ones(M + 1) / (M * Lnn);
    bestL = inf;
    for it = 1:nIt
        itBestL = inf; itBest = [];
        for a = 1:nAnts
            cur = 1; left = true(M + 1, 1); left(1) = false;
            route = zeros(M, 1);
            for step = 1:M
                cand = find(left);
                w = (tau(cur, cand).^alpha) .* (eta(cur, cand).^beta);
                cw = cumsum(w);
                r = rand(rs) * cw(end);
                nxt = cand(find(cw >= r, 1));
                route(step) = nxt - 1;
                left(nxt) = false;
                cur = nxt;
            end
            Lr = pathLength(s, P, route);
            if Lr < itBestL, itBestL = Lr; itBest = route; end
        end
        if itBestL < bestL, bestL = itBestL; best = itBest; end
        tau = (1 - rho) * tau;
        for r2 = {itBest, best}
            rt = [1; r2{1} + 1];
            Lr = pathLength(s, P, r2{1});
            for e = 1:M
                tau(rt(e), rt(e+1)) = tau(rt(e), rt(e+1)) + 1 / Lr;
            end
        end
    end
end
