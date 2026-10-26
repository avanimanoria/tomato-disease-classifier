function out = runSprayUncertaintyStudy(outDir, opts)
%RUNSPRAYUNCERTAINTYSTUDY Bounded UNCALIBRATED spray study (manual M4 fallback, Phase 6).
%
%   out = runSprayUncertaintyStudy()                       -> results/spray_uncalibrated_v1
%   out = runSprayUncertaintyStudy(outDir, struct('overwrite', true))
%
%   No compatible deposition / drift measurements were supplied, so the spray model stays
%   UNCALIBRATED and no physically validated deposition is claimed. Instead this study asks
%   whether the simulator's CONCLUSIONS survive bounded changes of the uncalibrated parameters.
%
%   Part A - one-at-a-time sensitivity of the mission engine (Fully Corrected preset, PID):
%     sigmaFraction {0.3 0.5 0.8}, dropletFallSpeed {0.8 1.5 3.0} m/s, driftFactor {0.6 1.0 1.2},
%     releaseHeight {0.6 1.0 1.4} m, windStretch_perMps {0 0.3 0.6} (windStretched kernel);
%     wind 2 and 4 m/s; spray compensation off / on. The ranges are [ASSUMED] bounds around the
%     assumed defaults (not literature-sourced). Reported: target deposition, treatment
%     success, and whether "compensation helps" keeps its sign at every level.
%   Part B - valve delay {0 0.1 0.25 0.5 1.0} s with / without lag compensation:
%     B1 stopped release (mission engine, kinematic vehicle exactly at rest, settle 1 s then 2 s dwell)
%     B2 hover release  (mission engine, vehicle dynamics + 0.3 m/s gusts during the dwell)
%     B3 moving release (KERNEL-LEVEL, no mission: straight pass over one plant at 1.0 / 1.5 /
%        3.0 m/s, valve open while the nozzle footprint is over the canopy, same depositSpray
%        kernel and canopy disc as the engine metrics). Not a mission mode of the engine.
%   Writes partA.csv, partB_engine.csv, partB_moving.csv, summary.md, manifest.json.
%   Refuses to overwrite an existing study (new runs get a new folder).
    here = fileparts(mfilename('fullpath'));
    if nargin < 1 || isempty(outDir), outDir = fullfile(here, 'results', 'spray_uncalibrated_v1'); end
    if nargin < 2, opts = struct(); end
    if isfile(fullfile(outDir, 'manifest.json')) && ~(isfield(opts, 'overwrite') && opts.overwrite)
        error('runSprayUncertaintyStudy:exists', 'Study already exists in %s (use a new folder).', outDir);
    end
    if ~isfolder(outDir), mkdir(outDir); end
    t0 = tic;

    base = applyPreset(config(), 'Fully Corrected');
    evalc('field = generateIrregularField(base);');

    % ---------------- Part A ----------------
    P = {'sigmaFraction', [0.3 0.5 0.8], 0.5; 'dropletFallSpeed', [0.8 1.5 3.0], 1.5; ...
         'driftFactor', [0.6 1.0 1.2], 1.0; 'releaseHeight', [0.6 1.0 1.4], 1.0; ...
         'windStretch_perMps', [0 0.3 0.6], NaN};
    A = table();
    for w = [2 4]
        for i = 1:size(P, 1)
            for lv = P{i, 2}
                for comp = [false true]
                    c = base;
                    c.internal2.wind.speed = w;
                    c.internal2.spray.compensate = comp;
                    if strcmp(P{i, 1}, 'windStretch_perMps')
                        c.enhancements.enableAdvancedPhysics = true;
                        c.enhancements.actuation.enabled = true;
                        c.enhancements.actuation.valveDelay_s = 0;
                        c.enhancements.actuation.kernel = 'windStretched';
                        c.enhancements.actuation.windStretch_perMps = lv;
                    else
                        c.internal2.spray.(P{i, 1}) = lv;
                    end
                    m = mission(c, field);
                    A = [A; table(string(P{i, 1}), lv, lv == P{i, 3}, w, comp, m.dep, m.success, m.off, ...
                        'VariableNames', {'parameter', 'level', 'isDefault', 'wind_mps', 'compensate', ...
                        'targetDeposition_pct', 'treatmentSuccess_pct', 'offTarget_pct'})]; %#ok<AGROW>
                end
            end
        end
    end
    writetable(A, fullfile(outDir, 'partA.csv'));
    % compensation benefit per (parameter, level, wind)
    on = A(A.compensate, :); off = A(~A.compensate, :);
    B = off(:, {'parameter', 'level', 'wind_mps'});
    B.benefit_pp = on.targetDeposition_pct - off.targetDeposition_pct;
    B.successBenefit_pp = on.treatmentSuccess_pct - off.treatmentSuccess_pct;

    % ---------------- Part B1 / B2 (engine) ----------------
    E = table();
    delays = [0 0.1 0.25 0.5 1.0];
    for mode = ["stopped", "hover"]
        for d = delays
            for lag = [0 1]
                if d == 0 && lag == 1, continue; end
                c = base;
                c.enhancements.enableAdvancedPhysics = true;
                c.enhancements.actuation.enabled = true;
                c.enhancements.actuation.valveDelay_s = d;
                c.enhancements.actuation.lagCompensation = lag;
                if mode == "hover"
                    c.enhancements.dynamics.enabled = true;
                    c.enhancements.gusts.enabled = true; c.enhancements.gusts.sigma_mps = 0.3;
                end
                r = runInternal2Scenario(c, field, 'valve');
                m = computeInternal2Metrics(r.cfgEffective, field, r);
                E = [E; table(mode, d, logical(lag), m.spray.targetDepositionPct, 100 * m.spray.treatmentSuccess, ...
                    r.advanced.lagDisplacement_m, 'VariableNames', {'release', 'valveDelay_s', 'lagCompensation', ...
                    'targetDeposition_pct', 'treatmentSuccess_pct', 'lagDisplacement_m'})]; %#ok<AGROW>
            end
        end
    end
    writetable(E, fullfile(outDir, 'partB_engine.csv'));

    % ---------------- Part B3 (moving release, kernel level) ----------------
    M = table();
    S = base.internal2.spray;
    S.footprintRadius = S.releaseHeight * tand(S.nozzleHalfAngle);
    cK = base; cK.internal2.spray = S;
    rc = base.internal2.metrics.canopyRadius;
    for v = [1.0 1.5 3.0]
        for d = delays
            for lag = [0 1]
                if d == 0 && lag == 1, continue; end
                M = [M; table(v, d, logical(lag), movingPass(cK, v, d, lag, rc), ...
                    'VariableNames', {'speed_mps', 'valveDelay_s', 'lagCompensation', 'canopyCapture_pct'})]; %#ok<AGROW>
            end
        end
    end
    writetable(M, fullfile(outDir, 'partB_moving.csv'));

    % ---------------- summary ----------------
    out = struct('partA', A, 'benefit', B, 'engine', E, 'moving', M, 'outDir', outDir, 'runtime_s', toc(t0));
    writeSummary(out, P, fullfile(outDir, 'summary.md'));
    man = struct('study', 'spray_uncalibrated_v1', 'calibration', 'UNCALIBRATED (no deposition data supplied)', ...
        'created', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), 'matlab', version, ...
        'commit', gitHead(here), 'fieldSeed', base.internal2.seed, 'preset', 'Fully Corrected', ...
        'missionsPartA', height(A), 'missionsPartB', height(E), 'kernelCasesPartB3', height(M), ...
        'runtime_s', out.runtime_s);
    fid = fopen(fullfile(outDir, 'manifest.json'), 'w'); fprintf(fid, '%s', jsonencode(man, 'PrettyPrint', true)); fclose(fid);
