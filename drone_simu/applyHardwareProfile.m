function [cfg, changes, warns, prof] = applyHardwareProfile(cfg, idOrFile)
%APPLYHARDWAREPROFILE Set the profile's parameters in cfg.enhancements (only those it lists).
%
%   [cfg, changes, warns, prof] = applyHardwareProfile(cfg, 'assumedDefault' | id | file)
%   changes: table (key, old, new, sourceType) of parameters whose value actually changed.
%   warns:   physical-feasibility warnings (checkProfileFeasibility) - not errors, so a user
%            can still study an infeasible design, but they are always reported.
%   Hardware parameters only act when the matching optional feature (payload / dynamics /
%   energy) is enabled; with every feature off, any profile leaves the mission unchanged.
%   Reversible: applying 'assumedDefault' restores the config.m values.
    prof = loadHardwareProfile(idOrFile);
    k = {}; o = []; n = []; s = {};
    for i = 1:numel(prof.params)
        q = prof.params(i);
        f = strsplit(q.path, '.');
        old = getfield(cfg, f{:}); %#ok<GFLD>
        if ~isequal(old, q.value)
            k{end+1, 1} = q.key; o(end+1, 1) = old; n(end+1, 1) = q.value; s{end+1, 1} = q.sourceType; %#ok<AGROW>
            cfg = setfield(cfg, f{:}, q.value); %#ok<SFLD>
        end
    end
    changes = table(string(k), o, n, string(s), 'VariableNames', {'key', 'old', 'new', 'sourceType'});
    warns = checkProfileFeasibility(cfg);
end
