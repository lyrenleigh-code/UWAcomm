function c = p4_semantic_color(keyword)
% P3_SEMANTIC_COLOR  关键词 → 前景/背景语义色
%
% 功能：将状态关键词映射到色板里的前景/背景颜色（RGB [0,1]），统一收敛/未收敛/
%       进行中/失败/空闲等状态的视觉语义。未命中关键词返回中性灰。
% 版本：V1.0.0（2026-04-17 视觉升级 Step 1 引入）
% 输入：
%   keyword  — char / string，中英文关键词
% 输出：
%   c  — struct 含 fg / bg 字段，RGB [0,1]

%% 1. 入参规范化
if nargin < 1, keyword = ''; end
kw = lower(strtrim(char(keyword)));

%% 2. 从 p3_style 取色板（保证唯一色源）
S = p4_style();
P = S.PALETTE;

%% 3. 关键词 → 色对
switch kw
    case {'收敛', 'converged', 'ok', 'pass', '成功', 'success', '通过'}
        c.fg = P.success;       c.bg = P.success_bg;

    case {'未收敛', 'diverged', '发散', 'fail', 'failed', '失败', 'error'}
        c.fg = P.danger;        c.bg = P.danger_bg;

    case {'进行中', 'busy', 'running', '检测中', 'decoding', '处理中'}
        c.fg = P.warning;       c.bg = P.warning_bg;

    case {'空闲', 'idle', 'ready', '待机', '就绪'}
        c.fg = P.text_muted;    c.bg = P.surface;

    case {'激活', 'active', 'on', '开启'}
        c.fg = P.primary;       c.bg = P.info_bg;

    case {'关闭', 'off', 'disabled', '停用'}
        c.fg = P.text_dim;      c.bg = P.surface;

    otherwise
        % 未知关键词 → 中性
        c.fg = P.text_muted;    c.bg = P.surface;
end

end
