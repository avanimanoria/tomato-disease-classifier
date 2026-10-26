function evaluateDiseaseModel(net, augTest, trueLabels, classNames)
%EVALUATEDISEASEMODEL Print accuracy, confusion matrix, precision, recall,
%   F1 score for a trained network against a labeled test set (Section 13).
%
%   evaluateDiseaseModel(net, augTest, trueLabels, classNames) is called
%   automatically at the end of trainDiseaseModel.m, but can also be
%   called by itself later to re-evaluate a saved model.

    predLabels = classify(net, augTest);

    accuracy = mean(predLabels == trueLabels);
    fprintf('\n--- MODEL EVALUATION ---\n');
    fprintf('Overall accuracy: %.2f%%\n', accuracy * 100);

    cm = confusionmat(trueLabels, predLabels);
    disp('Confusion matrix (rows = true, cols = predicted):');
    disp(array2table(cm, 'VariableNames', cellstr(classNames), 'RowNames', cellstr(classNames)));

    numClasses = numel(classNames);
    precision = zeros(numClasses,1);
    recall    = zeros(numClasses,1);
    f1        = zeros(numClasses,1);

    for c = 1:numClasses
        tp = cm(c,c);
        fp = sum(cm(:,c)) - tp;
        fn = sum(cm(c,:)) - tp;

        if (tp+fp) > 0, precision(c) = tp / (tp+fp); else, precision(c) = 0; end
        if (tp+fn) > 0, recall(c)    = tp / (tp+fn); else, recall(c) = 0; end
        if (precision(c)+recall(c)) > 0
            f1(c) = 2 * precision(c) * recall(c) / (precision(c) + recall(c));
        else
            f1(c) = 0;
        end

        fprintf('%-10s  precision=%.2f  recall=%.2f  F1=%.2f\n', ...
            classNames{c}, precision(c), recall(c), f1(c));
    end

    try
        figure('Name','Confusion Matrix');
        confusionchart(trueLabels, predLabels);
    catch
        % confusionchart may be unavailable on older MATLAB versions;
        % the printed table above is sufficient in that case.
    end
end
