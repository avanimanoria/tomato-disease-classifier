function [uiNames, backendNames] = presetUiName(backendName)
%PRESETUINAME Display names for presets (UI only; backend identifiers are unchanged).
%
%   ui = presetUiName('No wind + PID')   -> 'Baseline + PID'
%   [uiNames, backendNames] = presetUiName()   -> all presets in scenarioPresets order
%
%   The only renamed preset is 'No wind + PID' (shown as 'Baseline + PID').

    T = scenarioPresets();
    backendNames = cellstr(T.name)';
    uiNames = backendNames;
    uiNames(strcmp(backendNames, 'No wind + PID')) = {'Baseline + PID'};
    if nargin == 0, return; end
    k = find(strcmp(backendNames, backendName), 1);
    if isempty(k)
        uiNames = backendName;      % 'Custom' or unknown: unchanged
    else
        uiNames = uiNames{k};
    end
end
