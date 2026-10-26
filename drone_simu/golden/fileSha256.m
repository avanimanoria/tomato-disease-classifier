function h = fileSha256(path)
%FILESHA256 Upper-case hex SHA-256 of a file (Java MessageDigest; no toolbox needed).
    fid = fopen(path, 'r');
    assert(fid > 0, 'fileSha256:open', 'Cannot open %s', path);
    c = onCleanup(@() fclose(fid));
    bytes = fread(fid, Inf, '*uint8');
    md = java.security.MessageDigest.getInstance('SHA-256');
    if ~isempty(bytes), md.update(bytes); end
    d = typecast(md.digest(), 'uint8');
    h = upper(reshape(dec2hex(d, 2)', 1, []));
end
