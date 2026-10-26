function st = missionStateAt(tl, k)
%MISSIONSTATEAT What the dashboard may show at replay step k (1..tl.N).
%
%   st = missionStateAt(tl, k)
%
%   Everything is a function of the replay PREFIX 1..k (nothing from later steps, no
%   final-mission totals before completion) and of information the drone has.
%
%   Fields: k, pos, t, cross, distance, stage, phaseText, observed / flagged (Nx1
%   logical), nObserved, nFlagged, obsPlant (current observation, 0 = none), tgtPlant,
%   row, target (Pass-2 ordinal), isSpraying, sprayed (completed spray events),
%   emitted_mL, pass2Distance, n1, done.

    k = min(max(round(k), 1), tl.N);
    st.k = k;
    st.pos = tl.pos(k, :);
    st.t = tl.t(k);
    st.cross = tl.cross(k);
    st.distance = tl.cumDist(k);
    st.stage = tl.stage(k);
    st.observed = tl.firstStep > 0 & tl.firstStep <= k;
    st.flagged = tl.flagStep > 0 & tl.flagStep <= k;
    st.nObserved = nnz(st.observed);
    st.nFlagged = nnz(st.flagged);
    st.obsPlant = tl.obsPlant(k);
    st.tgtPlant = tl.tgtPlant(k);
    st.target = tl.ord(k);
    st.isSpraying = tl.stage(k) == 4 && k < tl.N;    % the final logged step is the end of the last dwell: pump already off
    st.sprayed = tl.sprayDone(k);
    st.emitted_mL = tl.sprayStepsCum(k) * tl.emitPerStep_mL;
    st.pass2Distance = max(0, tl.cumDist(k) - tl.cumDist(tl.n1));
    st.n1 = tl.n1;
    st.inPass2 = k > tl.n1;
    st.done = k >= tl.N;
    st.isRefill = isfield(tl, 'isRefill') && tl.isRefill(k);

    st.row = 0;
    if k <= tl.n1 && ~isempty(tl.rowEnd)
        s = min((k - 1) * tl.refStep, tl.refLen);
        st.row = find(s <= tl.rowEnd + 1e-9, 1);
        if isempty(st.row), st.row = tl.numRows; end
    end

    if k <= tl.n1
        if st.row > 0
            st.phaseText = sprintf('PASS 1 - SURVEY    Row %d / %d', st.row, tl.numRows);
        else
            st.phaseText = 'PASS 1 - SURVEY';
        end
    elseif st.done
        st.phaseText = 'MISSION COMPLETE';
    elseif st.isRefill
        if tl.stage(k) == 3, what = 'refilling'; else, what = 'flying to refill point'; end
        st.phaseText = sprintf('PASS 2 - REFILL TRIP %d    (%s)', tl.refillNo(k), what);
    elseif tl.isReturn(k)
        st.phaseText = sprintf('PASS 2 - RETURN TO SURVEY PATH    after target %d / %d', st.target, tl.nTargets);
    else
        switch tl.stage(k)
            case 2, what = 'transit';
            case 3, what = 'settling';
            otherwise, what = 'SPRAYING';
        end
        st.phaseText = sprintf('PASS 2 - TARGETED TREATMENT    Target %d / %d (%s)', st.target, tl.nTargets, what);
    end
end
