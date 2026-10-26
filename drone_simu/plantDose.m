function dose = plantDose(cfg, field, grid)
%PLANTDOSE Delivered spray (mL) inside each plant's canopy disc (Nx1).
%   Sums grid mass over cells within cfg.internal2.metrics.canopyRadius of
%   the plant. SIMPLIFIED RELATIVE MODEL (see depositSpray).

    P = field.plants;
    N = height(P);
    R = cfg.internal2.metrics.canopyRadius;
    dose = zeros(N, 1);
    for i = 1:N
        ix = find(grid.xv >= P.X(i) - R & grid.xv <= P.X(i) + R);
        iy = find(grid.yv >= P.Y(i) - R & grid.yv <= P.Y(i) + R);
        if isempty(ix) || isempty(iy), continue; end
        [XX, YY] = meshgrid(grid.xv(ix), grid.yv(iy));
        mask = (XX - P.X(i)).^2 + (YY - P.Y(i)).^2 <= R^2;
        sub = grid.mass(iy, ix);
        dose(i) = sum(sub(mask));
    end
end
