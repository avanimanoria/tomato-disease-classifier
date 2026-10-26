function p = testSetupPaths()
%TESTSETUPPATHS Add the project and golden/ folders to the path; return the project root.
    p = fileparts(fileparts(mfilename('fullpath')));
    addpath(p, fullfile(p, 'golden'), fullfile(p, 'tests'));
end
