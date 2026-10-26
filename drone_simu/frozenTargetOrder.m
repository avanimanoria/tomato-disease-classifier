function idx = frozenTargetOrder(field)
%FROZENTARGETORDER Truly diseased plants in a fixed, detection-independent order.
%
%   idx = frozenTargetOrder(field) returns row indices into field.plants of
%   ALL truly diseased plants, ordered boustrophedon like the survey: row 1
%   by increasing X, row 2 by decreasing X, row 3 increasing, ... This uses
%   only ground truth and geometry, so perception cannot influence it.
%   Used by Experiment C (routing) and D (spray-only).

    P = field.plants;
    d = find(P.TrueDisease == "DISEASED");
    dirSign = ones(numel(d), 1);
    dirSign(mod(P.RowIdx(d), 2) == 0) = -1;     % even rows are flown in -X
    [~, o] = sortrows([P.RowIdx(d), dirSign .* P.X(d)]);
    idx = d(o);
end
