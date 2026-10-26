function c = advParamChoices(feature, name)
%ADVPARAMCHOICES Allowed values of the text-valued advanced-option parameters.
    key = [feature '.' name];
    switch key
        case 'localization.mode'
            c = {'errorModel', 'imuDeadReckoning', 'flowOdometry', 'kalman', 'sensorFusion'};
        case 'guidance.mode'
            c = {'pid', 'purePursuit'};
        case 'actuation.kernel'
            c = {'gaussian', 'windStretched'};
        otherwise
            c = {};
    end
end
