function [cfg, label] = applyPreset(cfg, spec)
%APPLYPRESET Resolve a scenario spec into cfg switches (wind / PID / compensation).
%
%   [cfg, label] = applyPreset(cfg, 'Fully Corrected')   % named preset (scenarioPresets)
%   [cfg, label] = applyPreset(cfg, 'Custom')            % use cfg exactly as supplied
%   [cfg, label] = applyPreset(cfg, struct('wind',1,'pid',0,'comp',1))   % custom combination
%                                                         % optional fields: name, windSpeed
%
%   The label is for display only. It never influences the simulation: the
%   only things set here are the three switches in cfg.internal2 (via
%   applyScenario), and 'Custom' sets nothing at all.

    if isstruct(spec)
        if isfield(spec, 'windSpeed'), ws = spec.windSpeed; else, ws = []; end
        cfg = applyScenario(cfg, spec.wind, spec.pid, spec.comp, ws);
        if isfield(spec, 'name'), label = char(spec.name); else, label = 'Custom'; end
        return;
    end

    name = string(spec);
    if strcmpi(name, "Custom")
        cfg.internal2.enabled = true;
        label = 'Custom';
        return;
    end
    T = scenarioPresets();
    k = find(T.name == name, 1);
    if isempty(k)
        error('applyPreset:unknown', 'Unknown preset "%s". Known: %s, or "Custom", or a struct(wind,pid,comp).', ...
            name, strjoin(T.name, ', '));
    end
    cfg = applyScenario(cfg, T.wind(k), T.pid(k), T.comp(k));
    label = char(name);
end
