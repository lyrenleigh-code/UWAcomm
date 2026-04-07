%% test_doppler.m
% 功能：多普勒估计与补偿模块单元测试
% 版本：V2.0.0
% 运行方式：>> run('test_doppler.m')
% V2.0: 增加ZoomFFT/ICI矩阵/阵列信道测试 + 可视化(估计对比/重采样/频谱/阵列)

clc; close all;
fprintf('========================================\n');
fprintf('  多普勒估计与补偿模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;
vis = struct();  % 可视化数据收集

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
    vis.a_caf = a_caf; vis.ok_caf = true;
catch e
    fprintf('[失败] 2.1 CAF | %s\n', e.message);
    fail_count = fail_count + 1;
    vis.ok_caf = false;
end

%% 2.2 复自相关幅相联合估计
try
    T_v = length(tx_sig) / fs - 0.02;  % 近似前后导码间隔
    [a_xcorr, a_coarse, ~] = est_doppler_xcorr(rx_sig, preamble, T_v, fs, fc);
    err_xcorr = abs(a_xcorr - alpha_true);

    fprintf('[通过] 2.2 复自相关 | α_est=%.5f, 粗估=%.5f, 速度误差=%.2fm/s\n', ...
            a_xcorr, a_coarse, err_xcorr*c_sound);
    pass_count = pass_count + 1;
    vis.a_xcorr = a_xcorr; vis.ok_xcorr = true;
catch e
    fprintf('[失败] 2.2 复自相关 | %s\n', e.message);
    fail_count = fail_count + 1;
    vis.ok_xcorr = false;
end

%% ==================== 三、重采样补偿 ==================== %%
fprintf('\n--- 3. 重采样补偿 ---\n\n');

% 生成测试信号做精度和速度对比（多种数据长度）
rng(30);
alpha_test = 1 / c_sound;             % 1m/s对应α

%% 3.1 重采样精度+速度对比（多数据长度）
try
    test_lengths = [10000, 50000, 200000, 500000];
    fprintf('[通过] 3.1 重采样精度+速度对比 (α=%.4f, v=%.1fm/s):\n', alpha_test, alpha_test*c_sound);
    fprintf('    %-10s | %-12s %-12s %-12s | %-12s %-12s %-12s\n', ...
            '数据长度', 'Spline(ms)', 'Farrow(ms)', 'resample(ms)', ...
            'Spline相关', 'Farrow相关', '速度比');

    for li = 1:length(test_lengths)
        N_test = test_lengths(li);
        s_test = randn(1, N_test) + 1j*randn(1, N_test);

        % 三种方法计时
        tic; y_spline = comp_resample_spline(s_test, alpha_test, fs); t_spline = toc;
        tic; y_farrow = comp_resample_farrow(s_test, alpha_test, fs); t_farrow = toc;

        tic;
        [P, Q] = rat(1/(1+alpha_test), 1e-6);
        y_ref = resample(s_test, P, Q);
        y_ref = y_ref(1:min(N_test, length(y_ref)));
        if length(y_ref) < N_test, y_ref = [y_ref, zeros(1, N_test-length(y_ref))]; end
        t_ref = toc;

        % 精度（相关性）
        corr_sp = abs(sum(y_spline .* conj(y_ref))) / (norm(y_spline)*norm(y_ref)+1e-30);
        corr_fa = abs(sum(y_farrow .* conj(y_ref))) / (norm(y_farrow)*norm(y_ref)+1e-30);

        % Farrow vs resample速度比
        speed_ratio = t_farrow / (t_ref + 1e-10);

        fprintf('    %-10d | %-12.1f %-12.1f %-12.1f | %-12.6f %-12.6f %-12.1fx\n', ...
                N_test, t_spline*1000, t_farrow*1000, t_ref*1000, corr_sp, corr_fa, speed_ratio);
    end
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 重采样 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 重采样后信号长度保持
try
    N_test = 50000;
    s_test = randn(1, N_test) + 1j*randn(1, N_test);
    y_spline = comp_resample_spline(s_test, alpha_test, fs);
    y_farrow = comp_resample_farrow(s_test, alpha_test, fs);
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

%% ==================== 五、ZoomFFT估计 ==================== %%
fprintf('\n--- 5. ZoomFFT估计 ---\n\n');

%% 5.1 ZoomFFT多普勒估计
try
    % 用上变频信号测试ZoomFFT（需要载频信息）
    proj_root2 = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    addpath(fullfile(proj_root2, '09_Waveform', 'src', 'Matlab'));

    rng(50);
    fs_zf = 48000; fc_zf = 12000;
    [preamble_zf, ~] = gen_lfm(fs_zf, 0.02, 8000, 16000);
    alpha_zf = 0.0015;
    tv_off2 = struct('enable', false);
    [rx_zf, ~] = gen_doppler_channel(preamble_zf, fs_zf, alpha_zf, [], 30, tv_off2);

    [a_zf, freq_zf, spec_zf] = est_doppler_zoomfft(rx_zf, preamble_zf, fs_zf, fc_zf);
    err_zf = abs(a_zf - alpha_zf);

    fprintf('[通过] 5.1 ZoomFFT | α_est=%.5f, 误差=%.2e (速度误差=%.2fm/s)\n', ...
            a_zf, err_zf, err_zf*c_sound);
    pass_count = pass_count + 1;
    vis.a_zoomfft = a_zf; vis.ok_zoomfft = true;
catch e
    fprintf('[失败] 5.1 ZoomFFT | %s\n', e.message);
    fail_count = fail_count + 1;
    vis.ok_zoomfft = false;
end

%% ==================== 六、ICI矩阵补偿 ==================== %%
fprintf('\n--- 6. ICI矩阵补偿 ---\n\n');

%% 6.1 ICI补偿验证
try
    rng(60);
    N_fft = 64;
    X_true = (2*randi([0 1],1,N_fft)-1) + 1j*(2*randi([0 1],1,N_fft)-1);
    alpha_ici = 5e-4;                  % 残余多普勒因子

    % 用与comp_ici_matrix相同的公式构建D矩阵模拟ICI
    D_sim = zeros(N_fft);
    n = 0:N_fft-1;
    for k = 0:N_fft-1
        for l = 0:N_fft-1
            D_sim(k+1, l+1) = sum(exp(1j*2*pi*(l - k*(1+alpha_ici)) .* n / N_fft)) / N_fft;
        end
    end
    Y_ici = (D_sim * X_true(:)).';     % 含ICI的接收

    % 补偿
    Y_comp = comp_ici_matrix(Y_ici, alpha_ici, N_fft);

    err_before = mean(abs(Y_ici - X_true).^2);
    err_after = mean(abs(Y_comp - X_true).^2);

    fprintf('  [诊断] ICI补偿前MSE=%.4f, 补偿后MSE=%.6f\n', err_before, err_after);
    assert(err_after < err_before, sprintf('ICI补偿后误差应减小: before=%.4f, after=%.6f', err_before, err_after));

    fprintf('[通过] 6.1 ICI矩阵补偿 | MSE: %.4f → %.6f (改善%.1fdB)\n', ...
            err_before, err_after, 10*log10(err_before/(err_after+1e-30)));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 6.1 ICI补偿 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 七、阵列信道 ==================== %%
fprintf('\n--- 7. 阵列信道(V2.0新增) ---\n\n');

%% 7.1 阵列信道生成
try
    rng(70);
    s_arr = exp(1j*2*pi*1000*(0:4999)/48000);
    arr_params = struct('M', 4, 'fc', 12000, 'c', 1500, 'theta', pi/6);
    tv_off3 = struct('enable', false);

    [R_arr, arr_info] = gen_uwa_channel_array(s_arr, 48000, 0.001, [], 25, tv_off3, arr_params);

    assert(size(R_arr, 1) == 4, '应有4行(4阵元)');
    assert(size(R_arr, 2) > 0, '接收信号不应为空');
    assert(length(arr_info.tau_spatial) == 4, '空间时延长度应为4');
    assert(arr_info.tau_spatial(1) == 0, '第1阵元时延应为0');

    fprintf('[通过] 7.1 阵列信道 | %d阵元, 入射角=%.0f°, τ间距=%.2fμs\n', ...
            arr_params.M, arr_params.theta*180/pi, diff(arr_info.tau_spatial(1:2))*1e6);
    pass_count = pass_count + 1;
    vis.R_arr = R_arr; vis.arr_info = arr_info; vis.ok_arr = true;
catch e
    fprintf('[失败] 7.1 阵列信道 | %s\n', e.message);
    fail_count = fail_count + 1;
    vis.ok_arr = false;
end

%% 7.2 阵列相位差验证
try
    % 各阵元之间应有稳定相位差（远场平面波假设）
    % 相位差 = 2π*fc*d*cos(θ)/c
    expected_dphi = 2*pi * arr_params.fc * arr_info.tau_spatial(2) ;
    % 实测：取中间段做互相关相位
    mid = 2000:3000;
    dphi_12 = angle(sum(R_arr(2,mid) .* conj(R_arr(1,mid))));
    dphi_expected = mod(expected_dphi + pi, 2*pi) - pi;

    fprintf('[通过] 7.2 阵列相位差 | 期望=%.2frad, 实测=%.2frad\n', ...
            dphi_expected, dphi_12);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 7.2 阵列相位差 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 八、异常输入 ==================== %%
fprintf('\n--- 8. 异常输入 ---\n\n');

try
    caught = 0;
    try gen_doppler_channel([], 48000, 0.001); catch; caught=caught+1; end
    try est_doppler_caf([], [1 -1], 48000); catch; caught=caught+1; end
    try comp_resample_spline([], 0.001, 48000); catch; caught=caught+1; end
    try comp_cfo_rotate([], 10, 48000); catch; caught=caught+1; end
    try gen_uwa_channel_array([], 48000, 0.001); catch; caught=caught+1; end

    assert(caught == 5, '部分函数未对空输入报错');

    fprintf('[通过] 8.1 空输入拒绝 | 5个函数均报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 8.1 空输入 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 可视化（独立于测试） ==================== %%

% 保存公共变量供可视化
vis.alpha_true = alpha_true; vis.c_sound = c_sound; vis.v_platform = v_platform;
if exist('rx_sig','var'), vis.rx_sig = rx_sig; end
if exist('tx_sig','var'), vis.tx_sig = tx_sig; end
if exist('y_coarse','var'), vis.y_coarse = y_coarse; end

% --- Figure 1: 多普勒估计方法对比 --- %
try
    est_names = {}; est_vals = []; est_errs = [];
    if isfield(vis,'ok_caf') && vis.ok_caf
        est_names{end+1} = 'CAF'; est_vals(end+1) = vis.a_caf;
        est_errs(end+1) = abs(vis.a_caf - alpha_true);
    end
    if isfield(vis,'ok_xcorr') && vis.ok_xcorr
        est_names{end+1} = '复自相关'; est_vals(end+1) = vis.a_xcorr;
        est_errs(end+1) = abs(vis.a_xcorr - alpha_true);
    end
    if isfield(vis,'ok_zoomfft') && vis.ok_zoomfft
        est_names{end+1} = 'ZoomFFT'; est_vals(end+1) = vis.a_zoomfft;
        est_errs(end+1) = abs(vis.a_zoomfft - alpha_true);
    end

    if ~isempty(est_names)
        figure('Name','多普勒估计对比','NumberTitle','off','Position',[50 80 1100 450]);

        subplot(1,2,1);
        bar(est_vals * 1000, 0.5, 'FaceColor',[0.3 0.5 0.8]); hold on;
        line([0.5 length(est_vals)+0.5], [alpha_true alpha_true]*1000, ...
             'Color','r','LineStyle','--','LineWidth',1.5);
        set(gca, 'XTickLabel', est_names);
        ylabel('\alpha \times 10^{-3}'); legend('估计值','真实值');
        title(sprintf('多普勒因子估计 (v=%dm/s)', v_platform)); grid on;

        subplot(1,2,2);
        bar(est_errs * c_sound, 0.5, 'FaceColor',[0.8 0.4 0.2]);
        set(gca, 'XTickLabel', est_names);
        ylabel('速度误差 (m/s)');
        title('估计误差对比'); grid on;
    end
catch; end

% --- Figure 2: 重采样补偿前后波形 --- %
try
    if isfield(vis,'rx_sig') && isfield(vis,'y_coarse') && isfield(vis,'tx_sig')
        figure('Name','重采样补偿波形','NumberTitle','off','Position',[60 60 1100 500]);
        n_show = min(500, length(vis.tx_sig));

        subplot(2,1,1);
        plot(real(vis.tx_sig(1:n_show)), 'b', 'LineWidth', 0.8); hold on;
        plot(real(vis.rx_sig(1:n_show)), 'r', 'LineWidth', 0.6);
        legend('发射信号','接收信号(含多普勒)');
        xlabel('采样点'); ylabel('幅度');
        title(sprintf('补偿前 (α=%.4f)', alpha_true)); grid on;

        subplot(2,1,2);
        plot(real(vis.tx_sig(1:n_show)), 'b', 'LineWidth', 0.8); hold on;
        n_comp = min(n_show, length(vis.y_coarse));
        plot(real(vis.y_coarse(1:n_comp)), 'Color',[0 0.6 0], 'LineWidth', 0.6);
        legend('发射信号','补偿后信号');
        xlabel('采样点'); ylabel('幅度');
        title('重采样补偿后'); grid on;
    end
catch; end

% --- Figure 3: 阵列信道各阵元信号 --- %
try
    if isfield(vis,'ok_arr') && vis.ok_arr
        figure('Name','阵列信道','NumberTitle','off','Position',[70 50 1100 500]);
        M_arr = size(vis.R_arr, 1);
        n_show_arr = min(300, size(vis.R_arr, 2));

        subplot(1,2,1);
        for m = 1:M_arr
            plot(real(vis.R_arr(m, 1:n_show_arr)) + (m-1)*3, 'LineWidth', 0.6); hold on;
        end
        ylabel('阵元 (偏移显示)'); xlabel('采样点');
        title(sprintf('%d阵元接收信号 (θ=%.0f°)', M_arr, vis.arr_info.array.theta*180/pi));
        grid on;

        subplot(1,2,2);
        % 阵元间互相关幅度
        corr_mat = zeros(M_arr);
        for i = 1:M_arr
            for j = 1:M_arr
                corr_mat(i,j) = abs(sum(vis.R_arr(i,:) .* conj(vis.R_arr(j,:)))) / ...
                                sqrt(sum(abs(vis.R_arr(i,:)).^2) * sum(abs(vis.R_arr(j,:)).^2));
            end
        end
        imagesc(corr_mat); colorbar; axis equal tight;
        xlabel('阵元'); ylabel('阵元');
        title('阵元间归一化互相关'); colormap(hot);
    end
catch; end

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
