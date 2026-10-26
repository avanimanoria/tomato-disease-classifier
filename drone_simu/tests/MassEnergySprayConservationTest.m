function tests = MassEnergySprayConservationTest
%MASSENERGYSPRAYCONSERVATIONTEST Non-negative tank and battery; spray mass balance.
%   emitted = deposited on the grid + evaporated + unresolved, where "unresolved" is the
%   mass beyond the +-4 sigma kernel window or outside the grid (must be >= 0 and small).
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
    c = applyPreset(config(), 'Fully Corrected');
    c.enhancements.enableAdvancedPhysics = true;
    for f = {'payload', 'energy', 'atmosphere', 'actuation', 'dynamics'}, c.enhancements.(f{1}).enabled = true; end
    evalc('fld = generateIrregularField(c);');
    tc.TestData.adv = runInternal2Scenario(c, fld, 'x');
    b = applyPreset(config(), 'Fully Corrected');
    evalc('fb = generateIrregularField(b);');
    tc.TestData.base = runInternal2Scenario(b, fb, 'x');
end

function testTankAndBatteryNonNegative(tc)
    r = tc.TestData.adv;
    logs = [{r.log1}; r.legLogs(:)];
    L = cell2mat(cellfun(@(x) x.advLiquid, logs, 'UniformOutput', false));
    E = cell2mat(cellfun(@(x) x.advEnergy, logs, 'UniformOutput', false));
    verifyGreaterThanOrEqual(tc, min(L), 0);
    verifyLessThanOrEqual(tc, max(L), config().enhancements.payload.tankCapacity_L + 1e-12);
    verifyGreaterThanOrEqual(tc, min(diff(E)), 0);
    verifyGreaterThan(tc, r.advanced.energy_Wh, 0);
end

function testSprayMassBalanceAdvanced(tc)
    checkBalance(tc, tc.TestData.adv.grid, 'advanced');
end

function testSprayMassBalanceLegacy(tc)
    checkBalance(tc, tc.TestData.base.grid, 'legacy');
end

function checkBalance(tc, g, label)
    ev = 0; if isfield(g, 'evaporated_mL'), ev = g.evaporated_mL; end
    unresolved = g.emitted - sum(g.mass(:)) - ev;
    verifyGreaterThanOrEqual(tc, unresolved, -1e-6, [label ': deposited + evaporated exceeds emitted']);
    verifyLessThan(tc, unresolved / g.emitted, 0.01, [label ': more than 1% of emitted spray unaccounted']);
end
