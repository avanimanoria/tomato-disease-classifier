function cfg = uiToConfig(s)
%UITOCONFIG Dashboard control values -> a cfg for the shared Internal-2 engine.
%
%   cfg = uiToConfig(s)
%
%   s fields: wind, pid, comp (logical switches); windSpeed (m/s), windDirDeg (deg,
%   direction wind blows TOWARD, from +X); routing ('fixedOrder' | 'nearestNeighbour' |
%   'stage7Return'); droneSpeed (m/s); rowSpacing, plantSpacing (m); shape
%   ('Rectangle' | 'Trapezoid'); rect (struct length,width) or trap (struct
%   bottom,top,height); rowStyle ('Straight' | 'Curved').
%
%   The dashboard holds NO scenario logic: it only fills these values. The three
%   switches go through applyPreset (switch struct), the rest are plain cfg fields,
%   so any combination is valid and identical to what the experiments use.
%   Throws uiToConfig:invalid with a readable message for out-of-range values.

    chk = @(v, lo, hi, nm) assert(isnumeric(v) && isscalar(v) && isfinite(v) && v >= lo && v <= hi, ...
        'uiToConfig:invalid', '%s must be between %g and %g.', nm, lo, hi);
    chk(s.windSpeed, 0, 5, 'Wind speed (m/s)');
    chk(s.windDirDeg, -360, 360, 'Wind direction (deg)');
    chk(s.droneSpeed, 0.5, 2.0, 'Drone speed (m/s)');      % controller saturates at maxCommandSpeed = 2.5 m/s
    chk(s.rowSpacing, 1, 5, 'Row spacing (m)');
    chk(s.plantSpacing, 0.25, 2, 'Plant spacing (m)');
    adv = isfield(s, 'advancedRouting') && s.advancedRouting;    % optional field: absent = original behaviour
    allowed = {'fixedOrder', 'nearestNeighbour', 'stage7Return'};
    if adv, allowed = [allowed, {'nearestNeighbour2opt', 'cheapestInsertion', 'nearestNeighbourOrOpt', 'antColony'}]; end
    assert(any(strcmp(s.routing, allowed)), ...
        'uiToConfig:invalid', 'Routing "%s" is not available (advanced routing %s).', s.routing, ternaryStr(adv));
    assert(any(strcmp(s.rowStyle, {'Straight', 'Curved'})), 'uiToConfig:invalid', 'Unknown row style "%s".', s.rowStyle);

    cfg = config();
    cfg = applyPreset(cfg, struct('wind', s.wind, 'pid', s.pid, 'comp', s.comp, 'windSpeed', s.windSpeed));
    cfg.internal2.wind.dirDeg = s.windDirDeg;
    cfg.internal2.treat.routing = s.routing;
    if adv, cfg.enhancements.enableAdvancedRouting = true; end
    cfg.droneSpeed = s.droneSpeed;
    cfg.rowSpacing = s.rowSpacing;
    cfg.plantSpacing = s.plantSpacing;

    switch s.shape
        case 'Rectangle'
            chk(s.rect.length, 6, 60, 'Field length (m)');
            chk(s.rect.width, 6, 40, 'Field width (m)');
            cfg.internal2.field.polygon = fieldShapeToPolygon('Rectangle', s.rect);
        case 'Trapezoid'
            chk(s.trap.bottom, 6, 60, 'Bottom width (m)');
            chk(s.trap.top, 4, 60, 'Top width (m)');
            chk(s.trap.height, 6, 40, 'Height (m)');
            cfg.internal2.field.polygon = fieldShapeToPolygon('Trapezoid', s.trap);
        case 'UShape'                    % ENHANCEMENT (Pipeline Builder only)
            chk(s.rect.length, 12, 60, 'Field length (m)');
            chk(s.rect.width, 10, 40, 'Field width (m)');
            cfg.internal2.field.polygon = fieldShapeToPolygon('UShape', s.rect);
        otherwise
            error('uiToConfig:invalid', 'Unsupported field shape "%s".', s.shape);
    end
    if strcmp(s.rowStyle, 'Straight')
        cfg.internal2.field.rowCurveAmp = 0;
    end
    if isfield(s, 'adv')                 % optional: advanced-physics options (master switch default off)
        cfg = applyAdvancedUi(cfg, s.adv);
    end
