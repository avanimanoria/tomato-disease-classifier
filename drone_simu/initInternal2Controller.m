function ctrl = initInternal2Controller()
%INITINTERNAL2CONTROLLER Fresh controller state for pidCrossTrackController.
%   integralVec : world-frame integral of cross-track error (m*s)
%   prevCross   : previous cross-track error (NaN = none yet; set by flyReference per leg)

    ctrl.integralVec = [0 0];
    ctrl.prevCross   = NaN;
end
