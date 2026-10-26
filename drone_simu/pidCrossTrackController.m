function [vCmd, ctrl, diag] = pidCrossTrackController(estPos, refPos, tau, vFF, ctrl, cfg)
%PIDCROSSTRACKCONTROLLER Velocity command from reference + feedback.
%
%   [vCmd, ctrl, diag] = pidCrossTrackController(estPos, refPos, tau, vFF, ctrl, cfg)
%
%   estPos, refPos : [X Y] estimated drone position / reference point
%   tau            : unit tangent of the reference at refPos
%   vFF            : feed-forward velocity [vx vy] (reference velocity)
%   ctrl           : controller state (see initInternal2Controller.m)
%
%   cfg.internal2.ctrl.enabled == false  ->  vCmd = vFF (open-loop, no
%   feedback; the "PID OFF" case).
%   enabled == true:
%       e        = refPos - estPos           (position error vector)
%       eCross   = e . n,  eAlong = e . tau  (n = left normal of tau)
%       vCmd     = vFF + KpAlong*eAlong*tau + (Kp*eCross + Ki*I + Kd*dE)*n
%   The integral is stored as a WORLD-FRAME vector so a steady wind bias
%   learned on one leg is still correct when the reference direction
%   changes. Heading error is not a separate term: for this point-mass
%   model, heading follows the commanded velocity direction.

    C = cfg.internal2.ctrl;
    dt = cfg.dt;

    nrm = [-tau(2), tau(1)];
    e = refPos - estPos;
    eAlong = dot(e, tau);
    eCross = dot(e, nrm);

    diag.eAlong = eAlong;
    diag.eCross = eCross;

    if ~C.enabled
        vCmd = vFF;
        return;
    end

    if isnan(ctrl.prevCross)
        dE = 0;
    else
        dE = (eCross - ctrl.prevCross) / dt;
    end
    ctrl.prevCross = eCross;

    ctrl.integralVec = ctrl.integralVec + eCross * nrm * dt;
    nI = norm(ctrl.integralVec);
    if nI > C.integralLimit
        ctrl.integralVec = ctrl.integralVec * (C.integralLimit / nI);
    end
    iCross = dot(ctrl.integralVec, nrm);

    uCross = C.Kp * eCross + C.Ki * iCross + C.Kd * dE;
    uAlong = C.KpAlong * eAlong;

    vCmd = vFF + uAlong * tau + uCross * nrm;

    sp = norm(vCmd);
    if sp > C.maxCommandSpeed
        vCmd = vCmd * (C.maxCommandSpeed / sp);
    end
end
