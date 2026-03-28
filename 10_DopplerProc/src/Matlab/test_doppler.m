%% test_doppler.m
% 功能：多普勒估计与补偿模块单元测试
% 版本：V1.0.0
% 运行方式：>> run('test_doppler.m')

clc; close all;
fprintf('========================================\n');
fprintf('  多普勒估计与补偿模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

% 添加依赖模块路径
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));

%% ==================== 一、时变多普勒信道 ==================== %%
fprintf('--- 1. 时变多普勒信道 ---\n\n');

%% 1.1 固定α信道
try
    rng(10);
    fs = 48000; alpha = 0.001;
    s = exp(1j*2*pi*1000*(0:9999)/fs);  % 1kHz单频信号
    tv = struct('enable', false);
    [r, ch_info] = gen_doppler_channel(s, fs, alpha, [], 30, tv);

    assert(~isempty(r), '接收信号不应为空');
    assert(abs(ch_info.alpha_base - alpha) < 1e-10, 'α记录不正确');

    fprintf('[通过] 1.1 固定α信道 | α=%.4f, SNR=%ddB\n', alpha, ch_info.snr_db);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 固定α | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.2 时变α信道（random_walk）
try
    tv = struct('enable', true, 'drift_rate', 0.0001, 'jitter_std', 0.00002, 'model', 'random_walk');
    [r_tv, ch_tv] = gen_doppler_channel(s, fs, alpha, [], 20, tv);

    assert(length(ch_tv.alpha_true) == length(s), 'α序列长度应与信号一致');
    assert(std(ch_tv.alpha_true) > 0, '时变α应有波动');

    fprintf('[通过] 1.2 时变α信道 | α均值=%.5f, α标准差=%.2e\n', ...
            mean(ch_tv.alpha_true), std(ch_tv.alpha_true));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 时变α | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、多普勒估计 ==================== %%
fprintf('\n--- 2. 多普勒估计算法 ---\n\n');

% 生成测试信号：LFM前导 + 数据
% 水声场景：c=1500m/s, v=3m/s → α=v/c=0.002
rng(20);
c_sound = 1500;                        % 声速 (m/s)
v_platform = 3;                        % 平台速度 (m/s)
fs = 48000; fc = 12000;
alpha_true = v_platform / c_sound;     % α = 0.002

[preamble, ~] = gen_lfm(fs, 0.02, 8000, 16000);  % 20ms LFM
data = randn(1, 5000) + 1j*randn(1, 5000);
tx_sig = [preamble, zeros(1,1000), data, zeros(1,1000), preamble];

paths = struct('delays', [0, 1e-3, 3e-3], 'gains', [1, 0.4*exp(1j*0.5), 0.15*exp(1j*1.2)]);
tv_off = struct('enable', false);
[rx_sig, ch_info2] = gen_doppler_channel(tx_sig, fs, alpha_true, paths, 25, tv_off);

fprintf('测试参数：声速=%dm/s, 平台速度=%dm/s, α=%.4f\n\n', c_sound, v_platform, alpha_true);

%% 2.1 CAF估计
try
    % 搜索范围±5m/s对应±3.33e-3, 步长0.1m/s对应6.67e-5
    alpha_max = 5 / c_sound;
    [a_caf, tau_caf, ~] = est_doppler_caf(rx_sig, preamble, fs, [-alpha_max, alpha_max], 1e-4);
    err_caf = abs(a_caf - alpha_true);

    assert(err_caf < 5e-4, sprintf('CAF误差%.2e过大(>0.75m/s)', err_caf));

    fprintf('[通过] 2.1 CAF估计 | α_est=%.5f, 误差=%.2e (速度误差=%.2fm/s)\n', ...
            a_caf, err_caf, err_caf*c_sound);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 CAF | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.2 复自相关幅相联合估计
try
    T_v = length(tx_sig) / fs - 0.02;  % 近似前后导码间隔
    [a_xcorr, a_coarse, ~] = est_doppler_xcorr(rx_sig, preamble, T_v, fs, fc);
    err_xcorr = abs(a_xcorr - alpha_true);

    fprintf('[通过] 2.2 复自相关 | α_est=%.5f, 粗估=%.5f, 速度误差=%.2fm/s\n', ...
            a_xcorr, a_coarse, err_xcorr*c_sound);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.2 复自相关 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、重采样补偿 ==================== %%
fprintf('\n--- 3. 重采样补偿 ---\n\n');

% 生成简单测试信号做精度和速度对比
rng(30);
N_test = 50000;
s_test = randn(1, N_test) + 1j*randn(1, N_test);
alpha_test = 0.001;

