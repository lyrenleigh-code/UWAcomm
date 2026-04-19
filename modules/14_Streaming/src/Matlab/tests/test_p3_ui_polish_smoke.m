function test_p3_ui_polish_smoke()
% TEST_P3_UI_POLISH_SMOKE  视觉美化 Step 1 冒烟测试
%
% 覆盖：
%   1. p3_style() 返回结构完整
%   2. p3_pick_font() fallback 链正确
%   3. p3_semantic_color() 关键词映射正确
%   4. metric card 构造（Step 3 启用）
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm\modules\14_Streaming\src\Matlab\tests');
%   clear functions; clear all;
%   diary('test_p3_ui_polish_smoke_results.txt');
%   run('test_p3_ui_polish_smoke.m');
%   diary off;

%% 0. 路径注册
this_dir   = fileparts(mfilename('fullpath'));
ui_dir     = fullfile(fileparts(this_dir), 'ui');
addpath(ui_dir);

pass = 0; fail = 0;

fprintf('========== p3_ui_polish Step 1 冒烟测试 ==========\n');

%% 1. p3_style() 结构
try
    S = p3_style();
    assert(isstruct(S) && isfield(S,'PALETTE') && isfield(S,'FONTS') ...
        && isfield(S,'SIZES') && isfield(S,'GLOW'), 'p3_style 四字段缺失');

    % PALETTE 必需色
    req_palette = {'primary','accent','success','danger','bg','surface', ...
        'text','text_muted','border_subtle','border_active','surface_glass', ...
        'accent_sonar','glow_cyan','chart_cyan'};
    % glow_cyan 存 GLOW 不存 PALETTE，调整
    req_palette = setdiff(req_palette, {'glow_cyan'});
    missing = req_palette(~isfield(S.PALETTE, req_palette));
    assert(isempty(missing), ...
        sprintf('PALETTE 缺: %s', strjoin(missing,', ')));

    % FONTS
    assert(isfield(S.FONTS,'code') && isfield(S.FONTS,'body') ...
        && isfield(S.FONTS,'title'), 'FONTS 缺 code/body/title');
    assert(ischar(S.FONTS.code) && ~isempty(S.FONTS.code), 'FONTS.code 非法');

    % SIZES
    assert(S.SIZES.h1 == 22 && S.SIZES.top_h == 96, ...
        sprintf('SIZES 数值异常 h1=%d top_h=%d', S.SIZES.h1, S.SIZES.top_h));

    % GLOW
    assert(isfield(S.GLOW,'border_width') && isfield(S.GLOW,'cyan_soft'), ...
        'GLOW 缺字段');

    fprintf('  [PASS] 1. p3_style() 结构完整\n'); pass = pass+1;
catch ME
    fprintf('  [FAIL] 1. p3_style(): %s\n', ME.message); fail = fail+1;
end

%% 2. p3_pick_font() fallback 链
try
    % 2.1 完全不存在 → fallback monospaced
    f = p3_pick_font({'AbsolutelyNotAFont_1234', 'AnotherGhost_9876'});
    assert(strcmp(f, 'monospaced'), ...
        sprintf('fallback 应为 monospaced 实际 %s', f));

    % 2.2 命中第一个存在项（Consolas 在 Windows 一般在）
    f2 = p3_pick_font({'AbsolutelyNotAFont_1234', 'Consolas', 'Arial'});
    sys_fonts = listfonts;
    if any(strcmpi(sys_fonts,'Consolas'))
        assert(strcmpi(f2,'Consolas'), ...
            sprintf('应命中 Consolas 实际 %s', f2));
    else
        % 若无 Consolas 也不应返回第一个不存在项
        assert(~strcmpi(f2,'AbsolutelyNotAFont_1234'), '不应命中不存在项');
    end

    % 2.3 空输入
    f3 = p3_pick_font({});
    assert(strcmp(f3, 'monospaced'), '空输入 fallback 错误');

    fprintf('  [PASS] 2. p3_pick_font() fallback 链\n'); pass = pass+1;
catch ME
    fprintf('  [FAIL] 2. p3_pick_font(): %s\n', ME.message); fail = fail+1;
end

%% 3. p3_semantic_color() 映射
try
    c_ok = p3_semantic_color('收敛');
    assert(c_ok.fg(2) > c_ok.fg(1), ...
        sprintf('收敛应偏绿 fg=[%.2f %.2f %.2f]', c_ok.fg));

    c_bad = p3_semantic_color('未收敛');
    assert(c_bad.fg(1) > c_bad.fg(2), ...
        sprintf('未收敛应偏红 fg=[%.2f %.2f %.2f]', c_bad.fg));

    c_busy = p3_semantic_color('进行中');
    assert(c_busy.fg(1) > 0.5 && c_busy.fg(2) > 0.5, ...
        sprintf('进行中应偏黄 fg=[%.2f %.2f %.2f]', c_busy.fg));

    c_idle = p3_semantic_color('空闲');
    assert(isfield(c_idle,'fg') && isfield(c_idle,'bg'), '空闲应有 fg/bg');

    c_unknown = p3_semantic_color('未知关键词xyz');
    assert(isfield(c_unknown,'fg'), '未知关键词应有 fg 字段');

    % 英文别名
    c_en = p3_semantic_color('converged');
    assert(isequal(c_en.fg, c_ok.fg), '英文 converged 应等同 收敛');

    fprintf('  [PASS] 3. p3_semantic_color() 映射\n'); pass = pass+1;
catch ME
    fprintf('  [FAIL] 3. p3_semantic_color(): %s\n', ME.message); fail = fail+1;
end

%% 4. metric card（Step 3 启用，Step 1 先跳过）
if exist('p3_metric_card','file') == 2
    try
        fig = uifigure('Visible','off');
        grid = uigridlayout(fig, [1 1]);
        h = p3_metric_card(grid, 'BER', '1.2e-3', '', 'primary');
        assert(isfield(h,'value') && isgraphics(h.value), 'metric card 缺 value handle');
        close(fig);
        fprintf('  [PASS] 4. p3_metric_card()\n'); pass = pass+1;
    catch ME
        fprintf('  [FAIL] 4. p3_metric_card(): %s\n', ME.message); fail = fail+1;
    end
else
    fprintf('  [SKIP] 4. p3_metric_card (Step 3 未启用)\n');
end

%% 总结
fprintf('==================================================\n');
fprintf('Pass: %d  Fail: %d\n', pass, fail);
if fail > 0
    error('冒烟测试失败: %d 项', fail);
end

end
