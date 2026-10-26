function n = advNoise(seed, k)
%ADVNOISE Deterministic standard-normal 1x2 sample number k of a seeded sequence.
%   Private stream per seed (global rng untouched); identical across runs.
    persistent cache
    if isempty(cache), cache = containers.Map('KeyType', 'double', 'ValueType', 'any'); end
    if ~isKey(cache, seed) || size(cache(seed), 2) < k
        N = max(200000, 2 * k);
        s = RandStream('mt19937ar', 'Seed', seed);
        cache(seed) = randn(s, 2, N);          % prefix is identical whatever N is
    end
    A = cache(seed);
    n = A(:, k)';
end
