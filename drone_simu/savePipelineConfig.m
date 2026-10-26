function savePipelineConfig(pc, file)
%SAVEPIPELINECONFIG Write a PipelineConfig to JSON (schema v1, human-editable).
    fid = fopen(file, 'w');
    assert(fid > 0, 'savePipelineConfig:open', 'Cannot write %s', file);
    c = onCleanup(@() fclose(fid));
    fwrite(fid, jsonencode(pc, 'PrettyPrint', true), 'char');
end
