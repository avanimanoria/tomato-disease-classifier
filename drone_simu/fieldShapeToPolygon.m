function poly = fieldShapeToPolygon(shape, p)
%FIELDSHAPETOPOLYGON Polygon (Nx2, m) for the UI's supported field shapes.
%
%   poly = fieldShapeToPolygon('Rectangle', struct('length', L, 'width', W))
%   poly = fieldShapeToPolygon('Trapezoid', struct('bottom', B, 'top', T, 'height', H))
%
%   Trapezoid is symmetric about x = B/2; bottom 30, top 18, height 14 reproduces
%   the default cfg.internal2.field.polygon [0 0; 30 0; 24 14; 6 14].
%   'UShape' (length, width) is CONCAVE: use it with cfg.internal2.field.keepAllRuns = true
%   (otherwise the legacy generator keeps only the longest piece of each split row).

    switch shape
        case 'Rectangle'
            L = p.length; W = p.width;
            poly = [0 0; L 0; L W; 0 W];
        case 'Trapezoid'
            B = p.bottom; T = p.top; H = p.height;
            if T > B
                error('fieldShapeToPolygon:invalid', 'Trapezoid top width must not exceed bottom width.');
            end
            poly = [0 0; B 0; (B + T) / 2 H; (B - T) / 2 H];
        case 'UShape'                  % ENHANCEMENT: concave - a notch in the middle of the top edge
            L = p.length; W = p.width;
            poly = [0 0; L 0; L W; 2*L/3 W; 2*L/3 W/2; L/3 W/2; L/3 W; 0 W];
        otherwise
            error('fieldShapeToPolygon:badShape', 'Unsupported field shape "%s" (Rectangle | Trapezoid | UShape).', shape);
    end
end
