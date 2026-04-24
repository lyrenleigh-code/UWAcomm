function test_p3_ui_smoke()
% TEST_P3_UI_SMOKE  P3 UI 重构 Step 2 冒烟测试
%
% 覆盖：
%   1. p3_apply_scheme_params 5 scheme 参数映射正确
%   2. p3_text_capacity 与 p3_apply_scheme_params 单一事实源一致
%   3. p3_downconv_bw 所有 scheme 返回正值
%   4. p3_channel_tap 所有 scheme 返回非空 h_tap
%
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm\modules\14_Streaming\src\Matlab\tests');
%   clear functions; clear all;
%   diary('test_p3_ui_smoke_results.txt');
%   run('test_p3_ui_smoke.m');
%   diary off;

%% 0. 路径注册
this_dir   = fileparts(mfilename('fullpath'));
root_dir   = fileparts(this_dir);
ui_dir     = fullfile(root_dir, 'ui');
common_dir = fullfile(root_dir, 'common');
addpath(ui_dir); addpath(common_dir);

pass = 0; fail = 0;
fprintf('========== P3 UI Step 2 冒烟测试 ==========\n');

sys = sys_params_default();
schemes = {'SC-FDE','OFDM','SC-TDE','DSSS','FH-MFSK'};

%% 1. p3_apply_scheme_params 参数映射
for k = 1:length(schemes)
    sch = schemes{k};
    ui_vals = default_ui_vals(sch);
    try
        [N_info, sys_out] = p3_apply_scheme_params(sch, sys, ui_vals);
        assert(N_info > 0, '%s: N_info <= 0', sch);
        assert(isstruct(sys_out), '%s: sys_out not struct', sch);
        fprintf('[PASS] %s N_info=%d\n', sch, N_info); pass = pass + 1;
    catch ME
        fprintf('[FAIL] %s apply_scheme_params: %s\n', sch, ME.message); fail = fail + 1;
    end
end

%% 2. 文本容量单一事实源一致性
for k = 1:length(schemes)
    sch = schemes{k};
    ui_vals = default_ui_vals(sch);
    try
        [N_info, ~] = p3_apply_scheme_params(sch, sys, ui_vals);
        nb_params = floor(N_info / 8);
        nb_helper = p3_text_capacity(sch, sys);
        diff_nb = abs(nb_params - nb_helper);
        assert(diff_nb <= 1, '%s: params=%d helper=%d diff=%d', ...
            sch, nb_params, nb_helper, diff_nb);
        fprintf('[PASS] %s text_capacity params=%d helper=%d\n', ...
            sch, nb_params, nb_helper); pass = pass + 1;
    catch ME
        fprintf('[FAIL] %s text_capacity: %s\n', sch, ME.message); fail = fail + 1;
    end
end

%% 3. p3_downconv_bw 返回正值
for k = 1:length(schemes)
    sch = schemes{k};
    try
        bw = p3_downconv_bw(sch, sys);
        assert(bw > 0, '%s: bw = %g', sch, bw);
        fprintf('[PASS] %s bw=%.1f Hz\n', sch, bw); pass = pass + 1;
    catch ME
        fprintf('[FAIL] %s downconv_bw: %s\n', sch, ME.message); fail = fail + 1;
    end
end

%% 4. p3_channel_tap 非空
presets = {'AWGN (无多径)', '6径 标准水声', '3径 短时延'};
for k = 1:length(schemes)
    sch = schemes{k};
    for pi = 1:length(presets)
        preset = presets{pi};
        try
            [h_tap, label] = p3_channel_tap(sch, sys, preset);
            assert(~isempty(h_tap), '%s/%s: h_tap empty', sch, preset);
            assert(~isempty(label), '%s/%s: label empty', sch, preset);
            fprintf('[PASS] %s %s taps=%d\n', sch, preset, length(h_tap));
            pass = pass + 1;
        catch ME
            fprintf('[FAIL] %s %s channel_tap: %s\n', sch, preset, ME.message);
            fail = fail + 1;
        end
    end
end

%% 总结
fprintf('\n========== 冒烟测试结果 ==========\n');
fprintf('PASS: %d   FAIL: %d\n', pass, fail);
if fail > 0
    fprintf('[!!] 有失败项，请检查\n');
else
    fprintf('[OK] 全部通过\n');
end

end

% ---------- 局部辅助：UI 默认值 ----------
function v = default_ui_vals(sch)
    switch sch
        case 'SC-FDE', v = struct('blk_fft', 128, 'turbo_iter', 6, 'payload', 2048);
        case 'OFDM',   v = struct('blk_fft', 256, 'turbo_iter', 6, 'payload', 2048);
        case 'SC-TDE', v = struct('blk_fft', 128, 'turbo_iter', 6, 'payload', 2048);
        case 'DSSS',   v = struct('blk_fft', 128, 'turbo_iter', 6, 'payload', 2048);
        case 'OTFS',   v = struct('blk_fft', 128, 'turbo_iter', 6, 'payload', 2048);
        case 'FH-MFSK',v = struct('blk_fft', 128, 'turbo_iter', 6, 'payload', 2048);
        otherwise,     v = struct('blk_fft', 128, 'turbo_iter', 6, 'payload', 2048);
    end
end
