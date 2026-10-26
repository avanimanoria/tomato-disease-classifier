function p = loadHardwareProfile(idOrFile)
%LOADHARDWAREPROFILE Read and VALIDATE a versioned hardware profile (profiles/<id>.json).
%
%   p = loadHardwareProfile('assumedDefault')   or   p = loadHardwareProfile('C:\...\x.json')
%   Each parameter: key (cfg.enhancements.<key>), value, unit, sourceType
%   (manufacturer | literature | synthetic), citation, range [lo hi]. Rejected (error):
%     hardwareProfile:notFound          unknown id / file
%     hardwareProfile:uncited           a manufacturer / literature value without a citation
%     hardwareProfile:range             a value outside its stated plausible range
%     hardwareProfile:unknownParameter  a key that is not an existing cfg.enhancements parameter
%     hardwareProfile:sourceType        a sourceType other than the three above
%   p.params: struct array (key, path, value, unit, sourceType, citation, range); p.provenance.
    if isfile(idOrFile)
        fn = char(idOrFile);
    else
        fn = fullfile(fileparts(mfilename('fullpath')), 'profiles', [char(idOrFile) '.json']);
    end
    if ~isfile(fn), error('hardwareProfile:notFound', 'Hardware profile "%s" not found.', idOrFile); end
    J = jsondecode(fileread(fn));
    p.id = J.id; p.version = J.version; p.label = J.label; p.description = J.description; p.file = fn;
    c0 = config();
    Q = J.parameters;
    if iscell(Q), Q = [Q{:}]; end
    p.params = struct('key', {}, 'path', {}, 'value', {}, 'unit', {}, 'sourceType', {}, 'citation', {}, 'range', {});
    for i = 1:numel(Q)
        q = Q(i);
        path = ['enhancements.' q.key];
        if ~hasPath(c0, path) || ~isnumeric(getPath(c0, path))
            error('hardwareProfile:unknownParameter', '%s: unknown parameter "%s".', p.id, q.key);
        end
        if ~any(strcmp(q.sourceType, {'manufacturer', 'literature', 'synthetic'}))
            error('hardwareProfile:sourceType', '%s: %s has sourceType "%s".', p.id, q.key, q.sourceType);
        end
        if ~strcmp(q.sourceType, 'synthetic') && isempty(strtrim(q.citation))
            error('hardwareProfile:uncited', '%s: %s is marked "%s" but has no citation.', p.id, q.key, q.sourceType);
        end
        if q.value < q.range(1) || q.value > q.range(2)
            error('hardwareProfile:range', '%s: %s = %g is outside the plausible range [%g, %g].', ...
                p.id, q.key, q.value, q.range(1), q.range(2));
        end
        p.params(end+1) = struct('key', q.key, 'path', path, 'value', q.value, 'unit', q.unit, ...
            'sourceType', q.sourceType, 'citation', q.citation, 'range', q.range(:)');
    end
    st = {p.params.sourceType};
    p.provenance = sprintf('%d manufacturer, %d literature, %d synthetic', sum(strcmp(st, 'manufacturer')), ...
        sum(strcmp(st, 'literature')), sum(strcmp(st, 'synthetic')));
end

function ok = hasPath(s, path)
    ok = true;
    for f = strsplit(path, '.')
        if ~isstruct(s) || ~isfield(s, f{1}), ok = false; return; end
        s = s.(f{1});
    end
end

function v = getPath(s, path)
    for f = strsplit(path, '.'), s = s.(f{1}); end
    v = s;
end
