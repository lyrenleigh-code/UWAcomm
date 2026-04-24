function h = p4_metric_card(parent, label, value, unit, tone)
% P3_METRIC_CARD  深色科技风 metric 指标卡
%
% 功能：构造 label（小 / 灰）+ value（大 / 等宽 / 语义色）+ unit（小 / 灰）
%       的三层指标卡，作为 bento 布局原子。返回 handles struct，便于回调更新。
% 版本：V1.0.0（2026-04-17 视觉升级 Step 3）
% 输入：
%   parent  — uigridlayout 或 uipanel 句柄
%   label   — char，字段名（如 'BER' / 'estimated_snr'）
%   value   — char，初始数值文本（如 '—' / '0.00'）
%   unit    — char，单位（如 'dB' / ''），可空
%   tone    — char，语义色调：'primary'(青)/'accent'(橙)/'success'/'warning'/
%             'danger'/'muted'
% 输出：
%   h  — struct 含字段 panel / label / value / unit / tone
%        （后续 app.lbl_* = h.value 可无缝替换旧绑定）

%% 1. 入参规范化
if nargin < 4, unit = ''; end
if nargin < 5 || isempty(tone), tone = 'primary'; end

S = p4_style();
P = S.PALETTE;
F = S.FONTS;

%% 2. tone → value 色
switch lower(tone)
    case 'primary',   value_color = P.primary;
    case 'accent',    value_color = P.accent_hi;
    case 'success',   value_color = P.success;
    case 'warning',   value_color = P.warning;
    case 'danger',    value_color = P.danger;
    case 'muted',     value_color = P.text_muted;
    otherwise,        value_color = P.primary;
end

%% 3. 外层 panel（surface_glass 作底）
panel = uipanel(parent, 'Title', '', ...
    'BackgroundColor', P.surface_glass, ...
    'BorderType', 'line');
if isprop(panel, 'BorderColor')
    panel.BorderColor = P.border_subtle;
end
if isprop(panel, 'BorderWidth')
    panel.BorderWidth = 1;
end

%% 4. 内部 3 行网格：label / value / unit
inner = uigridlayout(panel, [3 1]);
inner.RowHeight = {16, '1x', 14};
inner.Padding = [10 6 10 6];
inner.RowSpacing = 1;
inner.BackgroundColor = P.surface_glass;

lbl = uilabel(inner, ...
    'Text', char(label), ...
    'FontSize', 10, ...
    'FontName', F.body, ...
    'FontColor', P.text_muted, ...
    'HorizontalAlignment', 'left');
lbl.Layout.Row = 1;

val = uilabel(inner, ...
    'Text', char(value), ...
    'FontSize', S.SIZES.metric_value, ...
    'FontWeight', 'bold', ...
    'FontName', F.metric, ...
    'FontColor', value_color, ...
    'HorizontalAlignment', 'left', ...
    'VerticalAlignment', 'center');
val.Layout.Row = 2;

un = uilabel(inner, ...
    'Text', char(unit), ...
    'FontSize', S.SIZES.metric_unit, ...
    'FontName', F.code, ...
    'FontColor', P.text_dim, ...
    'HorizontalAlignment', 'left');
un.Layout.Row = 3;

%% 5. 返回 handles
h = struct();
h.panel = panel;
h.label = lbl;
h.value = val;
h.unit  = un;
h.tone  = tone;

end
