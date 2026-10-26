function [vCmd, dg] = purePursuitController(estPos, ref, s, pRef, tau, v, hold, cfg)
%PUREPURSUITCONTROLLER Look-ahead (pure-pursuit style) path following, an alternative to PID.
%
%   [vCmd, dg] = purePursuitController(estPos, ref, s, pRef, tau, v, hold, cfg)
%
%   Travel: steer at the reference point lookahead_m ahead of the time-indexed reference
%   arclength s; speed = v * |d| / lookahead (so a lagging drone speeds up, a leading one
%   slows), saturated at maxCommandSpeed. Settle/dwell (hold = true): fly to the leg end
%   point with speed holdGain * distance. Uses only the ESTIMATED position.
%   Enhancement 'guidance' (mode 'purePursuit'); [ASSUMED] gains, not tuned.

    G = cfg.enhancements.guidance;
    vMax = cfg.internal2.ctrl.maxCommandSpeed;
    if hold
        target = ref.pts(end, :);
        d = target - estPos;
        spd = min(G.holdGain_per_s * norm(d), vMax);
    else
        target = sampleReference(ref, min(s + G.lookahead_m, ref.len));
        d = target - estPos;
        spd = min(v * norm(d) / G.lookahead_m, vMax);
    end
    if norm(d) > 1e-9
        vCmd = spd * d / norm(d);
    else
        vCmd = [0 0];
    end
    dg.eAlong = dot(pRef - estPos, tau);
end
