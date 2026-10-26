function results = runAllTests(names)
%RUNALLTESTS Regression gate: run every test in tests/ (matlab.unittest).
%
%   results = runAllTests                 % full gate (about 15 min)
%   results = runAllTests('LegacyMissionGoldenTest')   % one test file
%
%   Prints a summary and writes a plain-text report to test_reports/. Any failure blocks the
%   next implementation phase (DRONE_IMPLEMENTATION_COMPLETION_MANUAL_V1, section 1.3).
    p = fileparts(mfilename('fullpath'));
    addpath(p, fullfile(p, 'golden'), fullfile(p, 'tests'));
    import matlab.unittest.TestSuite
    if nargin < 1 || isempty(names)
        suite = TestSuite.fromFolder(fullfile(p, 'tests'));
    else
        names = cellstr(names);
        suite = [];
        for i = 1:numel(names), suite = [suite, TestSuite.fromFile(fullfile(p, 'tests', [names{i} '.m']))]; end %#ok<AGROW>
    end
    runner = matlab.unittest.TestRunner.withTextOutput('OutputDetail', matlab.unittest.Verbosity.Terse);
    t0 = tic;
    results = runner.run(suite);
    T = table(results);
    fprintf('\n%-62s %-6s %8s\n', 'Test', 'Result', 'Time(s)');
    for i = 1:numel(results)
        fprintf('%-62s %-6s %8.1f\n', results(i).Name, ternary(results(i).Passed, 'PASS', 'FAIL'), results(i).Duration);
    end
    nP = nnz([results.Passed]); nF = nnz([results.Failed]);
    fprintf('\nREGRESSION GATE: %s  (%d passed, %d failed, %.1f min)\n', ternary(nF == 0, 'PASS', 'FAIL'), nP, nF, toc(t0) / 60);
    rd = fullfile(p, 'test_reports');
    if ~isfolder(rd), mkdir(rd); end
    fn = fullfile(rd, ['regression_' datestr(now, 'yyyymmdd_HHMMSS') '.txt']);
    fid = fopen(fn, 'w');
    fprintf(fid, 'Regression gate %s\n', datestr(now));
    [~, h] = system(['git -C "' p '" rev-parse --short HEAD']);
    fprintf(fid, 'git HEAD: %s\n', strtrim(h));
    for i = 1:numel(results)
        fprintf(fid, '%s\t%s\t%.1f s\n', results(i).Name, ternary(results(i).Passed, 'PASS', 'FAIL'), results(i).Duration);
    end
    fprintf(fid, 'RESULT: %s (%d passed, %d failed)\n', ternary(nF == 0, 'PASS', 'FAIL'), nP, nF);
    fclose(fid);
    fprintf('Report: %s\n', fn);
    if nargout == 0, clear results; end
    assignin('base', 'lastTestTable', T);
end

function v = ternary(c, a, b)
    if c, v = a; else, v = b; end
end