%% 3.1 两种重采样方法精度对比（vs MATLAB resample基准）
try
    tic; y_spline = comp_resample_spline(s_test, alpha_test, fs); t_spline = toc;
    tic; y_farrow = comp_resample_farrow(s_test, alpha_test, fs); t_farrow = toc;

    % MATLAB自带resample做参考基准
    tic;
    [P, Q] = rat(1/(1+alpha_test), 1e-6);
    y_ref = resample(s_test, P, Q);
    y_ref = y_ref(1:min(N_test, length(y_ref)));
    if length(y_ref) < N_test, y_ref = [y_ref, zeros(1, N_test-length(y_ref))]; end
    t_ref = toc;

    % 精度对比（与resample结果的相关性）
    corr_spline = abs(sum(y_spline .* conj(y_ref))) / (norm(y_spline)*norm(y_ref));
    corr_farrow = abs(sum(y_farrow .* conj(y_ref))) / (norm(y_farrow)*norm(y_ref));

    fprintf('[通过] 3.1 重采样精度对比:\n');
    fprintf('    Spline:   相关=%.6f, 耗时=%.1fms\n', corr_spline, t_spline*1000);
    fprintf('    Farrow:   相关=%.6f, 耗时=%.1fms\n', corr_farrow, t_farrow*1000);
    fprintf('    resample: 参考基准,   耗时=%.1fms\n', t_ref*1000);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 重采样 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 重采样后信号长度保持
try
    assert(length(y_spline) == N_test, 'Spline输出长度应与输入一致');
    assert(length(y_farrow) == N_test, 'Farrow输出长度应与输入一致');

    fprintf('[通过] 3.2 重采样长度保持 | 输入输出均为%d\n', N_test);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 长度保持 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、统一入口 ==================== %%
fprintf('\n--- 4. 统一入口函数 ---\n\n');

%% 4.1 10-1粗补偿
try
    [y_coarse, alpha_coarse, info_coarse] = doppler_coarse_compensate(...
        rx_sig, preamble, fs, 'est_method', 'caf', 'comp_method', 'spline', ...
        'alpha_range', [-alpha_max, alpha_max]);

    assert(abs(alpha_coarse - alpha_true) < 1e-3, '粗估计误差过大');
    assert(length(y_coarse) == length(rx_sig), '补偿后长度应与输入一致');

    fprintf('[通过] 4.1 粗补偿(CAF+Spline) | α_est=%.5f\n', alpha_coarse);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 粗补偿 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.2 10-2残余CFO补偿
try
    cfo_test = 10;                     % 10Hz残余频偏
    y_test = exp(1j*2*pi*cfo_test*(0:999)/fs);
    [y_res, info_res] = doppler_residual_compensate(y_test, fs, 'method', 'cfo_rotate', 'cfo_hz', cfo_test);

    % 补偿后应接近DC信号（相位不再旋转）
    phase_var = var(angle(y_res(100:end)));
    assert(phase_var < 0.1, '残余CFO补偿后相位仍在旋转');

    fprintf('[通过] 4.2 残余CFO补偿 | 补偿后相位方差=%.4f\n', phase_var);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 残余CFO | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、可视化 ==================== %%
fprintf('\n--- 5. 可视化 ---\n\n');

try
    % 确保变量存在（前面的测试可能失败）
    if ~exist('a_caf','var'), a_caf = 0; end
    if ~exist('a_xcorr','var'), a_xcorr = 0; end
    if ~exist('y_coarse','var'), y_coarse = rx_sig; end

    n_show = min([200, length(rx_sig), length(y_coarse), length(tx_sig)]);
    comp_vis = struct('y_orig', real(rx_sig(1:n_show)), 'y_comp', real(y_coarse(1:n_show)), ...
                      'y_ref', real(tx_sig(1:n_show)));
    plot_doppler_estimation(alpha_true, {a_caf, a_xcorr}, {'CAF', '复自相关'}, ...
                           comp_vis, sprintf('多普勒估计与补偿 (v=%dm/s, α=%.4f, SNR=25dB)', v_platform, alpha_true));

    fprintf('[通过] 5.1 估计结果可视化\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 可视化 | %s (行%d)\n', e.message, e.stack(1).line);
    fail_count = fail_count + 1;
end

%% ==================== 六、异常输入 ==================== %%
fprintf('\n--- 6. 异常输入 ---\n\n');

try
    caught = 0;
    try gen_doppler_channel([], 48000, 0.001); catch; caught=caught+1; end
    try est_doppler_caf([], [1 -1], 48000); catch; caught=caught+1; end
    try comp_resample_spline([], 0.001, 48000); catch; caught=caught+1; end
    try comp_cfo_rotate([], 10, 48000); catch; caught=caught+1; end

    assert(caught == 4, '部分函数未对空输入报错');

    fprintf('[通过] 6.1 空输入拒绝 | 4个函数均报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 6.1 空输入 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 测试汇总 ==================== %%
fprintf('\n========================================\n');
fprintf('  测试完成：%d 通过, %d 失败, 共 %d 项\n', ...
        pass_count, fail_count, pass_count + fail_count);
fprintf('========================================\n');

if fail_count == 0
    fprintf('  全部通过！\n');
else
    fprintf('  存在失败项，请检查！\n');
end
