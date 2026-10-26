function w = windVector(cfg, t) %#ok<INUSD>
%WINDVECTOR Steady wind velocity [wx wy] in m/s (world frame).
%   cfg.internal2.wind.dirDeg is the direction the wind blows TOWARD,
%   measured from +X. Returns [0 0] when wind is disabled. The time input
%   is part of the interface so a time-varying wind can be added later;
%   it is unused (no turbulence in Internal-2).

    W = cfg.internal2.wind;
    if ~W.enabled
        w = [0 0];
        return;
    end
    w = W.speed * [cosd(W.dirDeg), sind(W.dirDeg)];
    if advOn(cfg, 'gusts')             % ENHANCEMENT (opt-in): zero-mean gusts on top of the steady wind
        w = w + gustVector(cfg, t);
    end
end
