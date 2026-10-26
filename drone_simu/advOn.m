function tf = advOn(cfg, feature)
%ADVON True when an optional advanced-physics feature is active.
%
%   tf = advOn(cfg, 'payload')   % master switch AND that feature's .enabled
%   tf = advOn(cfg, 'any')       % master switch AND at least one feature enabled
%
%   Features: payload, dynamics, energy, gusts, atmosphere, perception,
%   localization, safety (cfg.enhancements.*). With the master switch
%   cfg.enhancements.enableAdvancedPhysics = false (the default) this is always
%   false, so every engine hook is skipped and the original code path runs.

    tf = false;
    if ~isfield(cfg, 'enhancements') || ~isfield(cfg.enhancements, 'enableAdvancedPhysics') ...
            || ~cfg.enhancements.enableAdvancedPhysics
        return;
    end
    E = cfg.enhancements;
    feats = advFeatures();
    if strcmp(feature, 'any')
        for i = 1:numel(feats)
            if E.(feats{i}).enabled, tf = true; return; end
        end
    else
        tf = logical(E.(feature).enabled);
    end
end
