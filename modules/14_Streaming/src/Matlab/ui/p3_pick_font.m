function name = p3_pick_font(candidates)
% P3_PICK_FONT  按优先级探测可用字体
%
% 功能：给定候选字体名 cell array，返回系统 `listfonts` 首个命中项；
%       全部缺失时回退 MATLAB 通用字体族 `'monospaced'`（保证可用）。
% 版本：V1.0.0（2026-04-17 视觉升级 Step 1 引入）
% 输入：
%   candidates  — cell array of char/string，优先级从高到低
% 输出：
%   name        — char，首个命中字体名（或 fallback）

%% 1. 入参校验
if nargin < 1 || isempty(candidates)
    name = 'monospaced';
    return;
end
if ~iscell(candidates)
    candidates = {candidates};
end

%% 2. 获取系统字体列表（结果缓存）
persistent sys_fonts
if isempty(sys_fonts)
    try
        sys_fonts = listfonts;
    catch
        sys_fonts = {};
    end
end

%% 3. 顺序匹配（大小写不敏感）
for k = 1:numel(candidates)
    c = char(candidates{k});
    if isempty(c), continue; end
    hit = any(strcmpi(sys_fonts, c));
    if hit
        name = c;
        return;
    end
end

%% 4. Fallback
name = 'monospaced';

end
