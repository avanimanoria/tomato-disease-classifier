function imu = simulateIMU(drone, prevDrone, dt)
%SIMULATEIMU  SIMULATED SENSOR INPUT — stands in for a real IMU chip.
%
%   imu = simulateIMU(drone, prevDrone, dt) estimates acceleration and
%   orientation rate from the change in true simulated position between
%   two timesteps, plus small noise. This is NOT a physics model of an
%   actual IMU — it exists so the rest of the navigation code has a
%   stable interface (imu.accel, imu.gyro) that can later be replaced
%   with a driver reading a real IMU chip without changing any other file.

    noiseAccel = 0.02;   % m/s^2, small simulated sensor noise
    noiseGyro  = 0.01;   % rad/s

    if dt <= 0
        dt = 0.1;
    end

    vel     = (drone.pos - prevDrone.pos) / dt;
    prevVel = (prevDrone.pos - prevDrone.pos) / dt; % zero on first call
    accel   = (vel - prevVel) / dt;

    imu.accel = accel + noiseAccel * randn(1,3);   % [ax, ay, az]
    imu.gyro  = noiseGyro * randn(1,3);            % [roll, pitch, yaw rates]
    imu.timestamp = drone.missionTime;
end
