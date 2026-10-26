function ok = runDemonstrations(outFile)
%RUNDEMONSTRATIONS Manual V1 section 8 item 9: the six hand-off demonstrations, with evidence.
%
%   ok = runDemonstrations()            -> demo_reports/demonstrations_<timestamp>.txt
%   1 baseline run reproduces the frozen golden mission
%   2 one manual pipeline run (non-legacy choices in every runnable stage)
%   3 paired comparison changing ONE algorithm (and an unpaired comparison refused)
%   4 Experiment F frozen results still readable and checksum-intact; re-running is refused
%   5 the unavailable CNN is explicitly disabled (registry, validator, adapter)
%   6 failure-safe recovery: invalid / infeasible requests fail closed and the legacy
%     mission is still reproduced afterwards
%   Nothing here writes to results/ or golden/.
    here = fileparts(mfilename('fullpath'));
    if nargin < 1
        d = fullfile(here, 'demo_reports'); if ~isfolder(d), mkdir(d); end
        outFile = fullfile(d, ['demonstrations_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')) '.txt']);
    end
    L = {}; ok = true;
    say('AGRICULTURAL DRONE - MANUAL V1 DEMONSTRATIONS  (%s, MATLAB %s, commit %s)', ...
        char(datetime('now')), version, gitHead(here));
    G = load(fullfile(here, 'golden', 'legacy_mission_golden.mat'));

    % 1 ----------------------------------------------------------------
    head(1, 'Baseline run (legacy defaults) reproduces the frozen golden mission');
    r0 = runPipeline(pipelineDefaults());
    run = r0.run; run.name = G.baseline.run.name;
    check(isequaln(run, G.baseline.run), 'runPipeline(pipelineDefaults()) == golden/legacy_mission_golden.mat baseline (bit-identical)');
    say('   pipeline: %s | deposition %.2f %% | mission time %.1f s', pipelineLabel(r0.pc), ...
        r0.metrics.spray.targetDepositionPct, r0.run.finalWorld.time);

    % 2 ----------------------------------------------------------------
    head(2, 'One manual pipeline run');
    pc = pipelineDefaults();
    pc.scenario.wind.enabled = true; pc.scenario.gust_mps = 0.3;
    pc.pipeline.localization = 'sensorFusion'; pc.pipeline.geolocateTargets = true;
    pc.pipeline.controller = 'pid'; pc.pipeline.routing = 'nearestNeighbourOrOpt';
    pc.pipeline.sprayCompensation = 'wind'; pc.pipeline.kernel = 'windStretched';
    r2 = runPipeline(pc);
    say('   pipeline: %s', pipelineLabel(r2.pc));
    say('   run %s  scenario %s  pipeline %s', r2.runId, r2.scenarioHash(1:12), r2.pipelineHash(1:12));
    T = r2.runMetrics;
    for m = ["Detector recall", "Estimate error RMSE", "NEES (consistency, ~2 ideal)", "Target deposition", "Treatment success", "Mission time"]
        k = find(T.Metric == m, 1);
        say('   %-32s %10.3f %s', m, T.Value(k), T.Unit(k));
    end
    check(~isequaln(r2.run.log1, r0.run.log1), 'the selected pipeline changed the flown mission (not a label)');

    % 3 ----------------------------------------------------------------
    head(3, 'Paired comparison changing ONE algorithm (Pass-2 routing)');
    pa = pc; pa.pipeline.routing = 'nearestNeighbour';
    ra = runPipeline(pa);
    C = comparePipelineRuns({ra, r2});
    check(strcmp(ra.scenarioHash, r2.scenarioHash), 'same scenario hash (field, seeds, wind / gust / sensor traces)');
    check(isequaln(ra.run.log1, r2.run.log1), 'Pass 1 identical - only Pass-2 routing differs');
    for m = ["Planned (geometric) Pass-2 route", "Flown Pass-2 distance", "Target deposition", "Mission time"]
        k = find(C.Metric == m, 1);
        say('   %-34s NN %9.2f | NN+Or-opt %9.2f | diff %+8.2f %s', m, C.Run1(k), C.Run2(k), C.Run2(k) - C.Run1(k), C.Unit(k));
    end
    pu = pa; pu.scenario.field.seed = 7;
    ru = runPipeline(pu);
    check(threw(@() comparePipelineRuns({ra, ru}), 'comparePipelineRuns:unpaired'), 'a different field seed is refused as UNPAIRED');

    % 4 ----------------------------------------------------------------
    head(4, 'Experiment F frozen results readable and intact');
    B = load(fullfile(here, 'results', 'benchmark', 'benchmark.mat'));
    check(isstruct(B) && ~isempty(fieldnames(B)), 'results/benchmark/benchmark.mat loads');
    CS = readtable(fullfile(here, 'golden', 'frozen_checksums.csv'), 'Delimiter', ',', 'TextType', 'string');
    bad = 0;
    for i = 1:height(CS)
        if ~strcmpi(fileSha256(fullfile(here, CS.path(i))), CS.sha256(i)), bad = bad + 1; end
    end
    check(bad == 0, sprintf('%d frozen files, %d checksum mismatches', height(CS), bad));
    rep = fileread(fullfile(here, 'results', 'benchmark', 'benchmark_report.md'));
    h2 = regexp(rep, '- H2[^\n]*', 'match', 'once');
    say('   %s', h2(1:min(end, 160)));
    check(threw(@() runExperimentF(fullfile(here, 'results', 'benchmark')), 'runExperimentF:frozen'), ...
        'runExperimentF refuses to overwrite the frozen benchmark');

    % 5 ----------------------------------------------------------------
    head(5, 'Unavailable CNN explicitly disabled');
    R = pipelineRegistry();
    k = strcmp(R.perception.id, 'cnn');
    check(~R.perception.available(k), sprintf('registry: cnn available = false (%s)', R.perception.note{k}));
    pcn = pipelineDefaults(); pcn.pipeline.perception = 'cnn';
    [v, errs] = validatePipeline(pcn);
    check(~v && any(contains(errs, 'UNAVAILABLE')), ['validator: ' strjoin(errs, '; ')]);
    check(threw(@() perceptionCNNAdapter([], [], config()), 'perceptionCNNAdapter:unavailable'), ...
        'adapter raises perceptionCNNAdapter:unavailable (no silent fallback to the parametric detector)');

    % 6 ----------------------------------------------------------------
    head(6, 'Failure-safe recovery');
    pb = pipelineDefaults(); pb.scenario.hardwareProfile = 'notAProfile';
    check(threw(@() runPipeline(pb), 'resolvePipeline:invalid'), 'unknown hardware profile rejected before any flight');
    c = applyPreset(config(), 'Baseline');
    c.internal2.field.polygon = fieldShapeToPolygon('Rectangle', struct('length', 30, 'width', 14));
    c.internal2.field.keepAllRuns = true; c.internal2.field.obstacles = {[14 -1; 16 -1; 16 15; 14 15]};
    c.internal2.coverage.method = 'polygonDecomposition';
    check(threw(@() quietField(c), 'planCoverageDecomposition:infeasible'), ...
        'field split by a wall: coverage reports INFEASIBLE instead of clipping through it');
    r6 = runPipeline(pipelineDefaults());
    run = r6.run; run.name = G.baseline.run.name;
    check(isequaln(run, G.baseline.run), 'after the failures the legacy mission is still bit-identical to the golden run');

    say(''); say('RESULT: %s', ifelse(ok, 'ALL DEMONSTRATIONS PASSED', 'SOME DEMONSTRATIONS FAILED'));
    fid = fopen(outFile, 'w'); fprintf(fid, '%s\n', L{:}); fclose(fid);
    fprintf('%s\nReport: %s\n', strjoin(L, newline), outFile);

    function say(varargin), L{end+1} = sprintf(varargin{:}); end
    function head(n, t), say(''); say('[%d] %s', n, t); end
    function check(c, msg)
        if c, say('   PASS  %s', msg); else, say('   FAIL  %s', msg); ok = false; end
    end
end

function t = threw(f, id)
    t = false;
    try
        f();
    catch e
        t = strcmp(e.identifier, id);
    end
end

function f = quietField(c)
    evalc('f = generateIrregularField(c);');
end

function s = ifelse(c, a, b), if c, s = a; else, s = b; end, end

function h = gitHead(here)
    [st, h] = system(sprintf('git -C "%s" rev-parse --short HEAD', here));
    if st ~= 0, h = 'unknown'; end
    h = strtrim(h);
end
