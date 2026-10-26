function name = matchPreset(wind, pid, comp)
%MATCHPRESET Backend preset name whose switches equal (wind, pid, comp), else 'Custom'.
%
%   name = matchPreset(wind, pid, comp)
%
%   Pure lookup in scenarioPresets(): it only LABELS a switch combination (UI display).
%   Nothing in the simulation reads the result.

    T = scenarioPresets();
    k = find(T.wind == logical(wind) & T.pid == logical(pid) & T.comp == logical(comp), 1);
    if isempty(k)
        name = 'Custom';
    else
        name = char(T.name(k));
    end
end
