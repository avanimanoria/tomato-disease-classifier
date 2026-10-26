function q = safeDiv(a, b)
%SAFEDIV a/b, or NaN when b == 0 (so empty denominators are visible, not 0 or Inf).
    if b == 0
        q = NaN;
    else
        q = a / b;
    end
end
