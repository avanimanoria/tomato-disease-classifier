function [hAll, hScenario, hPipeline] = pipelineHash(pc)
%PIPELINEHASH SHA-256 identifiers of a PipelineConfig (full, scenario part, pipeline part).
%   Short 12-character prefixes are shown in the UI; exports carry the full hashes.
    hAll = sha(jsonencode(orderfields2(pc)));
    hScenario = sha(jsonencode(orderfields2(pc.scenario)));
    hPipeline = sha(jsonencode(struct('mode', pc.mode, 'pipeline', orderfields2(pc.pipeline))));
end

function h = sha(str)
    md = java.security.MessageDigest.getInstance('SHA-256');
    md.update(uint8(unicode2native(str, 'UTF-8')));
    h = lower(reshape(dec2hex(typecast(md.digest(), 'uint8'), 2)', 1, []));
end

function s = orderfields2(s)
    if isstruct(s)
        s = orderfields(s);
        f = fieldnames(s);
        for i = 1:numel(f), s.(f{i}) = orderfields2(s.(f{i})); end
    end
end
