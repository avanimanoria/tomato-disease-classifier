function plants = sprayTarget(plants, plantIdx, cfg)
%SPRAYTARGET Simulate activating the pesticide pump (Section 20).
%
%   plants = sprayTarget(plants, plantIdx, cfg) marks the plant at row
%   plantIdx as sprayed, printing a simulated pump ON/OFF sequence.
%
%   THIS IS A SOFTWARE SIMULATION ONLY. No real pump, actuator, or
%   chemical-spraying hardware is activated by this function (Section 35).
%
%   Guards against spraying an already-sprayed plant twice (Section 26).

    if plants.SprayStatus(plantIdx) == "SPRAYED"
        fprintf('  %s already SPRAYED - skipping (duplicate spray prevented).\n', ...
            plants.ID(plantIdx));
        return;
    end

    sprayDuration = 2; % seconds, configurable

    plants.SprayStatus(plantIdx) = "SPRAYING";
    fprintf('  Pump: ON  (SIMULATED, duration %ds)\n', sprayDuration);
    fprintf('  Pump: OFF\n');

    plants.SprayStatus(plantIdx) = "SPRAYED";
    fprintf('  %s Spray Status: COMPLETED\n', plants.ID(plantIdx));
end
