function plot_otfs_dd_grid(dd_frame, title_str, pilot_pos)
% 功能：OTFS DD域格点可视化——显示数据/导频/保护区分布
% 版本：V1.0.0
% 输入：
%   dd_frame  - NxM DD域帧数据（复数矩阵）
%   title_str - 图标题 (默认 'OTFS DD Grid')
%   pilot_pos - 导频位置 [k, l]（可选，用于标注）

%% ========== 入参 ========== %%
if nargin < 3, pilot_pos = []; end
if nargin < 2 || isempty(title_str), title_str = 'OTFS DD Grid'; end

[N, M] = size(dd_frame);

%% ========== 绘图 ========== %%
figure('Name', title_str, 'NumberTitle', 'off', 'Position', [100,100,900,500]);

% DD域幅度热图
subplot(1,2,1);
imagesc(1:M, 1:N, abs(dd_frame));
colorbar; colormap('hot');
xlabel('时延索引 l'); ylabel('多普勒索引 k');
title('|x_{DD}[k,l]| 幅度');
set(gca, 'YDir', 'normal');

% 标注导频位置
if ~isempty(pilot_pos)
    hold on;
    plot(pilot_pos(2), pilot_pos(1), 'cs', 'MarkerSize', 14, ...
         'MarkerFaceColor', 'c', 'LineWidth', 2);
    legend('导频', 'Location', 'best');
    hold off;
end

% DD域相位热图
subplot(1,2,2);
phase_map = angle(dd_frame);
phase_map(abs(dd_frame) < 1e-10) = 0;  % 零值相位置零
imagesc(1:M, 1:N, phase_map);
colorbar; colormap('hsv');
xlabel('时延索引 l'); ylabel('多普勒索引 k');
title('∠x_{DD}[k,l] 相位');
set(gca, 'YDir', 'normal');
clim([-pi, pi]);

sgtitle(sprintf('%s  (N=%d, M=%d, 格点=%d)', title_str, N, M, N*M));

end
