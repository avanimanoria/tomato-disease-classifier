function cm = coverageMetrics(field, cfg, run)
%COVERAGEMETRICS Pass-1 coverage quality of a run (evaluation only, truth-based).
%
%   cm = coverageMetrics(field, cfg, run)
%     plantRecall_pct      plants imaged by the camera / all plants (observation quality)
%     areaCoverage_pct     free field area (inside polygon, outside obstacles) within
%                          cfg.cameraFovRadius of the TRUE survey track, 0.25 m grid
%     missedArea_m2        free area never inside the camera footprint
%     plannedLength_m      survey reference length;  flownLength_m, time_s: Pass 1 as flown
%     turns                reference heading changes > 45 deg
%     boundaryViolation_pct  Pass-1 steps outside the polygon or inside an obstacle (true position)
%     obstacleIncursion_pct  Pass-1 + Pass-2 steps inside an obstacle (true position)
%     plannedFeasible      1 if the planned reference (densified, 5 cm) stays in the free field
%     minClearance_m       planned reference: min distance to boundary / obstacle edges (0 if infeasible)
    poly = field.polygon;
    obst = {}; if isfield(field, 'obstacles'), obst = field.obstacles; end
    p1 = run.log1.truePos;
    cm.plantRecall_pct = 100 * mean(run.seen);
    h = 0.25;
    [XX, YY] = meshgrid(min(poly(:, 1)):h:max(poly(:, 1)), min(poly(:, 2)):h:max(poly(:, 2)));
    G = [XX(:), YY(:)];
    freeG = inpolygon(G(:, 1), G(:, 2), poly(:, 1), poly(:, 2)) & ~inObst(G, obst);
    G = G(freeG, :);
    hit = false(size(G, 1), 1);
    R2 = cfg.cameraFovRadius^2;
    for k = 1:5:size(p1, 1)                       % 0.5 s sub-sampling of the 10 Hz track
        hit = hit | sum((G - p1(k, :)).^2, 2) <= R2;
    end
    cm.areaCoverage_pct = 100 * mean(hit);
    cm.missedArea_m2 = sum(~hit) * h^2;
    ref = field.surveyRef;
    cm.plannedLength_m = ref.len;
    cm.flownLength_m = run.pass1.distance;
    cm.time_s = run.pass1.time;
    th = atan2(ref.segTau(:, 2), ref.segTau(:, 1));
    cm.turns = sum(abs(angle(exp(1i * diff(th)))) > pi / 4);
    out1 = ~inpolygon(p1(:, 1), p1(:, 2), poly(:, 1), poly(:, 2)) | inObst(p1, obst);
    cm.boundaryViolation_pct = 100 * mean(out1);
    allPos = [p1; cell2mat(cellfun(@(L) L.truePos, run.legLogs(:), 'UniformOutput', false))];
    cm.obstacleIncursion_pct = 100 * mean(inObst(allPos, obst));
    S = densify(ref.pts, 0.05);
    cm.plannedFeasible = double(all(inpolygon(S(:, 1), S(:, 2), poly(:, 1), poly(:, 2)) & ~inObst(S, obst)));
    cm.minClearance_m = cm.plannedFeasible * minEdgeDist(S, [{poly}, obst(:)']);
    cm.nCells = 1;
    if isfield(field, 'coverage'), cm.nCells = field.coverage.nCells; end
end

function in = inObst(P, obst)
    in = false(size(P, 1), 1);
    for o = 1:numel(obst), in = in | inpolygon(P(:, 1), P(:, 2), obst{o}(:, 1), obst{o}(:, 2)); end
end

function S = densify(P, h)
    S = P(1, :);
    for i = 2:size(P, 1)
        n = max(1, ceil(norm(P(i, :) - P(i - 1, :)) / h));
        S = [S; P(i - 1, :) + ((1:n)' / n) .* (P(i, :) - P(i - 1, :))]; %#ok<AGROW>
    end
end

function d = minEdgeDist(P, polys)
    d = inf;
    for q = 1:numel(polys)
        V = polys{q}; n = size(V, 1);
        for e = 1:n
            a = V(e, :); b = V(mod(e, n) + 1, :); ab = b - a;
            t = min(max(((P(:, 1) - a(1)) * ab(1) + (P(:, 2) - a(2)) * ab(2)) / dot(ab, ab), 0), 1);
            d = min(d, min(vecnorm(P - (a + t .* ab), 2, 2)));
        end
    end
end