end

function m = mission(c, field)
    r = runInternal2Scenario(c, field, 'sens');
    ce = c; if isfield(r, 'cfgEffective'), ce = r.cfgEffective; end
    k = computeInternal2Metrics(ce, field, r);
    m = struct('dep', k.spray.targetDepositionPct, 'success', 100 * k.spray.treatmentSuccess, 'off', k.spray.offTargetPct);
end

function pct = movingPass(cfg, v, d, lag, rc)
%MOVINGPASS % of the emitted volume landing on a canopy disc (radius rc) at the origin when the
%   nozzle passes over it at speed v (no wind) and the valve is commanded open while the
%   footprint overlaps the canopy; the flow starts and stops d seconds after the command
%   (lag = 1: commands issued d early, the delay is assumed known).
    S = cfg.internal2.spray; dt = cfg.dt;
    R = S.footprintRadius + rc;                       % nozzle-to-plant distance with overlap
    tOpen = -R / v; tClose = R / v;                   % command window (t = 0 above the plant)
    shift = d * (1 - lag);
    g.cell = 0.01; g.xv = -6:g.cell:6; g.yv = -1:g.cell:1;
    g.mass = zeros(numel(g.yv), numel(g.xv)); g.emitted = 0;
    for t = (tOpen + shift):dt:(tClose + shift - dt / 2)
        g = depositSpray(g, [v * t, 0], [0 0], S.flowRate * dt, cfg);
    end
    [XX, YY] = meshgrid(g.xv, g.yv);
    pct = 100 * sum(g.mass(XX.^2 + YY.^2 <= rc^2)) / max(g.emitted, eps);
