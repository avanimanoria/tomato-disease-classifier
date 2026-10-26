function main_animation(speed, which)
%MAIN_ANIMATION Watch the Internal-2 missions fly in real time.
%
%   main_animation              % 4 scenarios side by side at 8x real time
%   main_animation(15)          % faster playback (simulated s per wall s)
%   main_animation(8, [3 5])    % choose scenarios (indices below)
%
%   Scenario indices (order of cfg.experiments.E.scenarios): 1 Baseline, 2 No wind + PID,
%   3 Disturbed, 4 Navigation Corrected, 5 Fully Corrected.
%   Default = [1 3 4 5] (the original four). The simulation is computed first
%   (about a minute), then replayed live; close the figure window to stop.

    if nargin < 1, speed = 8; end
    if nargin < 2, which = [1 3 4 5]; end

    cfg = config();
    cfg.internal2.enabled = true;
    field = generateIrregularField(cfg);

    fprintf('Computing scenarios (this takes a moment) ...\n');
    E = runExperimentE(cfg, field, false);

    fprintf('Starting live playback at %gx. Close the window to stop.\n', speed);
    animateInternal2(cfg, field, E.runs(which), struct('speed', speed));
end
