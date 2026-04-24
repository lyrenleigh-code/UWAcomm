function test_p4_channel_smoke()
% TEST_P4_CHANNEL_SMOKE  P4 真实多普勒冒烟测试
%
% 覆盖：
%   1. p4_channel_tap 返回 paths 结构完整（delays 单位秒 + gains）
%   2. gen_doppler_channel 对 p4_channel_tap 的 paths 可用
%   3. constant 模式（tv.enable=false）α 全程恒定 = α_base
%   4. random_walk 模式 α(t) 非常量
%   5. linear_drift 模式 α(t) 严格单调递增
%
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm\modules\14_Streaming\src\Matlab\tests');
%   clear functions; clear all;
%   diary('test_p4_channel_smoke_results.txt');
%   run('test_p4_channel_smoke.m');
%   diary off;

%% 0. 路径注册
this_dir   = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
modules_root = fileparts(fileparts(streaming_root));
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(modules_root, '10_DopplerProc', 'src', 'Matlab'));

pass = 0; fail = 0;
fprintf('========== P4 真实多普勒冒烟测试 ==========\n');

sys = sys_params_default();

%% 1. p4_channel_tap 返回 paths
schemes = {'SC-FDE','OFDM','SC-TDE','DSSS','FH-MFSK'};
for k = 1:length(schemes)
    sch = schemes{k};
    try
        [h, paths, lbl] = p4_channel_tap(sch, sys, '6径 标准水声');
        assert(isfield(paths, 'delays'), '%s: paths.delays missing', sch);
        assert(isfield(paths, 'gains'), '%s: paths.gains missing', sch);
        assert(length(paths.delays) == length(paths.gains), ...
            '%s: delays/gains length mismatch', sch);
        assert(~isempty(h), '%s: h_tap empty', sch);
        assert(all(paths.delays >= 0), '%s: negative delay', sch);
        fprintf('[PASS] %s paths (%d 径, max_delay=%.2e s)\n', ...
            sch, length(paths.delays), max(paths.delays)); pass = pass + 1;
    catch ME
        fprintf('[FAIL] %s channel_tap: %s\n', sch, ME.message); fail = fail + 1;
    end
end

%% 2. gen_doppler_channel V1.1（传 fc）对 p4 paths 可用
try
    s = randn(1, 8192) + 1j*randn(1, 8192);
    [~, paths] = p4_channel_tap('SC-FDE', sys, '6径 标准水声');
    tv = struct('enable', true, 'model', 'random_walk', ...
                'drift_rate', 1e-7, 'jitter_std', 2e-8);
    [r, info] = gen_doppler_channel(s, sys.fs, 1e-5, paths, 20, tv, sys.fc);
    assert(~isempty(r), 'gen_doppler_channel returned empty');
    assert(isfield(info, 'alpha_true'), 'channel_info.alpha_true missing');
    assert(length(info.alpha_true) == length(s), 'alpha_true length mismatch');
    assert(info.fc == sys.fc, 'channel_info.fc 未记录');
    fprintf('[PASS] gen_doppler_channel V1.1 (fc=%d) α_mean=%.3e α_std=%.3e\n', ...
        sys.fc, mean(info.alpha_true), std(info.alpha_true)); pass = pass + 1;
catch ME
    fprintf('[FAIL] gen_doppler_channel V1.1: %s\n', ME.message); fail = fail + 1;
end

%% 3. constant 模式退化 = α_base 全程
try
    s = randn(1, 4096);
    [~, paths] = p4_channel_tap('SC-FDE', sys, '6径 标准水声');
    tv = struct('enable', false, 'model', 'constant', 'drift_rate', 0, 'jitter_std', 0);
    [~, info] = gen_doppler_channel(s, sys.fs, 1e-5, paths, Inf, tv, sys.fc);
    assert(all(info.alpha_true == 1e-5), 'constant α not constant');
    assert(info.noise_var < 1e-10, 'snr_db=Inf should give zero noise');
    fprintf('[PASS] constant 模式 α 全程 = %.3e (SNR=Inf 噪声=%.3e)\n', ...
        info.alpha_true(1), info.noise_var); pass = pass + 1;
catch ME
    fprintf('[FAIL] constant 退化: %s\n', ME.message); fail = fail + 1;
end

