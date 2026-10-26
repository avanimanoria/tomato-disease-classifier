function [confirmed, result2] = confirmTarget(imagePath, cfg)
%CONFIRMTARGET Re-analyse a target plant's image before spraying is
%   allowed (Section 19).
%
%   [confirmed, result2] = confirmTarget(imagePath, cfg) loads the
%   plant's image AGAIN and runs detectDisease + calculateSeverity a
%   second time. confirmed is true only if this second look still says
%   DISEASED. If the second look says HEALTHY, the target must be
%   REJECTED and NOT sprayed (Section 19: "the first detection may have
%   been made from a greater distance").
%
%   NOTE: in this simulation the "second" image is technically the same
%   underlying file as the first look (no separate close-up camera model
%   exists yet), so with a deterministic classifier confirmed will
%   currently always agree with the first detection. This function's
%   job is to have the CORRECT re-check architecture in place - a real
%   second (closer-range) image capture could be added later without
%   changing this function's interface.

    img = loadPlantImage(imagePath);
    result2 = detectDisease(img, cfg);
    result2 = calculateSeverity(result2);

    confirmed = (result2.label == "DISEASED");
end
