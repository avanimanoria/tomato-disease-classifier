function tests = FrozenExperimentIntegrityTest
%FROZENEXPERIMENTINTEGRITYTEST Experiment A-F inputs/results and golden data are unchanged.
%   Compares every file listed in golden/frozen_checksums.csv (SHA-256). New files are allowed;
%   a missing or modified frozen file fails.
    tests = functiontests(localfunctions);
end

function setupOnce(tc)
    tc.TestData.p = testSetupPaths();
end

function testChecksums(tc)
    p = tc.TestData.p;
    T = readtable(fullfile(p, 'golden', 'frozen_checksums.csv'), 'Delimiter', ',', 'TextType', 'string');
    bad = strings(0, 1);
    for i = 1:height(T)
        f = fullfile(p, T.path(i));
        if ~isfile(f), bad(end+1) = "MISSING " + T.path(i); continue; end %#ok<AGROW>
        if ~strcmp(fileSha256(f), T.sha256(i)), bad(end+1) = "CHANGED " + T.path(i); end %#ok<AGROW>
    end
    verifyEmpty(tc, bad, strjoin(bad, newline));
    verifyGreaterThan(tc, height(T), 50);
end
