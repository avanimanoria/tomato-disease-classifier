function smokePlaybackV2(projDir, presets, outDir, playbackX)
%SMOKEPLAYBACKV2 Visible, wall-clock playback smoke test of the V2 dashboard.
%   Real timer, real figure. Samples the app while it plays and checks: monotonic
%   continuous cursor, phase order (PASS 1 -> PASS 2 -> COMPLETE), constant map limits
%   (no rescaling/flicker source), status-label sync with the replayed step, PAUSE
%   freeze, RESUME, STOP, RESET. Saves screenshots into outDir.
    addpath(projDir);
    if nargin < 2, presets = {'Fully Corrected', 'Disturbed'}; end
    if nargin < 3, outDir = fullfile(projDir, 'results', 'ui_screens'); end
    if nargin < 4, playbackX = 25; end
    if ~isfolder(outDir), mkdir(outDir); end
    for pi = 1:numel(presets)
        name = presets{pi};
        tag = lower(strrep(name, ' ', ''));
        fprintf('=== wall-clock playback: %s (x%g) ===\n', name, playbackX);
        app = AgriculturalDroneDashboardV2();            % visible, real timer
        c = onCleanup(@() delete(app)); %#ok<NASGU>
        app.PresetDropDown.Value = presetUiName(name);
        app.PresetDropDown.ValueChangedFcn([], []);
        app.PlaybackEdit.Value = playbackX;
        app.generateField(); pause(0.5);
        exportapp(app.UIFigure, fullfile(outDir, sprintf('wc_%s_1_ready_fieldgenerated.png', tag)));
        app.startMission();
        assert(strcmp(app.mode, 'PLAYING'), 'did not start');
        xl0 = xlim(app.MapAxes); yl0 = ylim(app.MapAxes);
        t0 = tic; samples = zeros(0, 3); phases = strings(0, 1); modes = strings(0, 1);
        shot = false(1, 3); paused = false; resumed = false;
        syncBad = 0; limBad = 0;
        while ~any(strcmp(app.mode, {'DONE', 'STOPPED'})) && toc(t0) < 120
            pause(0.12);
            k = round(app.cursor);
            samples(end+1, :) = [toc(t0), app.cursor, 0]; %#ok<AGROW>
            ph = string(app.PhaseLabel.Text); phases(end+1, 1) = ph; modes(end+1, 1) = string(app.mode); %#ok<AGROW>
            % status sync: the displayed time must be the replayed step's time (within one render lag)
            shown = sscanf(app.TimeLabel.Text, 'Mission time: %f');
            if ~isempty(shown) && abs(shown - app.tl.t(min(max(round(app.cursor), 1), app.tl.N))) > 2.5
                syncBad = syncBad + 1;
            end
            if ~isequal(xlim(app.MapAxes), xl0) || ~isequal(ylim(app.MapAxes), yl0), limBad = limBad + 1; end
            if ~shot(1) && startsWith(ph, 'PASS 1') && k > 0.5 * app.tl.n1
                app.pauseMission(); drawnow; exportapp(app.UIFigure, fullfile(outDir, sprintf('wc_%s_2_pass1.png', tag))); shot(1) = true; app.resumeMission();
            end
            if ~paused && startsWith(ph, 'PASS 2') && contains(ph, 'Target 4 /')
                app.pauseMission(); paused = true; c1 = app.cursor; pause(0.6);
                fprintf('  PAUSE: cursor %.1f -> %.1f after 0.6 s (mode %s)\n', c1, app.cursor, app.mode);
                assert(app.cursor == c1 && strcmp(app.mode, 'PAUSED'), 'PAUSE did not freeze');
                assert(strcmp(app.Timer.Running, 'off'), 'timer still running while paused');
                drawnow; exportapp(app.UIFigure, fullfile(outDir, sprintf('wc_%s_3_pass2.png', tag))); shot(2) = true;
                app.resumeMission(); resumed = true; pause(0.5);
                assert(app.cursor > c1 && strcmp(app.mode, 'PLAYING'), 'RESUME did not continue');
                fprintf('  RESUME: cursor advanced %.1f -> %.1f\n', c1, app.cursor);
            end
        end
        pause(0.3);
        fprintf('  finished: mode %s, cursor %d / %d, wall %.1f s\n', app.mode, round(app.cursor), app.tl.N, toc(t0));
        assert(strcmp(app.mode, 'DONE'), 'playback did not reach DONE');
        exportapp(app.UIFigure, fullfile(outDir, sprintf('wc_%s_4_complete.png', tag))); shot(3) = true;

        % continuity / monotonicity
        d = diff(samples(:, 2));
        fprintf('  monotonic cursor: %d | max step jump per 0.12 s sample: %.1f steps (expected ~%.1f)\n', all(d >= 0), max(d), playbackX * 0.12 / 0.1);
        % phase order
        firstP2 = find(startsWith(phases, 'PASS 2'), 1); lastP1 = find(startsWith(phases, 'PASS 1'), 1, 'last');
        fprintf('  phase order PASS1 before PASS2: %d | COMPLETE shown: %d\n', lastP1 < firstP2, strcmp(app.PhaseLabel.Text, 'MISSION COMPLETE'));
        fprintf('  map limits constant during playback: %d (violations %d) | status-time sync violations: %d | PAUSE/RESUME exercised: %d\n', ...
            limBad == 0, limBad, syncBad, paused && resumed);

        % STOP + RESET on a fresh start
        app.startMission(); pause(0.8);
        app.stopMission(); cs = app.cursor; pause(0.5);
        fprintf('  STOP: mode %s, cursor frozen %d, timer %s, config unlocked %s\n', app.mode, app.cursor == cs, app.Timer.Running, app.WindCheck.Enable);
        assert(strcmp(app.mode, 'STOPPED') && strcmp(app.Timer.Running, 'off'), 'STOP failed');
        app.startMission(); pause(0.5); app.resetMission();
        fprintf('  RESET: mode %s, run cleared %d, timer %s\n', app.mode, isempty(app.run), app.Timer.Running);
        assert(strcmp(app.mode, 'READY') && isempty(app.run), 'RESET failed');
        delete(app);
    end
    fprintf('WALL-CLOCK PLAYBACK SMOKE TEST: DONE\n');
end
