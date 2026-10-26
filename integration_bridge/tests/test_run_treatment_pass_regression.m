function test_run_treatment_pass_regression()
%TEST_RUN_TREATMENT_PASS_REGRESSION Regression and validation suite for runTreatmentPass.

    testDir = fileparts(mfilename('fullpath'));
    bridgeDir = fileparts(testDir);
    rootDir = fileparts(bridgeDir);
    
    addpath(fullfile(rootDir, 'drone_simu'));
    addpath(fullfile(testDir, 'pristine_baseline'));

    fprintf('============================================================\n');
    fprintf('STAGE A: MATLAB Regression & Contract Test Suite\n');
    fprintf('============================================================\n');

    cfg = config();
    field = generateIrregularField(cfg);
    sv = runSurveyPass(cfg, field);
    
    % Deterministic fixture with at least 3 targets inside the field
    assert(height(field.plants) >= 3, 'Field must contain at least 3 plants');
    targsSample.XY = [field.plants.X(1:3), field.plants.Y(1:3)];
    targsSample.ID = field.plants.ID(1:3);
    targsSample.plantIdx = (1:3)';
    nT = size(targsSample.XY, 1);
    dt = cfg.dt;
    fprintf('Deterministic target fixture initialized with nT = %d targets.\n', nT);

    %% 1. Pristine Baseline Comparison under Identical Initial & RNG State
    rng(42, 'twister');
    savedRNG = rng;

    rng(savedRNG);
    tpPristine = runTreatmentPass_pristine(cfg, field, sv, targsSample);

    rng(savedRNG);
    tpPatched = runTreatmentPass(cfg, field, sv, targsSample);

    assert(isequal(tpPristine.order, tpPatched.order), 'Order mismatch with pristine baseline');
    assert(norm(tpPristine.finalWorld.pos - tpPatched.finalWorld.pos) < 1e-12, 'Final position mismatch');
    assert(abs(tpPristine.finalWorld.distance - tpPatched.finalWorld.distance) < 1e-12, 'Final distance mismatch');
    assert(abs(tpPristine.finalWorld.time - tpPatched.finalWorld.time) < 1e-12, 'Final world time mismatch');
    assert(abs(tpPristine.routes.actualDwellTime - tpPatched.routes.actualDwellTime) < 1e-12, 'actualDwellTime mismatch');
    assert(abs(tpPristine.routes.actualTotalTime - tpPatched.routes.actualTotalTime) < 1e-12, 'actualTotalTime mismatch');
    assert(abs(tpPristine.routes.actualFlightTime - tpPatched.routes.actualFlightTime) < 1e-12, 'actualFlightTime mismatch');
    assert(norm(tpPristine.grid.mass(:) - tpPatched.grid.mass(:)) < 1e-12, 'Deposition grid mass mismatch');
    assert(abs(tpPristine.grid.emitted - tpPatched.grid.emitted) < 1e-12, 'Deposition grid emitted mismatch');

    assert(numel(tpPristine.legLogs) == numel(tpPatched.legLogs), 'Leg count mismatch');
    for k = 1:numel(tpPristine.legLogs)
        pLog = tpPristine.legLogs{k};
        mLog = tpPatched.legLogs{k};
        assert(norm(pLog.truePos - mLog.truePos) < 1e-12, sprintf('Leg %d truePos mismatch', k));
        assert(isequal(pLog.phase, mLog.phase), sprintf('Leg %d phase mismatch', k));
        assert(norm(pLog.t - mLog.t) < 1e-12, sprintf('Leg %d timestamp mismatch', k));
    end
    fprintf('[PASS] Test 1: Pristine baseline equivalence confirmed (tol <= 1e-12 across trajectory, world, grid, timing).\n');

    %% 2. Validation Rejection Tests (Matrix, 3D, Empty, NaN, Inf, Negative, Length)
    invalidCases = {
        [], ...                     % Empty when nT > 0
        [1 2; 3 4], ...             % 2x2 matrix when nT = 3
        ones(1, 1, nT), ...         % 3D tensor
        [-0.5; 2.0; 2.0], ...       % Negative value
        [NaN; 2.0; 2.0], ...        % NaN
        [Inf; 2.0; 2.0], ...        % Inf
        [1.0; 2.0] ...              % Length mismatch (2 vs 3)
    };

    for i = 1:numel(invalidCases)
        tBad = targsSample;
        tBad.duration = invalidCases{i};
        caught = false;
        try
            runTreatmentPass(cfg, field, sv, tBad);
        catch ME
            if strcmp(ME.identifier, 'runTreatmentPass:invalidDuration')
                caught = true;
            end
        end
        assert(caught, sprintf('Failed to reject invalid duration case %d', i));
    end
    fprintf('[PASS] Test 2: Invalid duration types, matrix shapes, and non-finite values strictly rejected.\n');

    %% 3. Zero-Target Handling (nT = 0)
    tZero.XY = zeros(0, 2);
    % Case 3A: Missing duration field
    tpZ1 = runTreatmentPass(cfg, field, sv, tZero);
    assert(isempty(tpZ1.legLogs), 'Zero-target run must produce 0 legs');
    assert(tpZ1.routes.actualDwellTime == 0, 'Zero-target dwell time must be 0');

    % Case 3B: Empty vector override
    tZero.duration = [];
    tpZ2 = runTreatmentPass(cfg, field, sv, tZero);
    assert(isempty(tpZ2.legLogs), 'Zero-target run with [] duration must produce 0 legs');

    % Case 3C: Non-empty duration when nT = 0 must fail
    tZero.duration = [1.0];
    caught = false;
    try
        runTreatmentPass(cfg, field, sv, tZero);
    catch ME
        if strcmp(ME.identifier, 'runTreatmentPass:invalidDuration'), caught = true; end
    end
    assert(caught, 'Must reject non-empty duration for nT = 0');
    fprintf('[PASS] Test 3: Zero-target edge cases (missing, [], invalid) verified.\n');

    %% 4. Non-Timestep-Aligned Duration (0.26s) & TargetIdx Contract
    tNonAlign = targsSample;
    % Assign 1.0s to slot 1, 0.26s to slot 2, 0.0s to slot 3
    tNonAlign.duration = [1.0; 0.26; 0.0];

    tpNonAlign = runTreatmentPass(cfg, field, sv, tNonAlign);

    expectedSteps_026 = round(0.26 / dt); % 3 steps
    executedDur_026   = expectedSteps_026 * dt; % 0.30 s
    emittedVol_026_mL = expectedSteps_026 * (cfg.internal2.spray.flowRate * dt); % 7.5 mL

    treatmentLegCount = 0;
    for k = 1:numel(tpNonAlign.legLogs)
        leg = tpNonAlign.legLogs{k};
        if ~isnan(leg.targetIdx)
            assert(isscalar(leg.targetIdx), 'leg.targetIdx must be a scalar');
            slot = leg.targetIdx;
            treatmentLegCount = treatmentLegCount + 1;
            actualPhase3 = sum(leg.phase == 3);
            expectedSteps = round(tNonAlign.duration(slot) / dt);
            assert(actualPhase3 == expectedSteps, ...
                sprintf('Leg %d (targetIdx %d) step count mismatch: got %d, expected %d', ...
                k, slot, actualPhase3, expectedSteps));
            
            if slot == 2
                assert(actualPhase3 == expectedSteps_026, '0.26s target must execute exactly 3 dwell steps');
                assert(abs(actualPhase3 * dt - executedDur_026) < 1e-12, 'Executed dwell must be 0.30s');
                fprintf('  -> Slot 2 (0.26s requested): executed %d steps (%.2fs), emitted %.1f mL\n', ...
                    actualPhase3, actualPhase3 * dt, emittedVol_026_mL);
            elseif slot == 3
                assert(actualPhase3 == 0, '0.0s target must execute exactly 0 dwell steps');
                fprintf('  -> Slot 3 (0.00s requested): executed 0 steps (0.00s), emitted 0.0 mL\n');
            end
        end
    end
    assert(treatmentLegCount == nT, 'Must encounter exactly nT treatment legs');
    
    % Verify actualDwellTime matches executed steps
    totalExecutedDwellSteps = 0;
    for k = 1:numel(tpNonAlign.legLogs)
        totalExecutedDwellSteps = totalExecutedDwellSteps + sum(tpNonAlign.legLogs{k}.phase == 2 | tpNonAlign.legLogs{k}.phase == 3);
    end
    assert(abs(tpNonAlign.routes.actualDwellTime - totalExecutedDwellSteps * dt) < 1e-12, ...
        'routes.actualDwellTime does not match total executed settle+dwell steps');
    fprintf('[PASS] Test 4: Non-aligned duration (0.26s -> 3 steps = 0.30s, 7.5mL) and summary consistency verified.\n');

    %% 5. Refill Accounting with Verified LegKind Contract (Multiple Refills Forced)
    cfgRefill = cfg;
    cfgRefill.enhancements.enableAdvancedPhysics = true;
    cfgRefill.enhancements.payload.enabled = true;
    % Tank capacity 60 mL: holds 1 dose of 50 mL, but forces refill before target 2 and before target 3
    cfgRefill.enhancements.payload.tankCapacity_L = 0.060;
    cfgRefill.enhancements.payload.refillTime_s = 5.0;

    % Build survey pass with refill configuration
    svRefill = runSurveyPass(cfgRefill, field);
    assert(isfield(svRefill.world, 'adv'), 'Survey world must contain advanced state when payload enhancement is enabled');

    tpRefill = runTreatmentPass(cfgRefill, field, svRefill, targsSample);

    refillLegCount = 0;
    treatmentApproachCount = 0;
    for k = 1:numel(tpRefill.legLogs)
        leg = tpRefill.legLogs{k};
        if isnan(leg.targetIdx)
            assert(isfield(leg, 'legKind') && strcmp(leg.legKind, 'refill'), ...
                sprintf('Non-target leg %d must be marked as legKind==refill', k));
            refillLegCount = refillLegCount + 1;
            assert(sum(leg.phase == 3) == 0, 'Refill leg must not actuate spray (phase 3 == 0)');
            assert(sum(leg.phase == 2) == round(5.0 / dt), 'Refill docking settle steps mismatch');
        else
            treatmentApproachCount = treatmentApproachCount + 1;
        end
    end

    assert(refillLegCount >= 2, sprintf('Expected at least 2 refills, got %d', refillLegCount));
    assert(tpRefill.finalWorld.adv.refills == refillLegCount, 'World refill count mismatch');
    assert(treatmentApproachCount == nT, 'Treatment approach count mismatch');

    % Assert actualDwellTime includes refill docking waits without double-counting
    totalSteps = 0;
    for k = 1:numel(tpRefill.legLogs)
        totalSteps = totalSteps + sum(tpRefill.legLogs{k}.phase == 2 | tpRefill.legLogs{k}.phase == 3);
    end
    assert(abs(tpRefill.routes.actualDwellTime - totalSteps * dt) < 1e-12, ...
        'actualDwellTime does not match total executed settle/dwell steps');
    
    fprintf('[PASS] Test 5: Refill accounting verified with %d forced refills (no double counting).\n', refillLegCount);

    fprintf('============================================================\n');
    fprintf('STAGE A PASSED: All 5 MATLAB test suites succeeded!\n');
    fprintf('============================================================\n');
end
