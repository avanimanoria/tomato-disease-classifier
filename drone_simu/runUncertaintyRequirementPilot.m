function out = runUncertaintyRequirementPilot(outDir, opts)
%RUNUNCERTAINTYREQUIREMENTPILOT Reduced-order uncertainty-requirement falsification pilot.
%
%   out = runUncertaintyRequirementPilot()        -> results/uncertainty_requirement_pilot_v1
%   out = runUncertaintyRequirementPilot(outDir, struct('overwrite', true, 'N', 2e5))
%
%   STANDALONE: does not call or modify the mission engine. Model (per sample):
%     e_loc   ~ N(0, sigma_loc^2 I)
%     e_spray = [b 0] + eps,  eps ~ N(0, diag(sx^2, sy^2))   (isotropic: sx = sy = sigma_spray)
%     p_land  = e_loc + e_spray;   capture = p_land inside the target (disc radius R, or ellipse)
%   Monte Carlo with COMMON RANDOM NUMBERS: one master seed draws Z_loc, Z_spray (N x 2 standard
%   normals) once; every cell and intervention scales the same draws. Isotropic cells are checked
%   against the analytical Rice / Rayleigh capture probability.
%
%   Prespecified decision thresholds (set before running):
%     tieTol   = 0.005  two interventions within 0.5 pp capture are a TIE
%     material = 0.02   an intervention "materially helps" if it adds >= 2 pp capture
%   Interventions: loc  sigma_loc -> 0.5 sigma_loc;  spray  (sx, sy) -> 0.5 (sx, sy);
%                  bias b -> 0.5 b. Inapplicable (parameter already 0) => not a candidate.
    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(outDir), outDir = fullfile(here, 'results', 'uncertainty_requirement_pilot_v1'); end
    if nargin < 2, opts = struct(); end
    if ~isfield(opts, 'N'), opts.N = 2e5; end
    if isfile(fullfile(outDir, 'manifest.json')) && ~(isfield(opts, 'overwrite') && opts.overwrite)
        error('runUncertaintyRequirementPilot:exists', 'Pilot already exists in %s (use a new folder).', outDir);
    end
    figDir = fullfile(outDir, 'figures'); if ~isfolder(figDir), mkdir(figDir); end
    t0 = tic;
    P.seed = 20261011; P.N = opts.N; P.tieTol = 0.005; P.material = 0.02;
    P.R = [0.10 0.20 0.40 0.80]; P.sl = [0 0.02 0.05 0.10 0.20 0.40];
    P.ss = [0 0.05 0.10 0.20 0.40 0.80]; P.b = [0 0.10 0.25 0.50];
    Z = draws(P.seed, P.N);

    % ================= primary grid (576 cells) =================
    C = table(); IV = table();
    for R = P.R, for b = P.b, for sl = P.sl, for ss = P.ss
        s = sys(sl, ss, ss, b);
        [pc, me, p95] = capture(Z, s, R, R);
        pa = riceCapture(sqrt(sl^2 + ss^2), b, R);
        C = [C; table(R, sl, ss, b, sqrt(sl^2 + ss^2), sqrt(2 * sl^2 + 2 * ss^2 + b^2), pc, pa, me, p95, ...
            'VariableNames', {'R_m', 'sigma_loc_m', 'sigma_spray_m', 'bias_m', 'sigma_total_m', 'rmsLanding_m', ...
            'P_capture', 'P_capture_analytic', 'meanLanding_m', 'p95Landing_m'})]; %#ok<AGROW>
        IV = [IV; interventions(Z, s, R, R, pc, P)]; %#ok<AGROW>
    end, end, end, end
    IV = [C(:, {'R_m', 'sigma_loc_m', 'sigma_spray_m', 'bias_m', 'P_capture'}), IV];
    BP = baselines(IV, P);
    writetable(C, fullfile(outDir, 'parameter_cells.csv'));
    writetable(IV, fullfile(outDir, 'intervention_values.csv'));
    writetable(BP, fullfile(outDir, 'baseline_predictions.csv'));
    sumBase = summarize(BP, IV, P, "primary grid (circular, isotropic)");

    % ================= non-triviality challenges =================
    % A anisotropic spray at EQUAL total spray variance: sx^2 + sy^2 = 2 sigma^2, ratio sx:sy = k
    % B elliptical / row-like target at EQUAL AREA (pi R^2), aspect 1, 2, 4, major axis along x
    %   (= bias / wind direction) or along y; combined with anisotropy
    % C bias vs scatter at matched RMS landing error
    % D smooth outcome: UNCALIBRATED Gaussian deposition kernel (sigma_k = engine default
    %   0.5 x footprint radius 0.268 m = 0.134 m) - fraction of sprayed mass on the canopy
    R0 = 0.20;
    CH = table(); CHB = table();
    sgrid = [0.02 0.05 0.10 0.20 0.40]; bgrid = [0 0.10 0.25];
    for k = [1 2 4]
        for asp = [1 2 4]
            for ori = ["x", "y"]
                if asp == 1 && ori == "y", continue; end
                [ax, ay] = ellipseAxes(R0, asp, ori);
                for b = bgrid, for sl = sgrid, for ss = sgrid
                    sx = ss * sqrt(2 * k^2 / (1 + k^2)); sy = ss * sqrt(2 / (1 + k^2));
                    s = sys(sl, sx, sy, b);
                    pc = capture(Z, s, ax, ay);
                    v = interventions(Z, s, ax, ay, pc, P);
                    row = table(k, asp, ori, R0, sl, ss, sx, sy, b, pc, 'VariableNames', {'anisotropy', 'targetAspect', ...
                        'targetMajorAxis', 'R_equivArea_m', 'sigma_loc_m', 'sigma_spray_m', 'sx_m', 'sy_m', 'bias_m', 'P_capture'});
                    CH = [CH; [row, v]]; %#ok<AGROW>
                end, end, end
            end
        end
    end
    CHB = baselines([CH(:, {'R_equivArea_m', 'sigma_loc_m', 'sigma_spray_m', 'bias_m', 'P_capture'}), ...
        CH(:, {'d_loc', 'd_spray', 'd_bias', 'best', 'bestValue', 'nCandidates', 'tie'})], P);
    CHB = [CH(:, {'anisotropy', 'targetAspect', 'targetMajorAxis'}), CHB];
    writetable(CH, fullfile(outDir, 'challenge_anisotropy_geometry.csv'));
    writetable(CHB, fullfile(outDir, 'challenge_baseline_predictions.csv'));
    % per (anisotropy, aspect, orientation): does the isotropic-circle answer still hold?
    GS = table();
    iso = CH.anisotropy == 1 & CH.targetAspect == 1;
    for k = [1 2 4], for asp = [1 2 4], for ori = ["x", "y"]
        m = CH.anisotropy == k & CH.targetAspect == asp & CH.targetMajorAxis == ori;
        if ~any(m), continue; end
        flip = CH.best(m) ~= CH.best(iso) & ~CH.tie(m) & ~CH.tie(iso) & CH.bestValue(m) >= P.material;
        A = CHB(m, :);
        GS = [GS; table(k, asp, ori, sum(m), sum(flip), mean(A.A_correct), mean(A.C_correct), max(A.A_regret), max(A.C_regret), ...
            'VariableNames', {'anisotropy', 'targetAspect', 'targetMajorAxis', 'cells', 'bestFlipsVsIsoCircle', ...
            'A_accuracy', 'C_accuracy', 'A_maxRegret', 'C_maxRegret'})]; %#ok<AGROW>
    end, end, end
    writetable(GS, fullfile(outDir, 'challenge_summary.csv'));

    % C bias vs scatter at matched RMS landing error (R = 0.20, sigma_loc = sigma_spray = s)
    BS = table();
    for rms = [0.10 0.20 0.30 0.50]
        for f = [0 0.25 0.5 0.75 0.9 1.0]
            b = sqrt(f) * rms; sgm = sqrt((1 - f) * rms^2 / 4);
            s = sys(sgm, sgm, sgm, b);
            pc = capture(Z, s, R0, R0);
            v = interventions(Z, s, R0, R0, pc, P);
            BS = [BS; [table(rms, f, sgm, b, sqrt(2 * sgm^2 + 2 * sgm^2 + b^2), pc, 'VariableNames', ...
                {'rmsLanding_m', 'biasVarianceFraction', 'sigma_each_m', 'bias_m', 'rmsCheck_m', 'P_capture'}), v]]; %#ok<AGROW>
        end
    end
    writetable(BS, fullfile(outDir, 'bias_vs_scatter.csv'));

    % D smooth deposition (UNCALIBRATED kernel), R = 0.20, isotropic: mass fraction on canopy
    sk = 0.5 * (1.0 * tand(15));                         % sigma_k = sigmaFraction 0.5 x footprint radius 0.268 m
    DS = table();
    for b = [0 0.10 0.25], for sl = sgrid, for ss = sgrid
        s = sys(sl, ss, ss, b); sK = sys(sl, sqrt(ss^2 + sk^2), sqrt(ss^2 + sk^2), b);
        pc = capture(Z, s, R0, R0);
        pd = capture(Z, sK, R0, R0);   % Gaussian kernel = extra isotropic scatter sigma_k (exact identity)
        vb = interventions(Z, s, R0, R0, pc, P);
        vd = interventionsKernel(Z, sl, ss, b, sk, R0, pd, P);
        DS = [DS; table(b, sl, ss, pc, pd, vb.best, vd.best, vb.tie | vd.tie, vb.bestValue, vd.bestValue, ...
            'VariableNames', {'bias_m', 'sigma_loc_m', 'sigma_spray_m', 'P_capture', 'massFractionOnCanopy', ...
            'best_capture', 'best_smooth', 'anyTie', 'value_capture', 'value_smooth'})]; %#ok<AGROW>
    end, end, end
    writetable(DS, fullfile(outDir, 'smooth_deposition.csv'));

    % ================= sanity checks =================
    SC = sanity(C, IV, Z, P, here, outDir);
    writetable(SC, fullfile(outDir, 'sanity_checks.csv'));

    % ================= figures, report, manifest =================
    figures(C, IV, CH, BS, P, figDir);
    out = struct('cells', C, 'interventions', IV, 'baselines', BP, 'summary', sumBase, 'challenge', CH, ...
        'challengeBaselines', CHB, 'challengeSummary', GS, 'biasScatter', BS, 'smooth', DS, 'sanity', SC, ...
        'P', P, 'sigmaKernel', sk, 'outDir', outDir, 'runtime_s', toc(t0));
    writeReport(out, fullfile(outDir, 'report.md'));
    man = struct('experiment', 'uncertainty_requirement_pilot_v1', 'model', 'reduced-order Monte Carlo (NOT the mission engine)', ...
        'masterSeed', P.seed, 'samplesPerCell', P.N, 'commonRandomNumbers', true, 'tieTol', P.tieTol, 'material', P.material, ...
        'gridCells', height(C), 'challengeCells', height(CH), 'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        'matlab', version, 'commit', gitHead(here), 'sanityAllPass', all(SC.pass), 'runtime_s', out.runtime_s, ...
        'icaerus', 'not used for any parameter (context only, see report)');
    fid = fopen(fullfile(outDir, 'manifest.json'), 'w'); fprintf(fid, '%s', jsonencode(man, 'PrettyPrint', true)); fclose(fid);
