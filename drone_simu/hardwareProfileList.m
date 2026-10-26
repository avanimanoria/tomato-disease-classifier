function [ids, labels] = hardwareProfileList()
%HARDWAREPROFILELIST Ids and labels of the VALID hardware profiles in profiles/*.json.
%   'assumedDefault' first. Invalid or uncited profiles are not offered (fail closed).
    d = dir(fullfile(fileparts(mfilename('fullpath')), 'profiles', '*.json'));
    ids = {}; labels = {};
    for i = 1:numel(d)
        try
            p = loadHardwareProfile(fullfile(d(i).folder, d(i).name));
        catch
            continue;
        end
        ids{end+1} = p.id; labels{end+1} = p.label; %#ok<AGROW>
    end
    k = find(strcmp(ids, 'assumedDefault'));
    o = [k, setdiff(1:numel(ids), k)];
    ids = ids(o); labels = labels(o);
end
