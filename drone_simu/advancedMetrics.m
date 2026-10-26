function m = advancedMetrics(cfg, field, sv, tp)
%ADVANCEDMETRICS Payload / energy / environment / localization / safety numbers of an advanced run.
%   Only computed when advOn(cfg,'any'); original runs never contain run.advanced.
    E = cfg.enhancements;
    logs = [{sv.log1}; tp.legLogs(:)];
    cat = @(f) cell2mat(cellfun(@(L) L.(f), logs, 'UniformOutput', false));
    t = cat('t'); mass = cat('advMass'); liq = cat('advLiquid'); en = cat('advEnergy');
    err = cat('advEstErr'); wnd = cat('advWind'); ph = cat('phase');
    isP2 = [false(numel(sv.log1.t), 1); true(numel(t) - numel(sv.log1.t), 1)];

    w = tp.finalWorld.adv;
    m.features = struct();
    for f = advFeatures(), m.features.(f{1}) = advOn(cfg, f{1}); end
    m.massStart_kg = mass(1);
    m.massEnd_kg = advMass(tp.finalWorld, cfg);
    m.tankCapacity_L = E.payload.tankCapacity_L;
    m.liquidEnd_L = w.liquid_L;
    m.pumped_L = tp.grid.emitted / 1000;
    m.refills = w.refills;
    if isfield(tp.grid, 'evaporated_mL'), m.evaporated_mL = tp.grid.evaporated_mL; else, m.evaporated_mL = 0; end
    m.evaporatedPct = 100 * safeDiv(m.evaporated_mL, tp.grid.emitted);
    m.plannedDriftDistance_m = norm(tp.driftTrue);
    m.compensationOffset_m = norm(tp.compVec);
    if advOn(cfg, 'energy')
        m.energy_Wh = w.energy_J / 3600;
        m.batteryUsedPct = 100 * m.energy_Wh / E.energy.battery_Wh;
        m.batteryLeftPct = 100 - m.batteryUsedPct;
        m.meanPower_W = w.energy_J / max(t(end), eps);
    else
        m.energy_Wh = NaN; m.batteryUsedPct = NaN; m.batteryLeftPct = NaN; m.meanPower_W = NaN;
    end
    ws = vecnorm(wnd, 2, 2);
    m.maxWind_mps = max(ws);
    m.maxWindWhileSpraying_mps = max([0; ws(isP2 & ph == 3)]);
    ee = vecnorm(err, 2, 2);
    m.estErrRMS_m = sqrt(mean(ee.^2));
    m.estErrMax_m = max(ee);
    m.fieldArea_ha = polyarea(field.polygon(:, 1), field.polygon(:, 2)) / 1e4;
    m.doseRate_Lha = m.pumped_L / m.fieldArea_ha;
    % --- evaluation metrics from the research charter (truth-based scoring; never used in flight) ---
    [XX, YY] = meshgrid(tp.grid.xv, tp.grid.yv);
    inF = inpolygon(XX, YY, field.polygon(:, 1), field.polygon(:, 2));
    m.offFieldPct = 100 * safeDiv(sum(tp.grid.mass(~inF)), tp.grid.emitted);      % deposited outside the field
    allPos = cat('truePos');
    m.boundaryViolationPct = 100 * mean(~inpolygon(allPos(:, 1), allPos(:, 2), field.polygon(:, 1), field.polygon(:, 2)));
    if isfield(tp.grid, 'lagDisplacement_m'), m.lagDisplacement_m = tp.grid.lagDisplacement_m; else, m.lagDisplacement_m = 0; end
    if advOn(cfg, 'localization')
        m.localizationMode = E.localization.mode;
        pv = cat('advEstVar');
        ok = pv > 1e-12;
        if any(ok), m.estNEES = mean(ee(ok).^2 ./ pv(ok)); else, m.estNEES = NaN; end   % ~2 for a consistent 2-D filter
        if isfield(sv.log1, 'advEstP')                % sensorFusion: NEES with the full 2x2 position covariance
            Pc = cat('advEstP'); nees = zeros(size(err, 1), 1);
            for q = 1:size(err, 1)
                Pq = [Pc(q, 1) Pc(q, 2); Pc(q, 2) Pc(q, 3)];
                nees(q) = err(q, :) / Pq * err(q, :)';
            end
            m.estNEES = mean(nees);
            sfs = tp.finalWorld.adv.sf;
            m.sensorFusion = struct('meanNIS', sfs.nisSum / max(sfs.nisN, 1), 'flowUpdates', sfs.nFlow, ...
                'rangeUpdates', sfs.nRange, 'gatedRejections', sfs.nRejected, 'flowDropouts', sfs.nDropout, ...
                'rejectionPct', 100 * sfs.nRejected / max(sfs.nisN, 1));
        end
    else
        m.localizationMode = 'groundTruth';
        m.estNEES = NaN;
    end
    m.effectiveCameraRadius_m = cfg.cameraFovRadius;
    m.effectiveReleaseHeight_m = cfg.internal2.spray.releaseHeight;

    adv = {};
    if advOn(cfg, 'safety')
        if m.maxWindWhileSpraying_mps > E.safety.maxSprayWind_mps
            adv{end+1} = sprintf('Sprayed in wind up to %.1f m/s (limit %.1f m/s)', m.maxWindWhileSpraying_mps, E.safety.maxSprayWind_mps);
        end
        if advOn(cfg, 'energy') && m.batteryLeftPct < E.energy.reservePct
            adv{end+1} = sprintf('Battery reserve violated: %.0f%% left (reserve %.0f%%)', m.batteryLeftPct, E.energy.reservePct);
        end
        if m.refills > 0
            adv{end+1} = sprintf('%d refill trip(s) needed (tank %.1f L)', m.refills, m.tankCapacity_L);
        end
        if m.evaporatedPct > 10
            adv{end+1} = sprintf('%.0f%% of the spray evaporated before landing', m.evaporatedPct);
        end
    end
    m.advisories = adv;
end