end

% =====================================================================================
function Z = draws(seed, N)
    rs = RandStream('mt19937ar', 'Seed', seed);
    Z.loc = randn(rs, N, 2); Z.spray = randn(rs, N, 2);
end

function s = sys(sl, sx, sy, b), s = struct('sl', sl, 'sx', sx, 'sy', sy, 'b', b); end

function [pc, me, p95] = capture(Z, s, ax, ay)
%CAPTURE P(landing inside the axis-aligned ellipse with semi-axes ax (x), ay (y)); disc if ax = ay.
    x = s.sl * Z.loc(:, 1) + s.sx * Z.spray(:, 1) + s.b;
    y = s.sl * Z.loc(:, 2) + s.sy * Z.spray(:, 2);
    pc = mean((x / ax).^2 + (y / ay).^2 <= 1);
    if nargout > 1, d = sqrt(x.^2 + y.^2); me = mean(d); p95 = prctile(d, 95); end
end

function v = interventions(Z, s, ax, ay, pc, P)
    c = struct('loc', s.sl > 0, 'spray', s.sx > 0 || s.sy > 0, 'bias', s.b > 0);
    d = nan(1, 3);
    if c.loc, t = s; t.sl = 0.5 * s.sl; d(1) = capture(Z, t, ax, ay) - pc; end
    if c.spray, t = s; t.sx = 0.5 * s.sx; t.sy = 0.5 * s.sy; d(2) = capture(Z, t, ax, ay) - pc; end
    if c.bias, t = s; t.b = 0.5 * s.b; d(3) = capture(Z, t, ax, ay) - pc; end
    v = decide(d, P);
