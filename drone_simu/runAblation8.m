function T = runAblation8(cfg, field, refFile)
%RUNABLATION8 Regenerate the 8-combination wind x PID x compensation ablation and
%   compare it with the saved reference (results/ablation8_reference.csv).
%   Nothing is tuned or overwritten: discrepancies are only reported.
%   Every combination is a struct preset through applyPreset (switches only).
    if nargin < 3, refFile = fullfile(fileparts(mfilename('fullpath')), 'results', 'ablation8_reference.csv'); end
    ref = readtable(refFile);
    rows = zeros(8, 8);
    k = 0;
    for w = 0:1
        for p = 0:1
            for c = 0:1
                k = k + 1;
                cc = applyPreset(cfg, struct('wind', w, 'pid', p, 'comp', c));
                run = runInternal2Scenario(cc, field, sprintf('w%dp%dc%d', w, p, c));
                m = computeInternal2Metrics(cc, field, run);
                rows(k, :) = [w p c norm(run.compVec) norm(run.driftTrue) m.survey.crossRMSE m.perception.nSeen m.spray.treatedTrue];
            end
        end
    end
    T = array2table(rows, 'VariableNames', ref.Properties.VariableNames);
    tol = [0 0 0 0.005 0.005 0.0005 0 0];   % display-rounding of the reference (2-3 dp); counts exact
    fprintf('Ablation regeneration vs reference (reference rounding: 2-3 dp):\n');
    allOK = true;
    for i = 1:8
        for j = 4:8
            if abs(T{i, j} - ref{i, j}) > tol(j)
                allOK = false;
                fprintf('  DISCREPANCY row %d %s: reference %.4g, regenerated %.4g\n', i, ref.Properties.VariableNames{j}, ref{i, j}, T{i, j});
            end
        end
    end
    if allOK, fprintf('  all 8 rows match the reference within its printed precision\n'); end
    disp(T);
end
