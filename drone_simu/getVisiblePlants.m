function visibleIdx = getVisiblePlants(plants, camera)
%GETVISIBLEPLANTS Find plants inside the camera's field of view that
%   haven't been seen yet (Section 9 / 27).
%
%   visibleIdx = getVisiblePlants(plants, camera) returns row indices
%   into the plants table for plants that are:
%     1) within camera.radius of camera.center, AND
%     2) still in the "NOT_SEEN" state.
%
%   Plants already SEEN/ANALYSED are excluded so they are not
%   re-processed every timestep just because the drone lingers nearby
%   (Section 5: "do not analyse it again unless deliberately rechecked").

    dx = plants.X - camera.center(1);
    dy = plants.Y - camera.center(2);
    dist = sqrt(dx.^2 + dy.^2);

    inView  = dist <= camera.radius;
    notSeen = plants.State == "NOT_SEEN";

    visibleIdx = find(inView & notSeen);
end
