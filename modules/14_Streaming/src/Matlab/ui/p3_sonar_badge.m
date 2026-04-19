function ax_out = p3_sonar_badge(parent, varargin)
% P3_SONAR_BADGE  顶栏声纳波纹装饰
%
% 功能：在 parent 容器中建一个 uiaxes，画 3 道同心弧 + 中心亮点，构成简化
%       声纳扫描视觉图标。
% 版本：V1.0.0（2026-04-17 视觉升级 Step 3）
% 输入：
%   parent  — uipanel / uigridlayout 句柄
%   可选 name-value：
%       'Radii'     — 3 个半径（默认 [0.35 0.65 0.95]）
%       'Alpha'     — 3 个透明度（默认 [0.95 0.6 0.35]）
% 输出：
%   ax_out  — 构造的 uiaxes 句柄

%% 1. 入参
p = inputParser;
p.addParameter('Radii', [0.35 0.65 0.95], @isnumeric);
p.addParameter('Alpha', [0.95 0.60 0.35], @isnumeric);
p.parse(varargin{:});
radii = p.Results.Radii(:)';
alph  = p.Results.Alpha(:)';

%% 2. 色板
S = p3_style();
P = S.PALETTE;

%% 3. 构造 axes
ax = uiaxes(parent);
ax.Color = P.surface;
ax.BackgroundColor = P.surface;
ax.XColor = 'none';
ax.YColor = 'none';
ax.Toolbar.Visible = 'off';
disableDefaultInteractivity(ax);
ax.XLim = [-1.1 1.1];
ax.YLim = [-1.1 1.1];
axis(ax, 'equal');
axis(ax, 'off');
hold(ax, 'on');

%% 4. 3 道半圆弧（上半圆 0-180°，模拟声纳扫描扇）
th = linspace(0, pi, 96);    % 上半圆
for k = 1:length(radii)
    r = radii(k);
    % 弧线（主色青，亮度由 alpha 近似）
    c = P.primary * alph(k) + P.surface * (1 - alph(k));
    line(ax, r*cos(th), r*sin(th), ...
        'Color', c, 'LineWidth', 1.8);
end

% 中心亮点
line(ax, 0, 0, 'Marker', 'o', 'MarkerSize', 6, ...
    'MarkerFaceColor', P.accent_sonar, ...
    'MarkerEdgeColor', P.primary_hi, ...
    'LineStyle', 'none');

% 声纳扫描线（一条对角亮线）
line(ax, [0 0.95*cos(pi/3)], [0 0.95*sin(pi/3)], ...
    'Color', P.accent_sonar, 'LineWidth', 1.2);

hold(ax, 'off');

ax_out = ax;

end
