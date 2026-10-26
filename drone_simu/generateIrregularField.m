function field = generateIrregularField(cfg)
%GENERATEIRREGULARFIELD Internal-2 field: polygon boundary + curved rows.
%
%   field = generateIrregularField(cfg) is the opt-in counterpart of
%   generateField / generatePlants / generateZigZagPath (which are left
%   untouched for Stages 1-7). It reads cfg.internal2.field.* and
%   cfg.rowSpacing / cfg.plantSpacing.
%
%   Geometry:
%     - rows are y = y_k + A*sin(2*pi*x/lambda), clipped to the polygon and
%       trimmed to stay cfg.internal2.field.edgeMargin inside the boundary
%       (so the TURN POINT of each row comes from the boundary, not from a
%       fixed field breadth);
%     - only the LONGEST contiguous run of each row inside the polygon is
%       kept (adequate for convex / mildly non-convex fields; a field that
%       splits a row into separate pieces would lose the shorter piece).
%
%   Returns struct with: polygon, rows (cell of Mx2), plants (table),
%   surveyRef (reference struct), surveyPath3 (Nx3, for
%   findNearestPathPoint), detectU (Nx1 fixed uniform draws), numRows.
%
%   ENHANCEMENTS (opt-in, absent fields = legacy; the legacy field struct is unchanged):
%     cfg.internal2.field.keepAllRuns = true  keep EVERY row piece (concave fields / obstacles)
%     cfg.internal2.field.obstacles   = {Kx2} no-fly / no-crop polygons (pond, pole, building);
%                                     rows are kept edgeMargin away from them
%     cfg.internal2.coverage.method = 'polygonDecomposition'  Pass-1 reference from
%                                     planCoverageDecomposition instead of joined rows
%   Extra outputs only when used: field.obstacles, field.rowSweep, field.coverage.

    I = cfg.internal2;
    poly = I.field.polygon;
    F = I.field;
    keepAll = isfield(F, 'keepAllRuns') && F.keepAllRuns;               % ENHANCEMENT (opt-in)
    obst = {}; if isfield(F, 'obstacles'), obst = F.obstacles; end      % ENHANCEMENT (opt-in)
    covMethod = 'boustrophedon';
    if isfield(I, 'coverage'), covMethod = I.coverage.method; end
    rowSweep = zeros(0, 1);

    xMin = min(poly(:,1)); xMax = max(poly(:,1));
    yMin = min(poly(:,2)); yMax = max(poly(:,2));
    xs = (xMin:F.rowSampleStep:xMax)';

    rows = {};
    y0 = yMin + F.rowFirstOffset;
    k = 0;
    while y0 + k * cfg.rowSpacing <= yMax
        yBase = y0 + k * cfg.rowSpacing;
        yc = yBase + F.rowCurveAmp * sin(2*pi*xs / F.rowCurveLambda);

        inside = inpolygon(xs, yc, poly(:,1), poly(:,2));
        dEdge = pointPolygonDistance([xs, yc], poly);
        ok = inside & (dEdge >= F.edgeMargin);
        for o = 1:numel(obst)                                           % ENHANCEMENT (opt-in)
            Q = obst{o};
            ok = ok & ~inpolygon(xs, yc, Q(:,1), Q(:,2)) & (pointPolygonDistance([xs, yc], Q) >= F.edgeMargin);
        end

        if keepAll, runs = allRuns(ok); else, runs = {longestRun(ok)}; end
        for q = 1:numel(runs)
            run = runs{q};
            if ~isempty(run)
                pts = [xs(run), yc(run)];
                segLen = vecnorm(diff(pts,1,1), 2, 2);
                if sum(segLen) > 2 * cfg.plantSpacing
                    rows{end+1} = pts; %#ok<AGROW>
                    rowSweep(end+1, 1) = k; %#ok<AGROW>
                end
            end
        end
        k = k + 1;
    end

    numRows = numel(rows);
    pieces = rows;                                     % un-flipped, left-to-right (for the planner)
    if numRows == 0
        error('generateIrregularField:noRows', ...
            'No rows fit inside the polygon with the given margin/spacing.');
    end

    % ---- plants along each row (arclength spacing), then direction flip ----
    ID = strings(0,1); X = zeros(0,1); Y = zeros(0,1); RowIdx = zeros(0,1);
    for r = 1:numRows
        pts = rows{r};
        cs = [0; cumsum(vecnorm(diff(pts,1,1), 2, 2))];
        sPl = (0:cfg.plantSpacing:cs(end))';
        px = interp1(cs, pts(:,1), sPl);
        py = interp1(cs, pts(:,2), sPl);
        X = [X; px]; %#ok<AGROW>
        Y = [Y; py]; %#ok<AGROW>
        RowIdx = [RowIdx; r * ones(numel(px),1)]; %#ok<AGROW>
        if mod(r, 2) == 0
            rows{r} = flipud(pts); %#ok<AGROW> boustrophedon
        end
    end
    N = numel(X);
    for i = 1:N
        ID(i,1) = string(sprintf('P%03d', i));
    end

    % ---- ground truth + fixed random draws (private stream, global rng untouched) ----
    stream = RandStream('mt19937ar', 'Seed', I.seed);
    isDis = rand(stream, N, 1) < F.diseaseFraction;
    detectU = rand(stream, N, 1);

    TrueDisease = repmat("HEALTHY", N, 1);
    TrueDisease(isDis) = "DISEASED";

    plants = table(ID, X, Y, RowIdx, TrueDisease);

    % ---- survey reference: rows joined by straight turn connectors ----
    surveyPts = vertcat(rows{:});
    surveyRef = makeReference(surveyPts);
    if strcmp(covMethod, 'polygonDecomposition')        % ENHANCEMENT (opt-in)
        [surveyRef, covInfo] = planCoverageDecomposition(pieces, rowSweep, poly, obst, cfg);
    elseif ~strcmp(covMethod, 'boustrophedon')
        error('generateIrregularField:badCoverage', 'Unknown coverage method "%s".', covMethod);
    end

    field.polygon     = poly;
    field.rows        = rows;
    field.numRows     = numRows;
    field.plants      = plants;
    field.detectU     = detectU;
    field.surveyRef   = surveyRef;
    field.surveyPath3 = [surveyRef.pts, cfg.flightAltitude * ones(size(surveyRef.pts,1),1)];
    if ~isempty(obst), field.obstacles = obst; end
    if keepAll, field.rowSweep = rowSweep; end
    if strcmp(covMethod, 'polygonDecomposition'), field.coverage = covInfo; end

    fprintf('--- INTERNAL-2 FIELD SUMMARY ---\n');
    fprintf('Polygon vertices  : %d (area %.1f m^2)\n', size(poly,1), polyarea(poly(:,1), poly(:,2)));
    fprintf('Rows              : %d (curved, clipped to polygon)\n', numRows);
    fprintf('Total plants      : %d (truly diseased: %d)\n', N, sum(isDis));
    fprintf('Survey path length: %.1f m\n', surveyRef.len);
