function [path, detour] = freeSpacePath(a, b, poly, obstacles, clr, relax)
%FREESPACEPATH Shortest collision-free polyline from a to b inside poly and outside obstacles.
%
%   [path, detour] = freeSpacePath(a, b, poly, obstacles, clr)
%   [path, detour] = freeSpacePath(a, b, poly, obstacles, clr, relax)
%
%   A point is free when it is inside the field, outside every obstacle and at least 0.9*clr
%   from all their edges. Straight segment if it is free (sampled every 5 cm); otherwise
%   Dijkstra over a visibility graph of polygon / obstacle vertices pushed into free space.
%   relax (m, default 0): within this distance of a or b only the HARD constraint applies
%   (inside field, outside obstacles), so endpoints closer than clr to an edge can connect.
%   path = [] when no free path exists (the caller decides: fail or report); detour = true
%   when the path is not the straight segment.
    if nargin < 6, relax = 0; end
    detour = false;
    seg = @(p, q) segFree(p, q, a, b, poly, obstacles, clr, relax);
    if seg(a, b), path = [a; b]; return; end
    nodes = graphNodes(poly, obstacles, clr);
    path = shortestPath(a, b, nodes, seg);
    detour = ~isempty(path);
end

function ok = segFree(p, q, a, b, poly, obstacles, clr, relax)
    n = max(2, ceil(norm(q - p) / 0.05) + 1);
    t = linspace(0, 1, n)';
    S = p + t .* (q - p);
    hard = inField(S, poly, obstacles);
    if ~all(hard), ok = false; return; end
    near = min(vecnorm(S - a, 2, 2), vecnorm(S - b, 2, 2)) < relax;
    ok = all(near | clearOf(S, poly, obstacles) >= 0.9 * clr);
end

function in = inField(P, poly, obstacles)
    in = inpolygon(P(:, 1), P(:, 2), poly(:, 1), poly(:, 2));
    for o = 1:numel(obstacles)
        in = in & ~inpolygon(P(:, 1), P(:, 2), obstacles{o}(:, 1), obstacles{o}(:, 2));
    end
end

function d = clearOf(P, poly, obstacles)
    d = edgeDist(P, poly);
    for o = 1:numel(obstacles), d = min(d, edgeDist(P, obstacles{o})); end
end

function d = edgeDist(P, poly)
    n = size(poly, 1); d = inf(size(P, 1), 1);
    for e = 1:n
        a = poly(e, :); b = poly(mod(e, n) + 1, :); ab = b - a;
        t = min(max(((P(:, 1) - a(1)) * ab(1) + (P(:, 2) - a(2)) * ab(2)) / dot(ab, ab), 0), 1);
        d = min(d, vecnorm(P - (a + t .* ab), 2, 2));
    end
end

function N = graphNodes(poly, obstacles, clr)
%GRAPHNODES Visibility-graph nodes: each polygon / obstacle vertex pushed into free space.
    N = zeros(0, 2);
    polys = [{poly}, obstacles(:)'];
    for q = 1:numel(polys)
        V = polys{q}; n = size(V, 1);
        for i = 1:n
            a = V(mod(i - 2, n) + 1, :); v = V(i, :); b = V(mod(i, n) + 1, :);
            u = (a - v) / norm(a - v) + (b - v) / norm(b - v);
            if norm(u) < 1e-9, u = [-(b(2) - a(2)), b(1) - a(1)]; end
            u = u / norm(u);
            for s = [1 -1]
                for d = clr * [1.5 2 3 4]
                    c = v + s * d * u;
                    if inField(c, poly, obstacles) && clearOf(c, poly, obstacles) >= 0.9 * clr
                        N(end+1, :) = c; break; %#ok<AGROW>
                    end
                end
            end
        end
    end
end

function path = shortestPath(a, b, nodes, seg)
%SHORTESTPATH Dijkstra over the visibility graph {a, nodes, b}; empty when disconnected.
    V = [a; nodes; b]; n = size(V, 1);
    W = inf(n);
    for i = 1:n
        for j = i + 1:n
            if seg(V(i, :), V(j, :)), W(i, j) = norm(V(i, :) - V(j, :)); W(j, i) = W(i, j); end
        end
    end
    dist = inf(n, 1); dist(1) = 0; prev = zeros(n, 1); done = false(n, 1);
    for it = 1:n
        dd = dist; dd(done) = inf;
        [m, u] = min(dd);
        if isinf(m) || u == n, break; end
        done(u) = true;
        alt = m + W(u, :)';
        better = alt < dist & ~done;
        dist(better) = alt(better); prev(better) = u;
    end
    path = [];
    if isinf(dist(n)), return; end
    k = n; path = V(n, :);
    while k ~= 1, k = prev(k); path = [V(k, :); path]; end %#ok<AGROW>
end
