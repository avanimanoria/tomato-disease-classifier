function s = pipelineLabel(pc)
%PIPELINELABEL Short human-readable label of the algorithm choices in a PipelineConfig.
    P = pc.pipeline;
    s = sprintf('%s | %s | %s | %s | %s | %s', P.controller, P.routing, P.sprayCompensation, P.localization, P.kernel, P.perception);
    if isfield(P, 'geolocateTargets') && P.geolocateTargets, s = [s ' | geolocated']; end
    if ~strcmp(pc.mode, 'manual'), s = [pc.mode ': ' s]; end
end