%% 4. random_walk 模式 α(t) 非常量
try
    s = randn(1, 8192);
    [~, paths] = p4_channel_tap('SC-FDE', sys, '6径 标准水声');
    tv = struct('enable', true, 'model', 'random_walk', ...
                'drift_rate', 0, 'jitter_std', 2e-8);
    [~, info] = gen_doppler_channel(s, sys.fs, 1e-5, paths, Inf, tv, sys.fc);
    assert(std(info.alpha_true) > 0, 'random_walk α is constant?');
    % α_base 均值检查（1e-5 ± 合理范围）
    m = mean(info.alpha_true);
    assert(abs(m - 1e-5) < 1e-5, sprintf('α mean drift: %.3e vs base 1e-5', m));
    fprintf('[PASS] random_walk α_std=%.3e (non-zero)\n', std(info.alpha_true));
    pass = pass + 1;
catch ME
    fprintf('[FAIL] random_walk: %s\n', ME.message); fail = fail + 1;
end

%% 5. linear_drift 模式 α(t) 单调递增
try
    s = randn(1, 4096);
    [~, paths] = p4_channel_tap('SC-FDE', sys, '6径 标准水声');
    tv = struct('enable', true, 'model', 'linear_drift', ...
                'drift_rate', 1e-5, 'jitter_std', 0);  % 1e-5 /s drift
    [~, info] = gen_doppler_channel(s, sys.fs, 1e-5, paths, Inf, tv, sys.fc);
    diff_alpha = diff(info.alpha_true);
    assert(all(diff_alpha >= -1e-12), 'linear_drift not monotonic increasing');
    assert(info.alpha_true(end) > info.alpha_true(1), 'linear_drift end > start');
    fprintf('[PASS] linear_drift α[1]=%.3e α[end]=%.3e\n', ...
        info.alpha_true(1), info.alpha_true(end)); pass = pass + 1;
catch ME
    fprintf('[FAIL] linear_drift: %s\n', ME.message); fail = fail + 1;
end

%% 6. 相位公式验证：V1.1 fc 路径 vs V1.0 α·fs 路径应不同
try
    s = ones(1, 1024) + 1j*zeros(1, 1024);  % DC 基带信号便于观察相位
    paths0 = struct('delays', 0, 'gains', 1);  % 无多径隔离相位项
    tv0 = struct('enable', false);
    alpha = 1e-3;

    [r_new, ~] = gen_doppler_channel(s, sys.fs, alpha, paths0, Inf, tv0, sys.fc);
    warning('off','gen_doppler_channel:NoFc');
    [r_old, ~] = gen_doppler_channel(s, sys.fs, alpha, paths0, Inf, tv0);  % 无 fc
    warning('on','gen_doppler_channel:NoFc');

    % 取尾段相位斜率
    n_end = min(length(r_new), 500);
    ph_new = unwrap(angle(r_new(1:n_end)));
    ph_old = unwrap(angle(r_old(1:n_end)));
    f_new = (ph_new(end) - ph_new(1)) / (n_end/sys.fs) / (2*pi);  % Hz
    f_old = (ph_old(end) - ph_old(1)) / (n_end/sys.fs) / (2*pi);
    expected_new = sys.fc * alpha;   % 物理正确 12 Hz
    expected_old = sys.fs * alpha;   % V1.0 旧公式 48 Hz
    err_new = abs(f_new - expected_new);
    err_old = abs(f_old - expected_old);
    assert(err_new < 1.0, sprintf('V1.1 相位频率 %.2f Hz ≠ fc·α=%.2f', f_new, expected_new));
    assert(err_old < 2.0, sprintf('V1.0 相位频率 %.2f Hz ≠ fs·α=%.2f', f_old, expected_old));
    fprintf('[PASS] 相位修复：V1.1=%.2fHz(=fc·α=%.2f) vs V1.0=%.2fHz(=fs·α=%.2f)\n', ...
        f_new, expected_new, f_old, expected_old);
    pass = pass + 1;
catch ME
    fprintf('[FAIL] 相位公式: %s\n', ME.message); fail = fail + 1;
end

%% 总结
fprintf('\n========== P4 冒烟测试结果 ==========\n');
fprintf('PASS: %d   FAIL: %d\n', pass, fail);
if fail > 0
    fprintf('[!!] 有失败项，请检查\n');
else
    fprintf('[OK] 全部通过\n');
end

end
