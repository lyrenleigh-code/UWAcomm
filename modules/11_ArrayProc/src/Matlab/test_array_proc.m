%% test_array_proc.m
% 功能：阵列接收预处理模块单元测试
% 版本：V1.0.0
% 运行方式：>> run('test_array_proc.m')

clc; close all;
fprintf('========================================\n');
fprintf('  阵列接收预处理模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

% 添加依赖模块路径
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, '08_Sync', 'src', 'Matlab'));

%% ==================== 一、阵列配置 ==================== %%
fprintf('--- 1. 阵列配置 ---\n\n');

%% 1.1 ULA配置
try
    cfg_ula = gen_array_config('ula', 8, [], 12000);
    assert(cfg_ula.M == 8, '阵元数应为8');
    assert(size(cfg_ula.positions, 1) == 8, '坐标矩阵行数应为8');
    assert(abs(cfg_ula.d - cfg_ula.lambda/2) < 1e-6, '默认间距应为半波长');

    fprintf('[通过] 1.1 ULA(8元) | 间距=%.4fm, λ=%.4fm\n', cfg_ula.d, cfg_ula.lambda);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 ULA | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.2 UCA配置
try
    cfg_uca = gen_array_config('uca', 6, 0.1, 12000);
    assert(cfg_uca.M == 6, '阵元数应为6');

    fprintf('[通过] 1.2 UCA(6元) | 半径=%.3fm\n', cfg_uca.d);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 UCA | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、多通道信道 ==================== %%
fprintf('\n--- 2. 多通道阵列信道 ---\n\n');

rng(10);
c_sound = 1500; v_platform = 2; fs = 48000; fc = 12000;
alpha_true = v_platform / c_sound;
[preamble, ~] = gen_lfm(fs, 0.02, 8000, 16000);
s_test = [preamble, randn(1,3000)+1j*randn(1,3000), preamble];

paths = struct('delays', [0, 1.5e-3, 4e-3], 'gains', [1, 0.4*exp(1j*0.6), 0.2*exp(1j*1.5)]);
cfg = gen_array_config('ula', 4, [], fc);
tv_off = struct('enable', false);

%% 2.1 阵列信道生成
try
    [R_array, ch_info] = gen_doppler_channel_array(s_test, fs, alpha_true, paths, 20, cfg, pi/6, tv_off);

    assert(size(R_array, 1) == 4, '应有4个通道');
    assert(size(R_array, 2) > length(s_test), '接收信号应含多径扩展');
    assert(length(ch_info.tau_array) == 4, '时延数组长度应为4');
    assert(ch_info.tau_array(1) == 0, '第1阵元时延应为0');

    fprintf('[通过] 2.1 阵列信道 | %d通道, θ=30°, 时延=[%s]μs\n', ...
            size(R_array,1), num2str(ch_info.tau_array*1e6, '%.1f '));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 阵列信道 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、波束形成 ==================== %%
fprintf('\n--- 3. 波束形成 ---\n\n');

%% 3.1 DAS波束形成
try
    [y_das, gain_das] = bf_das(R_array, ch_info.tau_array, fs);

    assert(~isempty(y_das), 'DAS输出不应为空');
    assert(length(y_das) == size(R_array, 2), '输出长度应与输入一致');

    fprintf('[通过] 3.1 DAS | 理论增益=%.1fdB, 输出长度=%d\n', gain_das, length(y_das));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 DAS | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 MVDR波束形成
try
    % 构建导向矢量（目标方向30°）
    look_dir = [sin(pi/6), cos(pi/6), 0];
    tau_steer = cfg.positions * look_dir.' / cfg.c;
    a_steer = exp(-1j * 2 * pi * fc * tau_steer);

    [y_mvdr, w_mvdr] = bf_mvdr(R_array, a_steer, 0.01);

    assert(~isempty(y_mvdr), 'MVDR输出不应为空');
    assert(length(w_mvdr) == cfg.M, '权重长度应为M');

    fprintf('[通过] 3.2 MVDR | 权重范数=%.3f\n', norm(w_mvdr));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 MVDR | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.3 时延标定
try
    [tau_est, tau_err] = bf_delay_calibration(R_array, preamble, fs, ch_info.tau_array);

    assert(length(tau_est) == cfg.M, '估计时延数应为M');
    max_err = max(abs(tau_err));

    fprintf('[通过] 3.3 时延标定 | 最大误差=%.2fμs\n', max_err*1e6);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.3 时延标定 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.4 波束方向图可视化
try
    plot_beampattern(cfg, [], 'DAS波束方向图');
    plot_beampattern(cfg, w_mvdr, 'MVDR波束方向图');

    fprintf('[通过] 3.4 波束方向图可视化\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.4 方向图 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、非均匀变采样 ==================== %%
fprintf('\n--- 4. 非均匀变采样重建 ---\n\n');

%% 4.1 采样率提升
try
    [y_hi, eff_fs] = bf_nonuniform_resample(R_array, ch_info.tau_array, fs);

    assert(eff_fs > fs, '等效采样率应高于原始');
    assert(length(y_hi) > size(R_array, 2), '重建信号应更长');

    fprintf('[通过] 4.1 非均匀重建 | 原始fs=%dHz, 等效fs=%dHz(%.1fx)\n', ...
            fs, round(eff_fs), eff_fs/fs);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 非均匀重建 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、模块10联合测试 ==================== %%
fprintf('\n--- 5. 与模块10多普勒联合测试 ---\n\n');

%% 5.1 DAS波束形成后多普勒估计精度
try
    % 单通道多普勒估计
    [~, alpha_single, ~] = doppler_coarse_compensate(R_array(1,:), preamble, fs, ...
        'est_method', 'caf', 'alpha_range', [-0.005, 0.005]);
    err_single = abs(alpha_single - alpha_true);

    % DAS后多普勒估计
    [~, alpha_das, ~] = doppler_coarse_compensate(y_das, preamble, fs, ...
        'est_method', 'caf', 'alpha_range', [-0.005, 0.005]);
    err_das = abs(alpha_das - alpha_true);

    fprintf('[通过] 5.1 DAS增强多普勒估计:\n');
    fprintf('    单通道: α误差=%.2e (速度误差=%.2fm/s)\n', err_single, err_single*c_sound);
    fprintf('    DAS后:  α误差=%.2e (速度误差=%.2fm/s)\n', err_das, err_das*c_sound);
    if err_das < err_single
        fprintf('    → DAS改善了%.1f%%\n', (1 - err_das/err_single)*100);
    end
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 联合多普勒 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 六、异常输入 ==================== %%
fprintf('\n--- 6. 异常输入 ---\n\n');

try
    caught = 0;
    try gen_array_config('unknown'); catch; caught=caught+1; end
    try bf_das([], [], 48000); catch; caught=caught+1; end
    try bf_mvdr([]); catch; caught=caught+1; end
    try bf_delay_calibration([], [], 48000); catch; caught=caught+1; end

    assert(caught == 4, '部分函数未对异常输入报错');

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
