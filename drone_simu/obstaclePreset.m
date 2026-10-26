function obst = obstaclePreset(name, poly)
%OBSTACLEPRESET Named no-crop / no-fly obstacle sets for a field polygon (Pipeline Builder).
%   'none' -> {};  'pond' -> one rectangular pond, 20 % x 25 % of the field bounding box,
%   centred slightly left of the middle so that rows are split into two unequal pieces.
    switch name
        case 'none'
            obst = {};
        case 'pond'
            x0 = min(poly(:, 1)); x1 = max(poly(:, 1)); y0 = min(poly(:, 2)); y1 = max(poly(:, 2));
            cx = x0 + 0.42 * (x1 - x0); cy = y0 + 0.5 * (y1 - y0);
            hx = 0.10 * (x1 - x0); hy = 0.125 * (y1 - y0);
            obst = {[cx - hx, cy - hy; cx + hx, cy - hy; cx + hx, cy + hy; cx - hx, cy + hy]};
        otherwise
            error('obstaclePreset:unknown', 'Unknown obstacle preset "%s" (none | pond).', name);
    end
end
