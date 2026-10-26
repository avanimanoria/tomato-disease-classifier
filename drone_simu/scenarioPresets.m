function T = scenarioPresets()
%SCENARIOPRESETS Named scenarios as DATA: the switch settings each name stands for.
%
%   T = scenarioPresets() returns a table (name, wind, pid, comp). A name is
%   only a label for a switch combination; no simulation code branches on it
%   (see applyPreset). Any other combination is just a struct with those
%   three fields ("Custom").
%
%     Baseline              wind OFF  PID OFF  compensation OFF
%     No wind + PID         wind OFF  PID ON   compensation OFF   (controller-only control)
%     Disturbed             wind ON   PID OFF  compensation OFF
%     Navigation Corrected  wind ON   PID ON   compensation OFF
%     Fully Corrected       wind ON   PID ON   compensation ON

    name = ["Baseline"; "No wind + PID"; "Disturbed"; "Navigation Corrected"; "Fully Corrected"];
    wind = [false; false; true;  true;  true];
    pid  = [false; true;  false; true;  true];
    comp = [false; false; false; false; true];
    T = table(name, wind, pid, comp);
end