end

function v = interventionsKernel(Z, sl, ss, b, sk, R, pd, P)
%INTERVENTIONSKERNEL Same interventions on the smooth (kernel) outcome; the kernel width is NOT improved.
    d = nan(1, 3);
    f = @(a, c, bb) capture(Z, sys(a, sqrt(c^2 + sk^2), sqrt(c^2 + sk^2), bb), R, R);
    if sl > 0, d(1) = f(0.5 * sl, ss, b) - pd; end
    if ss > 0, d(2) = f(sl, 0.5 * ss, b) - pd; end
    if b > 0, d(3) = f(sl, ss, 0.5 * b) - pd; end
    v = decide(d, P);
end

function v = decide(d, P)
    names = ["loc", "spray", "bias"];
    ok = ~isnan(d);
    if ~any(ok)
        best = "none"; bv = 0; tie = false;
    else
        dd = d; dd(~ok) = -inf;
        [bv, i] = max(dd);
        best = names(i);
        tie = sum(ok & dd >= bv - P.tieTol) > 1;
        if bv < P.material, best = "none (" + names(i) + ")"; end
    end
    v = table(d(1), d(2), d(3), best, bv, sum(ok), tie, 'VariableNames', ...
        {'d_loc', 'd_spray', 'd_bias', 'best', 'bestValue', 'nCandidates', 'tie'});
