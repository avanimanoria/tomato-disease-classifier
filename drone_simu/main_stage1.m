%% STAGE 1 TEST SCRIPT
% Tests: config -> generateField -> generatePlants -> generateZigZagPath
%
% HOW TO RUN:
%   1. Open MATLAB.
%   2. Set the current folder to AgriculturalDroneSimulation/.
%   3. Open this file and press F5 (Run), or type: main_stage1
%
% WHAT YOU SHOULD SEE:
%   - Console output: field summary (rows, plants/row, total plants).
%   - A figure with: field boundary rectangle, green plant dots, and a
%     blue dashed zig-zag path connecting the row corners.

clear; clc; close all;

cfg       = config();
fieldInfo = generateField(cfg);
plants    = generatePlants(cfg, fieldInfo);
path      = generateZigZagPath(cfg, fieldInfo);

disp('First 5 plants:');
disp(plants(1:5,:));

disp('Zig-zag path corner points [X Y Z]:');
disp(path);

%% Visualization
figure('Name','Stage 1: Field, Plants, Zig-Zag Path');
hold on; grid on; axis equal;
xlabel('X (m)'); ylabel('Y (m)');
title(sprintf('Field %gm x %gm | %d plants | %d rows', ...
    cfg.fieldLength, cfg.fieldWidth, fieldInfo.totalPlants, fieldInfo.numRows));

% field boundary
rectangle('Position',[0 0 cfg.fieldLength cfg.fieldWidth], ...
    'EdgeColor','k','LineWidth',1.5);

% plants
scatter(plants.X, plants.Y, 20, 'g', 'filled', 'DisplayName','Plants');

% zig-zag path
plot(path(:,1), path(:,2), 'b--o', 'LineWidth',1.2, 'DisplayName','Zig-Zag Path');

legend('Location','bestoutside');
hold off;

fprintf('\nStage 1 complete. Check the plot: field boundary, %d plants, zig-zag path.\n', ...
    fieldInfo.totalPlants);
