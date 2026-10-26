function ok = testResearchExtensions(projDir)
%TESTRESEARCHEXTENSIONS Gap-closing extensions from the research charter (all opt-in).
%   Localization estimators (IMU dead reckoning, optical-flow odometry, linear KF),
%   spray-valve delay + lag compensation, wind-stretched kernel, pure-pursuit guidance,
%   ACO / Or-opt routing and the new evaluation metrics. Mode A must stay identical.
    addpath(projDir);
    ok = true;
    function check(cond, msg)
        if cond, fprintf('  PASS  %s\n', msg); else, fprintf('  FAIL  %s\n', msg); ok = false; end
    end
    base = applyPreset(config(), 'Fully Corrected');
    fld = quietField(base);
    rBase = runInternal2Scenario(base, fld, 'x');
    mBase = computeInternal2Metrics(base, fld, rBase);

    fprintf('--- Mode A ---\n');
    c = base;
    c.enhancements.localization.mode = 'kalman'; c.enhancements.guidance.mode = 'purePursuit';
    c.enhancements.actuation.enabled = true; c.enhancements.guidance.enabled = true; c.enhancements.localization.enabled = true;
    check(isequaln(runInternal2Scenario(c, fld, 'x'), rBase), 'new options set but master switch OFF -> original run (bit-identical)');

    fprintf('--- localization estimators ---\n');
    names = {'imuDeadReckoning', 'flowOdometry', 'kalman', 'errorModel'};
    R = struct();
    for i = 1:numel(names)
        cl = feat(base, 'localization'); cl.enhancements.localization.mode = names{i};
        r = runInternal2Scenario(cl, fld, 'x');
        m = computeInternal2Metrics(r.cfgEffective, fld, r);
        R.(names{i}) = struct('rms', r.advanced.estErrRMS_m, 'max', r.advanced.estErrMax_m, 'nees', r.advanced.estNEES, ...
            'cross', m.survey.crossRMSE, 'dep', m.spray.targetDepositionPct, 'viol', r.advanced.boundaryViolationPct);
        fprintf('        %-17s est RMSE %7.3f m (max %7.3f) | NEES %5.2f | true cross-track %6.3f m | deposition %5.1f%% | outside field %5.1f%%\n', ...
            names{i}, R.(names{i}).rms, R.(names{i}).max, R.(names{i}).nees, R.(names{i}).cross, R.(names{i}).dep, R.(names{i}).viol);
    end
    check(R.imuDeadReckoning.rms > R.flowOdometry.rms, 'IMU-only dead reckoning drifts more than optical-flow odometry');
    check(R.kalman.rms < R.flowOdometry.rms, 'Kalman fixes reduce the optical-flow drift');
    check(R.kalman.nees > 0.2 && R.kalman.nees < 10, sprintf('Kalman NEES %.2f in a plausible consistency range (expected ~2)', R.kalman.nees));
    check(R.kalman.cross > mBase.survey.crossRMSE, 'any estimator is worse than the ground-truth oracle');

    fprintf('--- spray actuation (valve delay, lag compensation, kernel) ---\n');
    ca = feat(base, 'actuation');
    c0 = ca; c0.enhancements.actuation.valveDelay_s = 0;
    rA0 = runInternal2Scenario(c0, fld, 'x');
    cAtm = feat(base, 'safety');                          % advisories only: same flight, in-flight deposition (advDeposit)
    rRef = runInternal2Scenario(cAtm, fld, 'x');
    check(max(abs(rA0.grid.mass(:) - rRef.grid.mass(:))) < 1e-12 && abs(rA0.grid.emitted - rRef.grid.emitted) < 1e-9, ...
        'zero delay + gaussian kernel reproduces the in-flight deposition');
    rD = runInternal2Scenario(ca, fld, 'x');
    mD = computeInternal2Metrics(rD.cfgEffective, fld, rD);
    cc = ca; cc.enhancements.actuation.lagCompensation = 1;
    rC = runInternal2Scenario(cc, fld, 'x');
    mC = computeInternal2Metrics(rC.cfgEffective, fld, rC);
    m0 = computeInternal2Metrics(rA0.cfgEffective, fld, rA0);
    fprintf('        delay 0: deposition %.1f%% | delay 0.5 s: %.1f%% (lag displacement %.2f m) | with lag compensation: %.1f%% (%.2f m)\n', ...
        m0.spray.targetDepositionPct, mD.spray.targetDepositionPct, rD.advanced.lagDisplacement_m, mC.spray.targetDepositionPct, rC.advanced.lagDisplacement_m);
    check(rD.advanced.lagDisplacement_m > 0 && mD.spray.targetDepositionPct < m0.spray.targetDepositionPct, 'valve delay displaces spray and lowers target deposition');
    check(abs(mC.spray.targetDepositionPct - m0.spray.targetDepositionPct) < 1e-9 && rC.advanced.lagDisplacement_m == 0, 'lag compensation restores the zero-delay deposition');
    check(abs(rD.grid.emitted - rA0.grid.emitted) < 1e-9, 'delay does not change the emitted volume');
    ck = c0; ck.enhancements.actuation.kernel = 'windStretched';
    rK = runInternal2Scenario(ck, fld, 'x');
    mK = computeInternal2Metrics(rK.cfgEffective, fld, rK);
    fprintf('        wind-stretched kernel (uncalibrated): deposition %.1f%% vs %.1f%% circular\n', mK.spray.targetDepositionPct, m0.spray.targetDepositionPct);
    check(abs(sum(rK.grid.mass(:)) - sum(rA0.grid.mass(:))) / sum(rA0.grid.mass(:)) < 0.02 && ~isequal(rK.grid.mass, rA0.grid.mass), ...
        'stretched kernel redistributes (not creates) deposited volume');

    fprintf('--- path-following controller ---\n');
    cg = feat(base, 'guidance'); cg.enhancements.guidance.mode = 'purePursuit';
    rP = runInternal2Scenario(cg, fld, 'x');
    mP = computeInternal2Metrics(rP.cfgEffective, fld, rP);
    cgp = feat(base, 'guidance');
    rPid = runInternal2Scenario(cgp, fld, 'x');
    fprintf('        pure pursuit cross-track RMSE %.3f m (PID %.3f m), deposition %.1f%%\n', mP.survey.crossRMSE, mBase.survey.crossRMSE, mP.spray.targetDepositionPct);
    check(mP.survey.crossRMSE < 0.3 && ~isequal(rP.log1.truePos, rBase.log1.truePos), 'pure pursuit follows the path and differs from PID');
    check(isequal(rPid.log1.truePos, rBase.log1.truePos), "guidance mode 'pid' flies exactly the original controller");

    fprintf('--- routing: ant colony, Or-opt ---\n');
    st = RandStream('mt19937ar', 'Seed', 5); okR = true; worse = 0;
    for trial = 1:20
        M = randi(st, [3 30]); P = rand(st, M, 2) * 30; s0 = rand(st, 1, 2) * 30;
        [o2, l2] = planRouteAdvanced(s0, P, 'nearestNeighbour2opt');
        [oO, lO] = planRouteAdvanced(s0, P, 'nearestNeighbourOrOpt');
        [oA, lA] = planRouteAdvanced(s0, P, 'antColony');
        [oA2, lA2] = planRouteAdvanced(s0, P, 'antColony');
        okR = okR && isequal(sort(oO), (1:M)') && isequal(sort(oA), (1:M)') && isequal(oA, oA2) && lA == lA2;
        worse = worse + (lO > l2 + 1e-9);
    end
    check(okR, 'ACO and Or-opt return valid permutations; ACO is deterministic for a seed');
    check(worse == 0, 'Or-opt never lengthens the 2-opt route');

    fprintf('--- new metrics present ---\n');
    a = rD.advanced;
    check(all(isfield(a, {'offFieldPct', 'boundaryViolationPct', 'lagDisplacement_m', 'estNEES'})) && a.offFieldPct >= 0 && a.offFieldPct <= 100, ...
        'off-field deposition, boundary violation, lag displacement, NEES reported');

    fprintf('%s\n', ternary(ok, 'RESEARCH EXTENSION CHECKS: PASS', 'RESEARCH EXTENSION CHECKS: FAIL'));
end

function c = feat(c, f)
    c.enhancements.enableAdvancedPhysics = true;
    c.enhancements.(f).enabled = true;
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end

function f = quietField(c)
    evalc('f = generateIrregularField(c);');
end
