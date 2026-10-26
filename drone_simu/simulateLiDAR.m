function lidar = simulateLiDAR(drone)
%SIMULATELIDAR  SIMULATED SENSOR INPUT — stands in for a downward-facing
%   LiDAR/ultrasonic rangefinder used to hold altitude above the crop
%   canopy without GPS.
%
%   lidar = simulateLiDAR(drone) returns an estimated distance to the
%   ground beneath the drone (assumed flat field at Z=0 here), with
%   small noise. Real hardware would return a genuine time-of-flight
%   range reading; this keeps the same interface (lidar.altitude) so a
%   real rangefinder driver can be swapped in later.

    noiseRange = 0.02; % m simulated noise

    groundLevel = 0; % flat field assumption for this prototype
    trueAltitude = drone.pos(3) - groundLevel;

    lidar.altitude  = max(0, trueAltitude + noiseRange * randn());
    lidar.valid     = true; % would be false on real hardware if out of range
    lidar.timestamp = drone.missionTime;
end
