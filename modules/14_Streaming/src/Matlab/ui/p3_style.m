function S = p3_style()
% P3_STYLE  p3_demo_ui 样式单一事实源
%
% 功能：集中返回深色科技风的色板 / 字体 / 尺寸 / 发光参数，避免 demo 主文件中散落魔法值。
% 版本：V1.0.0（2026-04-17 视觉升级 Step 1 引入）
% 输出：
%   S.PALETTE  — 颜色 token（RGB [0,1]）
%   S.FONTS    — 字体名（跨平台探测）
%   S.SIZES    — 字号/行高/间距
%   S.GLOW     — 发光/边框参数

%% ---- 颜色 PALETTE（深空黑蓝 + 青/琥珀双主色）----
PALETTE = struct( ...
    'primary',      [0.20 0.78 0.95], ...  % cyan 青（主色/数据高亮）
    'primary_hi',   [0.45 0.90 1.00], ...
    'primary_lo',   [0.10 0.45 0.60], ...  % 青色暗阶
    'accent',       [0.95 0.62 0.20], ...  % amber 暖橙（主动作）
    'accent_hi',    [1.00 0.75 0.35], ...
    'accent_lo',    [0.55 0.35 0.12], ...
    'success',      [0.30 0.90 0.55], ...  % emerald 翠绿
    'success_bg',   [0.08 0.18 0.12], ...
    'warning',      [0.98 0.78 0.30], ...
    'warning_bg',   [0.20 0.16 0.08], ...
    'danger',       [0.98 0.40 0.45], ...
    'danger_bg',    [0.22 0.09 0.10], ...
    'bg',           [0.04 0.06 0.09], ...  % 深空黑蓝（主背景）
    'surface',      [0.09 0.12 0.17], ...  % 面板底
    'surface_alt',  [0.12 0.16 0.22], ...  % 二级面板
    'surface_glass',[0.14 0.19 0.26], ...  % 玻璃层（card 底）
    'divider',      [0.18 0.22 0.29], ...  % 分割/静态按钮
    'border_subtle',[0.22 0.28 0.36], ...  % 静态描边
    'border_active',[0.20 0.78 0.95], ...  % 激活描边（= primary）
    'text',         [0.88 0.92 0.96], ...  % 主文字
    'text_muted',   [0.55 0.62 0.72], ...  % 次要文字
    'text_dim',     [0.40 0.46 0.54], ...  % 第三级文字
    'info_bg',      [0.08 0.14 0.22], ...
    'panel_tx_bg',  [0.08 0.13 0.19], ...  % TX 面板底（蓝冷倾向）
    'panel_rx_bg',  [0.11 0.10 0.14], ...  % RX 面板底（紫暖倾向）
    'accent_sonar', [0.30 0.90 0.55], ...  % 声纳脉冲色（= success）
    'chart_cyan',   [0.25 0.80 0.98], ...  % 绘图用主色
    'chart_amber',  [0.98 0.68 0.28], ...
    'chart_pink',   [0.98 0.50 0.70], ...
    'chart_green',  [0.40 0.92 0.58], ...
    'chart_violet', [0.62 0.52 0.98]);
S.PALETTE = PALETTE;

%% ---- 字体（探测 fallback 链）----
% 等宽字体：metric 大数 / 代码 / 数据
FONTS.code = p3_pick_font({ ...
    'JetBrains Mono', 'JetBrainsMono NF', 'Cascadia Mono', 'Cascadia Code', ...
    'Consolas', 'monospaced'});

% 比例字体（正文、标题）
FONTS.body = p3_pick_font({ ...
    'Segoe UI', 'Microsoft YaHei UI', 'Helvetica Neue', 'Arial', 'sansserif'});

FONTS.title = FONTS.body;   % MATLAB uilabel 不支持字重族，靠 FontWeight 区分
FONTS.metric = FONTS.code;  % 数字用等宽
S.FONTS = FONTS;

%% ---- 字号 / 行高 / 间距 ----
SIZES = struct( ...
    'h1',            22, ...   % 顶栏主标题
    'h2',            15, ...   % 面板标题
    'h3',            13, ...   % 分组小标题
    'body',          12, ...   % 正文
    'body_sm',       11, ...
    'metric_value',  22, ...   % 指标大数
    'metric_unit',    9, ...   % 指标单位
    'caption',        9, ...   % 说明小字
    'row_h',         28, ...   % 表单行高
    'title_h',       25, ...   % 标题行高
    'metric_card_h', 74, ...   % 指标卡高
    'tab_h',        320, ...   % 底部 tab 总高
    'top_h',         96, ...   % 顶栏高（从 110 降）
    'padding',        8, ...
    'padding_lg',    12, ...
    'spacing',        6, ...
    'spacing_lg',    10);
S.SIZES = SIZES;

%% ---- 发光 / 边框参数 ----
% MATLAB uipanel 没有真正的 alpha，这里用 RGB 近似表达 "半透发光" 的混合色
GLOW = struct( ...
    'border_width',       1, ...
    'border_width_hot',   2, ...
    'cyan_soft',          [0.12 0.38 0.48], ...   % cyan α=0.35 over bg
    'amber_soft',         [0.48 0.32 0.15], ...   % amber α=0.35 over bg
    'success_soft',       [0.12 0.36 0.22], ...
    'danger_soft',        [0.44 0.20 0.22], ...
    'flash_primary',      [0.20 0.78 0.95], ...
    'flash_accent',       [0.95 0.62 0.20]);
S.GLOW = GLOW;

end
