function grid = initDepositionGrid(cfg, field)
%INITDEPOSITIONGRID Empty ground deposition grid covering the field.
%   Covers the polygon bounding box plus cfg.internal2.spray.gridMargin.
%   grid.mass(iy, ix) accumulates mL per cell; grid.emitted accumulates the
%   total volume sprayed (mL), including any that lands outside the grid.

    S = cfg.internal2.spray;
    poly = field.polygon;
    c = S.gridCell;

    grid.cell = c;
    grid.xv = (min(poly(:,1)) - S.gridMargin) : c : (max(poly(:,1)) + S.gridMargin);
    grid.yv = (min(poly(:,2)) - S.gridMargin) : c : (max(poly(:,2)) + S.gridMargin);
    grid.mass = zeros(numel(grid.yv), numel(grid.xv));
    grid.emitted = 0;
end