end

function run = longestRun(mask)
%LONGESTRUN Indices of the longest contiguous true-run in mask.
    run = [];
    if ~any(mask), return; end
    d = diff([0; mask(:); 0]);
    starts = find(d == 1);
    ends   = find(d == -1) - 1;
    [~, i] = max(ends - starts);
    run = (starts(i):ends(i))';
end

function runs = allRuns(mask)
%ALLRUNS Indices of every contiguous true-run in mask, left to right.
    d = diff([0; mask(:); 0]);
    starts = find(d == 1);
    ends   = find(d == -1) - 1;
    runs = arrayfun(@(a, b) (a:b)', starts, ends, 'UniformOutput', false);
    if isempty(runs), runs = {[]}; end
end

function d = pointPolygonDistance(P, poly)
%POINTPOLYGONDISTANCE Distance from each row of P (Nx2) to the polygon edges.
    n = size(poly,1);
    d = inf(size(P,1), 1);
    for e = 1:n
        a = poly(e, :);
        b = poly(mod(e, n) + 1, :);
        ab = b - a;
        t = ((P(:,1) - a(1)) * ab(1) + (P(:,2) - a(2)) * ab(2)) / dot(ab, ab);
        t = min(max(t, 0), 1);
        q = a + t .* ab;
        d = min(d, vecnorm(P - q, 2, 2));
    end
end
