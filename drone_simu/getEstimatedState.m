function est = getEstimatedState(world, cfg) %#ok<INUSD>
%GETESTIMATEDSTATE Estimator interface: what the drone BELIEVES its state is.
%
%   INTERNAL-2 PLACEHOLDER: this returns the ground-truth position unchanged
%   (est.source = "GROUND_TRUTH_PASSTHROUGH"). It is NOT GPS-independent
%   localization. The controller and mission planner read ONLY this
%   function, never world.pos directly, so a real estimator (e.g. the
%   existing estimatePosition.m Kalman filter, or IMU+LiDAR fusion) can be
%   substituted here later without touching the controller.
%
%   Three states kept separate in Internal-2:
%     world.pos   - ground truth (physics only)
%     est.pos     - this function's output (what controllers/planners use)
%     vCmd        - what the controller commands (logged in flyReference)

    est.pos    = world.pos;
    est.source = "GROUND_TRUTH_PASSTHROUGH";
    if isfield(world, 'adv') && world.adv.locOn     % ENHANCEMENT (opt-in): modelled odometry error
        if isfield(world.adv, 'sf')                 % 'sensorFusion': the EKF state itself - no truth involved
            est.pos    = world.adv.sf.x(1:2)';
            est.source = "EKF_SENSOR_FUSION";
            return;
        end
        est.pos    = world.pos + world.adv.estErr;
        est.source = "SIMULATED_ODOMETRY_WITH_FIXES";
    end
end
