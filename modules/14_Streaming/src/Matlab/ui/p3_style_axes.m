function p3_style_axes(ax, varargin)
% P3_STYLE_AXES  深色科技风 axes 统一样式 V2
%
% 功能：给 uiaxes 应用深色 + 柔和 grid + 等宽坐标字体，替代主文件内联 style_dark_axes。
% 版本：V1.0.0（2026-04-17 视觉升级 Step 2）
% 输入：
%   ax   — uiaxes 句柄 / array
%   可选 name-value：
%       'GridStyle' — char（默认 ':'）
%       'GridAlpha' — 数值（默认 0.25）

%% 1. 入参
p = inputParser;
p.addParameter('GridStyle', ':');
p.addParameter('GridAlpha', 0.25, @isnumeric);
p.parse(varargin{:});
gs    = p.Results.GridStyle;
galph = p.Results.GridAlpha;

%% 2. 色板
S = p3_style();
P = S.PALETTE;
F = S.FONTS;

%% 3. 批处理
if ~iscell(ax), ax = {ax}; end
for k = 1:numel(ax)
    a = ax{k};
    if ~isgraphics(a), continue; end
    a.BackgroundColor = P.surface;
    a.Color           = P.surface;
    a.XColor          = P.text_muted;
    a.YColor          = P.text_muted;
    a.GridColor       = P.divider;
    a.GridAlpha       = galph;
    a.GridLineStyle   = gs;
    a.MinorGridColor  = P.divider;
    a.MinorGridAlpha  = 0.15;
    a.FontName        = F.code;
    a.FontSize        = 10;
    a.XGrid           = 'on';
    a.YGrid           = 'on';
    if ~isempty(a.Title),  a.Title.Color  = P.text;       end
    if ~isempty(a.XLabel), a.XLabel.Color = P.text_muted; end
    if ~isempty(a.YLabel), a.YLabel.Color = P.text_muted; end
end

end
