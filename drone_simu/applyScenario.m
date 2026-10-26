function cfg = applyScenario(cfg, wind, pid, comp, windSpeed)
%APPLYSCENARIO Set the three Internal-2 scenario switches in one place.
%
%   cfg = applyScenario(cfg, wind, pid, comp)
%   cfg = applyScenario(cfg, wind, pid, comp, windSpeed)   % also overrides wind speed, m/s
%
%   wind : wind on/off      pid : PID on/off (off = open-loop feed-forward)
%   comp : upwind spray compensation on/off
%   Nothing else in cfg is touched, so scenarios differ ONLY in these switches.

    cfg.internal2.enabled          = true;
    cfg.internal2.wind.enabled     = logical(wind);
    cfg.internal2.ctrl.enabled     = logical(pid);
    cfg.internal2.spray.compensate = logical(comp);
    if nargin >= 5 && ~isempty(windSpeed)
        cfg.internal2.wind.speed = windSpeed;
    end
end
