function grid = advDepositKernel(grid, nozzleXY, driftVec, volume_mL, cfg, windVel)
%ADVDEPOSITKERNEL Deposit one spray step with the configured kernel (enhancement 'actuation').
%
%   kernel 'gaussian'      : the original circular Gaussian (depositSpray, unchanged).
%   kernel 'windStretched' : elliptical Gaussian, same across-wind sigma, along-wind sigma
%                            x (1 + windStretch_perMps * |wind|). UNCALIBRATED surrogate for the
%                            wind-stretched footprints reported in the literature; it conserves
%                            the deposited volume of the circular kernel within the +-4 sigma window.
    A = cfg.enhancements.actuation;
    if ~advOn(cfg, 'actuation') || strcmp(A.kernel, 'gaussian') || norm(windVel) < 1e-9
        grid = depositSpray(grid, nozzleXY, driftVec, volume_mL, cfg);
        return;
    end
    S = cfg.internal2.spray;
    sig = S.sigmaFraction * S.releaseHeight * tand(S.nozzleHalfAngle);
    sigA = sig * (1 + A.windStretch_perMps * norm(windVel));
    u = windVel / norm(windVel);                 % along-wind unit vector
    grid.emitted = grid.emitted + volume_mL;
    c = nozzleXY(:)' + driftVec(:)';
    half = 4 * sigA;
    ix = find(grid.xv >= c(1) - half & grid.xv <= c(1) + half);
    iy = find(grid.yv >= c(2) - half & grid.yv <= c(2) + half);
    if isempty(ix) || isempty(iy), return; end
    [XX, YY] = meshgrid(grid.xv(ix), grid.yv(iy));
    dx = XX - c(1); dy = YY - c(2);
    pa = dx * u(1) + dy * u(2);                 % along-wind coordinate
    pc = -dx * u(2) + dy * u(1);                % across-wind coordinate
    w = exp(-(pa.^2 / (2 * sigA^2) + pc.^2 / (2 * sig^2))) / (2 * pi * sigA * sig) * grid.cell^2;
    grid.mass(iy, ix) = grid.mass(iy, ix) + volume_mL * w;
end
