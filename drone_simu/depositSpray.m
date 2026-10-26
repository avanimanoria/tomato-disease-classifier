function grid = depositSpray(grid, nozzleXY, driftVec, volume_mL, cfg)
%DEPOSITSPRAY Add one timestep of spray to the ground deposition grid.
%
%   The cloud is a 2-D Gaussian centred at nozzleXY + driftVec, with
%       footprintRadius = releaseHeight * tand(nozzleHalfAngle)   [DERIVED]
%       sigma           = sigmaFraction * footprintRadius         [ASSUMED fraction]
%   Each cell receives volume * pdf(cell centre) * cell^2, evaluated within
%   +/- 4 sigma. Mass falling outside the grid or beyond 4 sigma is simply
%   not deposited (it still counts in grid.emitted, so it shows up as
%   wasted). SIMPLIFIED RELATIVE MODEL, not CFD and not validated.

    S = cfg.internal2.spray;
    radius = S.releaseHeight * tand(S.nozzleHalfAngle);
    sigma = S.sigmaFraction * radius;

    grid.emitted = grid.emitted + volume_mL;

    centre = nozzleXY(:)' + driftVec(:)';
    half = 4 * sigma;

    ix = find(grid.xv >= centre(1) - half & grid.xv <= centre(1) + half);
    iy = find(grid.yv >= centre(2) - half & grid.yv <= centre(2) + half);
    if isempty(ix) || isempty(iy)
        return;
    end

    [XX, YY] = meshgrid(grid.xv(ix), grid.yv(iy));
    r2 = (XX - centre(1)).^2 + (YY - centre(2)).^2;
    w = exp(-r2 / (2 * sigma^2)) / (2 * pi * sigma^2) * grid.cell^2;
    grid.mass(iy, ix) = grid.mass(iy, ix) + volume_mL * w;
end