end

function writeSummary(o, P, fn)
    A = o.partA; B = o.benefit; E = o.engine; M = o.moving;
    L = {'# Spray model: bounded UNCALIBRATED sensitivity study (spray_uncalibrated_v1)', '', ...
        '> **UNCALIBRATED.** No deposition / drift measurements were supplied. All numbers are relative results', ...
        '> of the simplified Gaussian deposition model inside the stated parameter bounds; they are not physical', ...
        '> validation. The bounds are assumed (around the assumed defaults), not literature-sourced.', '', ...
        sprintf('Runtime %.0f s. Missions: Part A %d, Part B1/B2 %d; Part B3 kernel cases %d.', o.runtime_s, height(A), height(E), height(M)), '', ...
        '## Part A - does "spray compensation helps" survive the parameter bounds?', '', ...
        '| parameter | levels | wind (m/s) | deposition range, comp. off (%) | deposition range, comp. on (%) | compensation benefit range (pp) | sign stable |', ...
        '|---|---|---|---|---|---|---|'};
    for i = 1:size(P, 1)
        for w = [2 4]
            k = B.parameter == P{i, 1} & B.wind_mps == w;
            a0 = A(A.parameter == P{i, 1} & A.wind_mps == w & ~A.compensate, :);
            a1 = A(A.parameter == P{i, 1} & A.wind_mps == w & A.compensate, :);
            b = B.benefit_pp(k);
            L{end+1} = sprintf('| %s | %s | %g | %.1f - %.1f | %.1f - %.1f | %+.1f to %+.1f | %s |', P{i, 1}, ...
                strjoin(string(P{i, 2}), ' / '), w, min(a0.targetDeposition_pct), max(a0.targetDeposition_pct), ...
                min(a1.targetDeposition_pct), max(a1.targetDeposition_pct), min(b), max(b), yesno(all(b > 0) || all(b < 0))); %#ok<AGROW>
        end
    end
    allPos = all(B.benefit_pp > 0);
    L = [L, {'', sprintf('Compensation benefit positive in %d of %d (parameter, level, wind) cells; minimum %+.1f pp, maximum %+.1f pp.', ...
        sum(B.benefit_pp > 0), height(B), min(B.benefit_pp), max(B.benefit_pp)), ...
        ['Conclusion: ' ifelse(allPos, 'the direction of the compensation effect is robust within these bounds; its MAGNITUDE is parameter-dependent and must not be quoted as a physical number.', ...
        'the direction of the compensation effect is NOT robust within these bounds - see the cells with a sign change.')], '', ...
        ['Caveat (self-consistency): the compensator computes its upwind offset with the SAME drift parameters as the ' ...
        'simulated truth, so these benefits are upper bounds for a perfectly known drift model. Wind-knowledge mismatch is ' ...
        'studied separately (Experiment D2, spray.windEstimateScale); fall-speed / drift-factor mismatch is not modelled. ' ...
        'Without compensation, deposition is near zero whenever the drift (wind x height / fall speed x driftFactor) exceeds ' ...
        'the 0.2 m canopy radius, which holds for every level here.'], '', ...
        '## Part B - when can valve-lag compensation matter?', '', ...
        '### B1 / B2 mission engine (stopped release and hover release)', '', ...
        '| release | valve delay (s) | lag comp. | target deposition (%) | treatment success (%) | lag displacement (m) |', '|---|---|---|---|---|---|'}];
    for i = 1:height(E)
        L{end+1} = sprintf('| %s | %.2f | %s | %.1f | %.1f | %.3f |', E.release(i), E.valveDelay_s(i), yesno(E.lagCompensation(i)), ...
            E.targetDeposition_pct(i), E.treatmentSuccess_pct(i), E.lagDisplacement_m(i)); %#ok<AGROW>
    end
    L = [L, {'', '### B3 moving release (kernel-level, not a mission mode)', '', ...
        '| speed (m/s) | valve delay (s) | lag comp. | canopy capture (% of emitted) |', '|---|---|---|---|'}];
    for i = 1:height(M)
        L{end+1} = sprintf('| %.1f | %.2f | %s | %.1f |', M.speed_mps(i), M.valveDelay_s(i), yesno(M.lagCompensation(i)), M.canopyCapture_pct(i)); %#ok<AGROW>
    end
    st = E(E.release == "stopped", :); mv = M(M.speed_mps == 1.5, :);
    lossStop = st.targetDeposition_pct(st.valveDelay_s == 0.5 & ~st.lagCompensation) - st.targetDeposition_pct(st.valveDelay_s == 0);
    lossMove = mv.canopyCapture_pct(mv.valveDelay_s == 0.5 & ~mv.lagCompensation) - mv.canopyCapture_pct(mv.valveDelay_s == 0);
    L = [L, {'', '### Interpretation', '', ...
        sprintf('- Stopped release, 0.5 s delay, no compensation: %+.1f pp target deposition vs. no delay (the drone holds position; the delay mostly shifts flow into the departure).', lossStop), ...
        sprintf('- Moving release at 1.5 m/s, 0.5 s delay, no compensation: %+.1f pp canopy capture vs. no delay (the release is displaced by v x delay = 0.75 m, larger than the canopy).', lossMove), ...
        '- Lag compensation restores the zero-delay result whenever the delay is known and (for the engine) does not exceed the 1 s settle time.', ...
        '- Hence compensation matters most for MOVING release, and for stopped release only when the delay is a large fraction of the dwell or the drone departs while still spraying.', ...
        '- Experiment F (hover release, gusts) measured a 2.1 pp delay effect and listed moving release as an open item (docs/EXPERIMENT_F_AUDIT.md section 5); B3 quantifies that case at kernel level only.'}];
    fid = fopen(fn, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
end

function s = yesno(b), if b, s = 'yes'; else, s = 'no'; end, end
function s = ifelse(c, a, b), if c, s = a; else, s = b; end, end

function h = gitHead(here)
    [st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', here));
    if st ~= 0, h = 'unknown'; end
    h = strtrim(h);
end
