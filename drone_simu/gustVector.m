function g = gustVector(cfg, t)
%GUSTVECTOR Zero-mean wind gust [gx gy] (m/s) at time t (enhancement 'gusts').
%
%   Sum of nComponents sinusoids per axis with log-spaced periods between
%   periodMin_s and periodMax_s and seeded random phases; amplitudes are set so
%   the RMS per axis equals sigma_mps. Deterministic, stateless in t. A simple
%   turbulence stand-in (not a Dryden/von Karman spectrum). [ASSUMED] values.

    persistent key comps
    G = cfg.enhancements.gusts;
    k = [G.seed, G.nComponents, G.periodMin_s, G.periodMax_s];
    if ~isequal(key, k)
        s = RandStream('mt19937ar', 'Seed', G.seed);
        n = max(1, round(G.nComponents));
        f = logspace(log10(1 / G.periodMax_s), log10(1 / G.periodMin_s), n)';
        comps.w = 2 * pi * f;
        comps.phx = 2 * pi * rand(s, n, 1);
        comps.phy = 2 * pi * rand(s, n, 1);
        key = k;
    end
    a = G.sigma_mps * sqrt(2 / numel(comps.w));
    g = a * [sum(sin(comps.w * t + comps.phx)), sum(sin(comps.w * t + comps.phy))];
end
