function handles = p4_plot_channel_stem(ax, delays_sec, h_tap, varargin)
% P3_PLOT_CHANNEL_STEM  深色主题彩色 stem 绘信道抽头
%
% 功能：以 |h| 幅度映射 cyan→amber 渐变色绘制 stem 图，替代默认单色，
%       便于肉眼快速识别主径与弱径。
% 版本：V1.0.0（2026-04-17 视觉升级 Step 2）
% 输入：
%   ax          — uiaxes 句柄
%   delays_sec  — 抽头时延（秒），横轴
%   h_tap       — 抽头增益（复或实），绝对值决定幅度
%   可选 name-value：
%       'Label'      — char，legend 标签（默认 '|h|'）
%       'MarkerSize' — 数值（默认 6）
% 输出：
%   handles  — struct：stems (line array), markers (line array)

%% 1. 入参解析
p = inputParser;
p.addParameter('Label', '|h|', @(s) ischar(s) || isstring(s));
p.addParameter('MarkerSize', 7, @isnumeric);
p.parse(varargin{:});
label = char(p.Results.Label);
msz   = p.Results.MarkerSize;

%% 2. 参数校验
delays_sec = delays_sec(:);
h_abs = abs(h_tap(:));
if length(h_abs) ~= length(delays_sec)
    error('delays_sec 与 h_tap 长度不一致: %d vs %d', ...
          length(delays_sec), length(h_abs));
end
if isempty(h_abs)
    cla(ax);
    text(ax, 0.5, 0.5, '(无抽头数据)', 'Units','normalized', ...
         'HorizontalAlignment','center', 'Color', [0.5 0.5 0.5]);
    handles = struct('stems', [], 'markers', []);
    return;
end

%% 3. 色板 & 色阶
S = p4_style();
P = S.PALETTE;
cyan  = P.chart_cyan;
amber = P.chart_amber;

hmax = max(h_abs);
if hmax <= 0, hmax = 1; end
norm_h = h_abs / hmax;            % [0,1]
% 色阶：弱径偏 cyan，强径偏 amber
colors = cyan + norm_h .* (amber - cyan);   % N×3

%% 4. 绘图
cla(ax);
hold(ax, 'on');

stems   = gobjects(length(h_abs), 1);
markers = gobjects(length(h_abs), 1);

% 时延轴转 ms（更直观）
x_ms = delays_sec * 1e3;

for k = 1:length(h_abs)
    stems(k) = line(ax, [x_ms(k) x_ms(k)], [0 h_abs(k)], ...
        'Color', [colors(k,:) 0.85], 'LineWidth', 1.8);
    markers(k) = line(ax, x_ms(k), h_abs(k), ...
        'Marker', 'o', 'MarkerSize', msz, ...
        'MarkerFaceColor', colors(k,:), ...
        'MarkerEdgeColor', P.text, 'LineStyle', 'none');
end

% 基线
yline(ax, 0, 'Color', P.divider, 'LineStyle', '-', 'LineWidth', 0.5);

xlabel(ax, '时延 (ms)', 'Color', P.text_muted);
ylabel(ax, label, 'Color', P.text_muted);

% Y 轴留白
ylim(ax, [0 hmax * 1.15]);
if length(x_ms) > 1
    xspan = max(x_ms) - min(x_ms);
    if xspan < 1e-6, xspan = 1; end
    xlim(ax, [min(x_ms)-xspan*0.05, max(x_ms)+xspan*0.05]);
end

hold(ax, 'off');
grid(ax, 'on');
ax.GridColor = P.divider;
ax.GridAlpha = 0.25;
ax.GridLineStyle = ':';

handles = struct('stems', stems, 'markers', markers);

end
