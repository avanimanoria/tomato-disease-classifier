function [ref, info] = planCoverageDecomposition(pieces, sweepIdx, poly, obstacles, cfg)
%PLANCOVERAGEDECOMPOSITION Pass-1 'polygonDecomposition' coverage planner (opt-in alternative).
%
%   [ref, info] = planCoverageDecomposition(pieces, sweepIdx, poly, obstacles, cfg)
%
%   pieces    cell of Mx2 row pieces (crop rows clipped to the free field, left-to-right)
%   sweepIdx  sweep-line (row) index of each piece
%   poly      field polygon (Nx2, may be concave);  obstacles: cell of Kx2 polygons
%
%   1. Boustrophedon CELL decomposition over the row pieces: a piece continues the cell of the
%      piece on the previous sweep line when their x-intervals overlap one-to-one; a split or
%      merge (concave notch, obstacle) starts a new cell.
%   2. Each cell is covered by a serpentine over its pieces (the crop rows are where the plants
%      are, so the camera must fly along them - observation quality, not just area).
%   3. Cells are visited greedily (nearest entry of 4 serpentine variants) from the legacy start.
%   4. Every connector is a collision-free shortest path (freeSpacePath): straight if the
%      segment keeps `clearance` from the boundary and obstacles, otherwise Dijkstra over a
%      visibility graph of offset polygon / obstacle vertices.
%   5. The whole reference is validated; an infeasible field raises
%      planCoverageDecomposition:infeasible (never clips through an obstacle or boundary).
%   info: nCells, cellOfPiece, connectorLength_m, nDetours, turns, minClearance_m, feasible.
    C = cfg.internal2.coverage;
    clr = C.clearance_m;
    nP = numel(pieces);
    if nP == 0, error('planCoverageDecomposition:infeasible', 'No row pieces to cover.'); end

    % ---- 1. cell decomposition ----
    iv = cell2mat(cellfun(@(p) [min(p(:, 1)), max(p(:, 1))], pieces(:), 'UniformOutput', false));
    cellOf = zeros(nP, 1); nC = 0;
    for i = 1:nP
        prev = find(sweepIdx == sweepIdx(i) - 1);
        ov = prev(iv(prev, 1) <= iv(i, 2) & iv(prev, 2) >= iv(i, 1));
        if numel(ov) == 1
            same = find(sweepIdx == sweepIdx(i));
            succ = same(iv(same, 1) <= iv(ov, 2) & iv(same, 2) >= iv(ov, 1));
            if numel(succ) == 1, cellOf(i) = cellOf(ov); continue; end
        end
        nC = nC + 1; cellOf(i) = nC;
    end

    % ---- 2-3. greedy cell order, serpentine inside each cell ----
    start = pieces{1}(1, :);
    pos = start; pts = start; visited = false(nC, 1);
    conLen = 0; nDet = 0;
    for step = 1:nC
        best = inf;
        for c = find(~visited)'
            idx = find(cellOf == c);
            [~, o] = sort(sweepIdx(idx)); idx = idx(o);
            for up = [true false]
                for leftFirst = [true false]
                    seq = idx; if ~up, seq = flipud(idx); end
                    p1 = orient(pieces{seq(1)}, leftFirst);
                    d = norm(p1(1, :) - pos);
                    if d < best, best = d; bc = c; bseq = seq; bleft = leftFirst; end
                end
            end
        end
        visited(bc) = true;
        lf = bleft;
        for j = 1:numel(bseq)
            P = orient(pieces{bseq(j)}, lf);
            [con, det] = connect(pos, P(1, :));
            pts = [pts; con(2:end, :); P(2:end, :)]; %#ok<AGROW>
            conLen = conLen + sum(vecnorm(diff(con, 1, 1), 2, 2));
            nDet = nDet + det;
            pos = P(end, :); lf = ~lf;
        end
    end

    % ---- 5. validation ----
    ref = makeReference(pts);
    S = densify(ref.pts, 0.05);
    inside = inpolygon(S(:, 1), S(:, 2), poly(:, 1), poly(:, 2));
    for o = 1:numel(obstacles)
        inside = inside & ~inpolygon(S(:, 1), S(:, 2), obstacles{o}(:, 1), obstacles{o}(:, 2));
    end
    if ~all(inside)
        error('planCoverageDecomposition:infeasible', ...
            'Coverage path leaves the free field at %d of %d samples.', sum(~inside), numel(inside));
    end
    th = atan2(ref.segTau(:, 2), ref.segTau(:, 1));
    dth = abs(angle(exp(1i * diff(th))));
    info = struct('method', 'polygonDecomposition', 'nCells', nC, 'cellOfPiece', cellOf, ...
        'connectorLength_m', conLen, 'nDetours', nDet, 'turns', sum(dth > pi / 4), ...
        'minClearance_m', min(clearance(S, poly, obstacles)), 'clearance_m', clr, 'feasible', true);

    function [path, det] = connect(a, b)
        [path, det] = freeSpacePath(a, b, poly, obstacles, clr);
        if isempty(path)
            error('planCoverageDecomposition:infeasible', ...
                'No collision-free connector from (%.1f, %.1f) to (%.1f, %.1f).', a(1), a(2), b(1), b(2));
        end
    end
end

function P = orient(P, leftFirst)
    if xor(P(1, 1) <= P(end, 1), leftFirst), P = flipud(P); end
end

function d = clearance(P, poly, obstacles)
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

function S = densify(P, h)
    S = P(1, :);
    for i = 2:size(P, 1)
        n = max(1, ceil(norm(P(i, :) - P(i - 1, :)) / h));
        t = (1:n)' / n;
        S = [S; P(i - 1, :) + t .* (P(i, :) - P(i - 1, :))]; %#ok<AGROW>
    end
end