end

function cfg = applyAdvancedUi(cfg, A)
%APPLYADVANCEDUI Copy the dashboard's advanced options into cfg.enhancements; validate if ON.
    E = cfg.enhancements;
    E.enableAdvancedPhysics = logical(A.enabled);
    feats = advFeatures();
    for i = 1:numel(feats)
        f = feats{i};
        if ~isfield(A, f), continue; end
        fn = fieldnames(A.(f));
        for j = 1:numel(fn)
            E.(f).(fn{j}) = A.(f).(fn{j});
        end
    end
    if E.enableAdvancedPhysics
        for i = 1:numel(feats)
            fn = setdiff(fieldnames(E.(feats{i})), {'enabled'});
            for j = 1:numel(fn)
                v = E.(feats{i}).(fn{j});
                if ischar(v) || isstring(v)
                    ok = advParamChoices(feats{i}, fn{j});
                    assert(any(strcmp(char(v), ok)), 'uiToConfig:invalid', 'Advanced %s.%s must be one of: %s.', ...
                        feats{i}, fn{j}, strjoin(ok, ', '));
                    continue;
                end
                assert(isnumeric(v) && isscalar(v) && isfinite(v), 'uiToConfig:invalid', ...
                    'Advanced %s.%s must be a finite number.', feats{i}, fn{j});
            end
        end
        pos = @(v, nm) assert(v > 0, 'uiToConfig:invalid', '%s must be positive.', nm);
        pos(E.payload.dryMass_kg, 'Dry mass'); pos(E.payload.liquidDensity_kgL, 'Liquid density');
        assert(E.payload.tankCapacity_L >= cfg.internal2.spray.flowRate * cfg.internal2.spray.duration / 1000, ...
            'uiToConfig:invalid', 'Tank capacity must hold at least one dose (%.2f L).', ...
            cfg.internal2.spray.flowRate * cfg.internal2.spray.duration / 1000);
        pos(E.dynamics.velTimeConstant_s, 'Velocity response time'); pos(E.dynamics.airDensity_kgm3, 'Air density');
        assert(E.dynamics.thrustToWeightFull > 1, 'uiToConfig:invalid', 'Thrust/weight must exceed 1.');
        pos(E.energy.battery_Wh, 'Battery'); pos(E.energy.rotorDiskArea_m2, 'Rotor disk area');
        assert(E.energy.efficiency > 0 && E.energy.efficiency <= 1, 'uiToConfig:invalid', 'Efficiency must be in (0, 1].');
        assert(E.gusts.periodMin_s > 0 && E.gusts.periodMax_s >= E.gusts.periodMin_s, 'uiToConfig:invalid', 'Gust periods invalid.');
        assert(E.atmosphere.relHumidity_pct >= 1 && E.atmosphere.relHumidity_pct <= 100, 'uiToConfig:invalid', 'Humidity must be 1-100 %.');
        assert(E.atmosphere.temperature_C >= -10 && E.atmosphere.temperature_C <= 50, 'uiToConfig:invalid', 'Temperature must be -10..50 C.');
        assert(E.atmosphere.dropletVMD_um >= 20 && E.atmosphere.dropletVMD_um <= 1000, 'uiToConfig:invalid', 'Droplet VMD must be 20-1000 um.');
        assert(E.perception.altitude_m >= 1 && E.perception.altitude_m <= 10, 'uiToConfig:invalid', 'Flight altitude must be 1-10 m.');
        pos(E.perception.detectAltitudeScale_m, 'Detection falloff'); pos(E.localization.fixInterval_s, 'Fix interval');
    end
    cfg.enhancements = E;
end

function t = ternaryStr(b)
    if b, t = 'enabled'; else, t = 'disabled'; end
end
