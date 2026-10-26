function [pc, warns] = loadPipelineConfig(src)
%LOADPIPELINECONFIG Read a PipelineConfig (JSON file or struct) onto the legacy defaults.
%
%   [pc, warns] = loadPipelineConfig(fileOrStruct)
%   Unknown fields are IGNORED (reported in warns); missing fields keep the legacy default;
%   a file without schemaVersion is treated as schema 1. The result is always a complete,
%   valid-shaped config - validatePipeline still decides whether it can run.
    if ischar(src) || isstring(src)
        txt = fileread(src);
        in = jsondecode(txt);
    else
        in = src;
    end
    warns = {};
    if ~isfield(in, 'schemaVersion')
        warns{end+1} = 'no schemaVersion: treated as schema 1';
    elseif in.schemaVersion ~= 1
        warns{end+1} = sprintf('schemaVersion %g is newer/older than 1: known fields only', in.schemaVersion);
    end
    [pc, warns] = merge(pipelineDefaults(), in, '', warns);
    pc.schemaVersion = 1;
end

function [d, warns] = merge(d, in, path, warns)
    if ~isstruct(in), return; end
    f = fieldnames(in);
    for i = 1:numel(f)
        k = f{i};
        if ~isfield(d, k)
            warns{end+1} = sprintf('unknown field ignored: %s%s', path, k); %#ok<AGROW>
            continue;
        end
        if isstruct(d.(k))
            [d.(k), warns] = merge(d.(k), in.(k), [path k '.'], warns);
        elseif ischar(d.(k))
            d.(k) = char(in.(k));
        elseif islogical(d.(k))
            d.(k) = logical(in.(k));
        else
            d.(k) = double(in.(k));
        end
    end
end