end

function BP = baselines(IV, P)
%BASELINES A largest random sigma; B the same normalised by R; C largest reduction of total RMS
%   sqrt(sl^2 + ss^2 + b^2) = halve the largest of (sl, ss, b). A / B can only pick loc or spray.
    n = height(IV); pA = strings(n, 1); pB = pA; pC = pA;
    for i = 1:n
        sl = IV.sigma_loc_m(i); ss = IV.sigma_spray_m(i); b = IV.bias_m(i); R = IV{i, 1};
        pA(i) = ifelse(sl > ss, "loc", "spray");
        pB(i) = ifelse(sl / R > ss / R, "loc", "spray");
        [~, j] = max([sl ss b]); nm = ["loc", "spray", "bias"]; pC(i) = nm(j);
    end
    D = [IV.d_loc, IV.d_spray, IV.d_bias];
    val = @(p) D(sub2ind(size(D), (1:n)', double(p == "loc") + 2 * double(p == "spray") + 3 * double(p == "bias")));
    best = max(D, [], 2, 'omitnan'); best(isnan(best)) = 0;
    vA = val(pA); vB = val(pB); vC = val(pC);
    vA(isnan(vA)) = 0; vB(isnan(vB)) = 0; vC(isnan(vC)) = 0;  % inapplicable prediction = no gain
    rA = best - vA; rB = best - vB; rC = best - vC;
    relevant = IV.nCandidates >= 2 & best >= P.material;
    BP = table(pA, pB, pC, rA, rB, rC, rA <= P.tieTol, rB <= P.tieTol, rC <= P.tieTol, relevant, ...
        'VariableNames', {'A_pred', 'B_pred', 'C_pred', 'A_regret', 'B_regret', 'C_regret', 'A_correct', 'B_correct', ...
        'C_correct', 'decisionRelevant'});
    BP = [IV(:, 1:4), BP];
end

function S = summarize(BP, IV, P, name)
    rel = BP.decisionRelevant; nonTie = rel & ~IV.tie;
    S = table(name, height(BP), sum(rel), sum(rel & IV.tie), ...
        mean(BP.A_correct(rel)), mean(BP.B_correct(rel)), mean(BP.C_correct(rel)), ...
        mean(BP.A_correct(nonTie)), mean(BP.C_correct(nonTie)), max(BP.A_regret), max(BP.C_regret), ...
        mean(BP.A_pred == BP.B_pred), 'VariableNames', {'set', 'cells', 'decisionRelevant', 'relevantTies', ...
        'A_acc', 'B_acc', 'C_acc', 'A_acc_nonTie', 'C_acc_nonTie', 'A_maxRegret', 'C_maxRegret', 'B_equals_A'});
end

function [ax, ay] = ellipseAxes(R, asp, ori)
    a = R * sqrt(asp); c = R / sqrt(asp);               % equal area pi R^2
    if ori == "x", ax = a; ay = c; else, ax = c; ay = a; end
end

function p = riceCapture(sig, b, R)
%RICECAPTURE Analytical P(||N([b 0], sig^2 I)|| <= R): Rayleigh for b = 0, Rice otherwise.
    if sig == 0, p = double(b <= R + 1e-12); return; end
    if b == 0, p = 1 - exp(-R^2 / (2 * sig^2)); return; end
    f = @(r) r / sig^2 .* exp(-(r - b).^2 / (2 * sig^2)) .* besseli(0, r * b / sig^2, 1);
    p = integral(f, 0, R, 'AbsTol', 1e-12, 'RelTol', 1e-10);
end

function SC = sanity(C, IV, Z, P, here, outDir)
    chk = {};
    se = 4 * sqrt(0.25 / P.N);                       % 4 x max binomial SE
    chk(end+1, :) = {'P_capture within [0, 1]', all(C.P_capture >= 0 & C.P_capture <= 1), ''};
    G = sortrows(C, {'sigma_loc_m', 'sigma_spray_m', 'bias_m', 'R_m'});
    mono = true;
    for i = 1:4:height(G), mono = mono && all(diff(G.P_capture(i:i + 3)) >= -1e-12); end
    chk(end+1, :) = {'increasing R never reduces capture (exact under common random numbers)', mono, ''};
    z = C.sigma_loc_m == 0 & C.sigma_spray_m == 0 & C.bias_m == 0;
    chk(end+1, :) = {'R > 0, b = 0, both sigmas 0 => P_capture = 1', all(C.P_capture(z) == 1), ''};
    sw = true; mx = 0;
    for i = find(C.bias_m == 0)'
        j = find(C.bias_m == 0 & C.R_m == C.R_m(i) & C.sigma_loc_m == C.sigma_spray_m(i) & C.sigma_spray_m == C.sigma_loc_m(i));
        if ~isempty(j), mx = max(mx, abs(C.P_capture(i) - C.P_capture(j))); end
    end
    sw = mx <= se;
    chk(end+1, :) = {'b = 0: swapping sigma_loc and sigma_spray leaves P_capture unchanged (MC tolerance)', sw, sprintf('max diff %.4f, tol %.4f', mx, se)};
    e = IV.bias_m == 0 & IV.sigma_loc_m == IV.sigma_spray_m & IV.sigma_loc_m > 0;
    md = max(abs(IV.d_loc(e) - IV.d_spray(e)));
    chk(end+1, :) = {'equal sigmas, b = 0: equal intervention values (MC tolerance)', md <= se, sprintf('max diff %.4f', md)};
    ea = max(abs(C.P_capture - C.P_capture_analytic));
    chk(end+1, :) = {'Monte Carlo vs analytical Rayleigh / Rice capture, all 576 cells (tol 4 SE)', ea <= se, sprintf('max |MC - analytic| %.4f, tol %.4f', ea, se)};
    e0 = max(abs(C.P_capture(C.bias_m == 0) - C.P_capture_analytic(C.bias_m == 0)));
    chk(end+1, :) = {'zero-bias cells vs analytical Rayleigh baseline', e0 <= se, sprintf('max %.4f', e0)};
    Z2 = draws(P.seed, P.N);
    chk(end+1, :) = {'common random numbers: identical draws regenerated from the stored seed', isequal(Z2.loc, Z.loc) && isequal(Z2.spray, Z.spray), ''};
    r1 = capture(Z, sys(0.05, 0.2, 0.2, 0.1), 0.2, 0.2); r2 = capture(Z2, sys(0.05, 0.2, 0.2, 0.1), 0.2, 0.2);
    chk(end+1, :) = {'exact reproducibility of a cell from the stored seed', r1 == r2, sprintf('%.6f', r1)};
    rel = strrep(outDir(numel(here) + 2:end), '\', '/');
    [~, st] = system(sprintf('git -C "%s" status --porcelain', here));
    lines = strtrim(strsplit(strtrim(st), newline)); lines = lines(~cellfun(@isempty, lines));
    other = lines(~contains(lines, rel) & ~contains(lines, 'runUncertaintyRequirementPilot.m'));
    chk(end+1, :) = {'no existing source / results modified (git status: only this runner and its folder)', isempty(other), strjoin(other, '; ')};
    evalc('tr = runtests(fullfile(here, ''tests'', ''FrozenExperimentIntegrityTest.m''));');
    chk(end+1, :) = {'frozen checksums unchanged (FrozenExperimentIntegrityTest)', all([tr.Passed]), ''};
    SC = cell2table(chk, 'VariableNames', {'check', 'pass', 'detail'});
end

function figures(C, IV, CH, BS, P, figDir)
    sl = P.sl; ss = P.ss;
    % 1 + 2: R = 0.20, b = 0 slice
    m = IV.R_m == 0.20 & IV.bias_m == 0;
    T = IV(m, :);
    [B, V] = slice(T, sl, ss);
    fh = figure('Visible', 'off', 'Position', [50 50 1300 560], 'Color', 'w');
    tl = tiledlayout(fh, 1, 2, 'TileSpacing', 'compact');
    ax = nexttile(tl);
    cm = [0.85 0.85 0.85; 0.20 0.45 0.85; 0.90 0.50 0.15; 0.55 0.75 0.55];
    imagesc(ax, 1:6, 1:6, B'); colormap(ax, cm); clim(ax, [0.5 4.5]); axis(ax, 'xy');
    set(ax, 'XTick', 1:6, 'XTickLabel', string(sl), 'YTick', 1:6, 'YTickLabel', string(ss));
    xlabel(ax, '\sigma_{loc} (m)'); ylabel(ax, '\sigma_{spray} (m)');
    lab = ["none / <2 pp", "localization", "spray", "tie"];
    for i = 1:6, for j = 1:6, text(ax, i, j, lab(B(i, j)), 'HorizontalAlignment', 'center', 'FontSize', 8); end, end
    title(ax, 'Best 50 % improvement (R = 0.20 m, b = 0)');
    ax = nexttile(tl);
    imagesc(ax, 1:6, 1:6, 100 * V'); axis(ax, 'xy'); colormap(ax, parula); cb = colorbar(ax); cb.Label.String = 'capture gain (pp)';
    set(ax, 'XTick', 1:6, 'XTickLabel', string(sl), 'YTick', 1:6, 'YTickLabel', string(ss));
    for i = 1:6, for j = 1:6, text(ax, i, j, sprintf('%.1f', 100 * V(i, j)), 'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', 'w'); end, end
    xlabel(ax, '\sigma_{loc} (m)'); ylabel(ax, '\sigma_{spray} (m)');
    title(ax, 'Value of best improvement max(\Delta_{loc}, \Delta_{spray})');
    title(tl, 'Reduced-order uncertainty model (NOT the mission engine; sensitivity values, not measured crop data)');
    exportgraphics(fh, fullfile(figDir, '01_02_crossover_and_value_R020_b0.png'), 'Resolution', 150); close(fh);
    % 3: radius comparison
    fh = figure('Visible', 'off', 'Position', [50 50 1500 420], 'Color', 'w');
    tl = tiledlayout(fh, 1, 4, 'TileSpacing', 'compact');
    for R = P.R
        T = IV(IV.R_m == R & IV.bias_m == 0, :);
        [B, V] = slice(T, sl, ss);
        ax = nexttile(tl);
        imagesc(ax, 1:6, 1:6, 100 * V'); axis(ax, 'xy'); clim(ax, [0 40]); colormap(ax, parula);
        set(ax, 'XTick', 1:6, 'XTickLabel', string(sl), 'YTick', 1:6, 'YTickLabel', string(ss), 'FontSize', 7);
        L = 'xLST'; % x none, L loc, S spray, T tie
        for i = 1:6, for j = 1:6, text(ax, i, j, L(B(i, j)), 'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold'); end, end
        title(ax, sprintf('R = %.2f m', R)); xlabel(ax, '\sigma_{loc}'); ylabel(ax, '\sigma_{spray}');
    end
    cb = colorbar(ax); cb.Label.String = 'best gain (pp)';
    title(tl, 'Value of the best 50 % improvement vs target radius (b = 0). L loc, S spray, T tie, x < 2 pp');
    exportgraphics(fh, fullfile(figDir, '03_target_radius_comparison.png'), 'Resolution', 150); close(fh);
    % 4: bias vs scatter
    fh = figure('Visible', 'off', 'Position', [50 50 1200 460], 'Color', 'w');
    tl = tiledlayout(fh, 1, 2, 'TileSpacing', 'compact');
    ax = nexttile(tl); hold(ax, 'on');
    for rms = unique(BS.rmsLanding_m)'
        k = BS.rmsLanding_m == rms;
        plot(ax, BS.biasVarianceFraction(k), 100 * BS.P_capture(k), '-o', 'LineWidth', 1.5, 'DisplayName', sprintf('RMS landing %.2f m', rms));
    end
    xlabel(ax, 'bias share of mean-square landing error  b^2 / E||p||^2'); ylabel(ax, 'P_{capture} (%)'); grid(ax, 'on');
    legend(ax, 'Location', 'best'); title(ax, 'Equal RMS landing error, different composition (R = 0.20 m)');
    ax = nexttile(tl); hold(ax, 'on');
    k = BS.rmsLanding_m == 0.30;
    bar(ax, categorical(string(BS.biasVarianceFraction(k))), 100 * [BS.d_loc(k), BS.d_spray(k), BS.d_bias(k)]);
    legend(ax, {'\Delta loc', '\Delta spray', '\Delta bias'}, 'Location', 'best'); grid(ax, 'on');
    xlabel(ax, 'bias share'); ylabel(ax, 'capture gain (pp)'); title(ax, 'Intervention values at RMS 0.30 m');
    exportgraphics(fh, fullfile(figDir, '04_bias_vs_scatter.png'), 'Resolution', 150); close(fh);
    % 5: anisotropy / geometry: share of decision-relevant cells whose best intervention differs from iso-circle
    fh = figure('Visible', 'off', 'Position', [50 50 1100 460], 'Color', 'w');
    ax = axes(fh); hold(ax, 'on');
    iso = CH.anisotropy == 1 & CH.targetAspect == 1;
    lbl = strings(0); val = [];
    for k = [1 2 4], for asp = [1 2 4], for ori = ["x", "y"]
        m = CH.anisotropy == k & CH.targetAspect == asp & CH.targetMajorAxis == ori;
        if ~any(m) || (k == 1 && asp == 1), continue; end
        fl = CH.best(m) ~= CH.best(iso) & ~CH.tie(m) & ~CH.tie(iso) & CH.bestValue(m) >= P.material;
        lbl(end+1) = sprintf('spray %d:1, target %d:1 %s', k, asp, ori); val(end+1) = 100 * mean(fl); %#ok<AGROW>
    end, end, end
    barh(ax, categorical(lbl, lbl), val); grid(ax, 'on');
    xlabel(ax, '% of cells where the best intervention changes vs isotropic spray + circular target');
    title(ax, 'Anisotropy / target-geometry effect on the preferred intervention (R_{eq} = 0.20 m, equal area, equal spray variance)');
    exportgraphics(fh, fullfile(figDir, '05_anisotropy_geometry.png'), 'Resolution', 150); close(fh);
end

function [B, V] = slice(T, sl, ss)
    B = ones(6); V = zeros(6);
    for i = 1:6, for j = 1:6
        r = T(T.sigma_loc_m == sl(i) & T.sigma_spray_m == ss(j), :);
        dl = r.d_loc; ds = r.d_spray; if isnan(dl), dl = -inf; end, if isnan(ds), ds = -inf; end
        V(i, j) = max([dl, ds, 0]);
        if V(i, j) < 0.02, B(i, j) = 1;
        elseif abs(dl - ds) <= 0.005, B(i, j) = 4;
        elseif dl > ds, B(i, j) = 2; else, B(i, j) = 3; end
    end, end
end

function writeReport(o, fn)
    S = o.summary; SC = o.sanity; P = o.P;
    L = {'# Cross-layer uncertainty requirement map - falsification pilot (uncertainty_requirement_pilot_v1)', '', ...
        '> Reduced-order Monte Carlo model, NOT the mission engine. Grid values are sensitivity values, not measured crop', ...
        '> or sensor properties. Within this simplified uncertainty model only.', '', ...
        sprintf('Seed %d, %d samples per cell, common random numbers; thresholds prespecified: tie %.1f pp, material %.0f pp. Runtime %.0f s. Sanity: %s.', ...
        P.seed, P.N, 100 * P.tieTol, 100 * P.material, o.runtime_s, ifelse(all(SC.pass), 'ALL PASS', 'FAILURES')), '', ...
        '## Baseline accuracy (primary grid)', '', ...
        '| set | cells | decision-relevant | of which ties | A acc. | B acc. | C acc. | A acc. (non-tie) | C acc. (non-tie) | A max regret | C max regret | B == A |', ...
        '|---|---|---|---|---|---|---|---|---|---|---|---|', ...
        sprintf('| %s | %d | %d | %d | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f | %.3f |', S.set, S.cells, S.decisionRelevant, S.relevantTies, ...
        S.A_acc, S.B_acc, S.C_acc, S.A_acc_nonTie, S.C_acc_nonTie, S.A_maxRegret, S.C_maxRegret, S.B_equals_A), '', ...
        'decision-relevant = at least 2 applicable interventions and best gain >= 2 pp. Correct = regret <= tie tolerance.', '', ...
        '## Anisotropy / geometry challenge summary (R_eq = 0.20 m)', '', ...
        '| spray anisotropy | target aspect | major axis | cells | best flips vs iso-circle | A acc. | C acc. | A max regret | C max regret |', '|---|---|---|---|---|---|---|---|---|'};
    G = o.challengeSummary;
    for i = 1:height(G)
        L{end+1} = sprintf('| %d:1 | %d:1 | %s | %d | %d | %.3f | %.3f | %.3f | %.3f |', G.anisotropy(i), G.targetAspect(i), G.targetMajorAxis(i), ...
            G.cells(i), G.bestFlipsVsIsoCircle(i), G.A_accuracy(i), G.C_accuracy(i), G.A_maxRegret(i), G.C_maxRegret(i)); %#ok<AGROW>
    end
    BS = o.biasScatter;
    L = [L, {'', '## Bias vs scatter at matched RMS landing error (R = 0.20 m)', '', ...
        '| RMS landing (m) | bias share | sigma each (m) | bias (m) | P_capture | d loc | d spray | d bias | best |', '|---|---|---|---|---|---|---|---|---|'}];
    for i = 1:height(BS)
        L{end+1} = sprintf('| %.2f | %.2f | %.3f | %.3f | %.3f | %+.3f | %+.3f | %+.3f | %s |', BS.rmsLanding_m(i), BS.biasVarianceFraction(i), ...
            BS.sigma_each_m(i), BS.bias_m(i), BS.P_capture(i), BS.d_loc(i), BS.d_spray(i), BS.d_bias(i), BS.best(i)); %#ok<AGROW>
    end
    D = o.smooth;
    ch = D.best_capture ~= D.best_smooth & ~D.anyTie & D.value_capture >= P.material & D.value_smooth >= P.material;
    L = [L, {'', sprintf(['## Smooth outcome (UNCALIBRATED Gaussian kernel, sigma_k = %.3f m)', newline, newline, ...
        'A Gaussian deposition kernel is exactly equivalent to adding sigma_k to the spray scatter (convolution of Gaussians), so it is not an independent mechanism. ', ...
        'Best intervention differs from binary capture in %d of %d cells where both are decision-relevant and untied; ', ...
        'cells where binary capture shows a material gain but the smooth outcome does not: %d.'], o.sigmaKernel, sum(ch), ...
        sum(~D.anyTie & D.value_capture >= P.material & D.value_smooth >= P.material), ...
        sum(D.value_capture >= P.material & D.value_smooth < P.material)), '', ...
        '## Sanity checks', '', '| check | pass | detail |', '|---|---|---|'}];
    for i = 1:height(SC), L{end+1} = sprintf('| %s | %s | %s |', SC.check{i}, ifelse(SC.pass(i), 'PASS', 'FAIL'), SC.detail{i}); end %#ok<AGROW>
    L = [L, {'', '<!-- ANALYST ANSWERS: written after reviewing the tables above -->'}];
    fid = fopen(fn, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
end

function s = ifelse(c, a, b), if c, s = a; else, s = b; end, end

function h = gitHead(here)
    [st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', here));
    if st ~= 0, h = 'unknown'; end
    h = strtrim(h);
end
