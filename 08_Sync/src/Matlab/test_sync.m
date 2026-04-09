%% test_sync.m
% 功能：同步+帧组装模块单元测试
% 版本：V3.0.0
% 运行方式：>> run('test_sync.m')
% V2.0: 多普勒补偿同步测试、相位跟踪(PLL/DFPT/Kalman)测试
% V3.0: 多普勒同步误差分析(双HFM消偏/多普勒估计精度/PLL载波同步)

clc; close all;
fprintf('========================================\n');
fprintf('  同步+帧组装模块 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

% 添加依赖模块路径
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));

%% ==================== 一、同步序列生成 ==================== %%
fprintf('--- 1. 同步序列生成 ---\n\n');

%% 1.1 LFM信号
try
    fs = 48000; dur = 0.01;
    [sig, t] = gen_lfm(fs, dur, 8000, 16000);
    assert(length(sig) == round(fs*dur), 'LFM长度不正确');
    assert(isreal(sig), 'LFM应为实信号');

    fprintf('[通过] 1.1 LFM | 长度=%d, 带宽=8kHz\n', length(sig));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 LFM | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.2 HFM信号
try
    [sig, t] = gen_hfm(fs, dur, 8000, 16000);
    assert(length(sig) == round(fs*dur), 'HFM长度不正确');

    fprintf('[通过] 1.2 HFM | 长度=%d, Doppler不变性\n', length(sig));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 HFM | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.3 Zadoff-Chu序列
try
    [seq, ~] = gen_zc_seq(127, 3);
    assert(length(seq) == 127, 'ZC长度不正确');
    assert(all(abs(abs(seq) - 1) < 1e-10), 'ZC应为恒模');

    % 周期自相关检验
    acorr = ifft(fft(seq) .* conj(fft(seq)));
    peak = abs(acorr(1));
    sidelobe = max(abs(acorr(2:end)));
    assert(sidelobe / peak < 0.01, 'ZC自相关旁瓣过高');

    fprintf('[通过] 1.3 ZC(127,3) | 恒模, 旁瓣/峰值=%.4f\n', sidelobe/peak);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.3 ZC | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.4 Barker码
try
    [code13, ~] = gen_barker(13);
    assert(length(code13) == 13, 'Barker-13长度不正确');

    % 非周期自相关旁瓣 <= 1
    acorr = xcorr(code13);
    peak = max(acorr);
    sidelobes = acorr; sidelobes(length(code13)) = 0;
    assert(max(abs(sidelobes)) <= 1 + 1e-6, 'Barker旁瓣应<=1');

    fprintf('[通过] 1.4 Barker(13) | 旁瓣最大=%.4f\n', max(abs(sidelobes)));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.4 Barker | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 二、粗同步检测 ==================== %%
fprintf('\n--- 2. 粗同步检测 ---\n\n');

%% 2.1 无噪声LFM同步
try
    fs = 48000;
    [preamble, ~] = gen_lfm(fs, 0.01, 8000, 16000);
    offset = 500;
    received = [zeros(1, offset), preamble, randn(1, 1000)*0.01];

    [pos, peak, ~] = sync_detect(received, preamble, 0.5);
    assert(abs(pos - offset - 1) <= 1, '同步位置偏差过大');
    assert(peak > 0.9, '无噪声峰值应接近1');

    fprintf('[通过] 2.1 LFM无噪声同步 | 偏移=%d, 检测=%d, 峰值=%.3f\n', offset, pos, peak);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 LFM同步 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.2 有噪声ZC同步
try
    rng(10);
    [preamble, ~] = gen_zc_seq(255, 7);
    offset = 300;
    noise = 0.5 * (randn(1, 1500) + 1j*randn(1, 1500));
    received = noise;
    received(offset+1 : offset+255) = received(offset+1 : offset+255) + preamble;

    [pos, peak, ~] = sync_detect(received, preamble, 0.3);
    assert(abs(pos - offset - 1) <= 2, '噪声下同步偏差过大');

    fprintf('[通过] 2.2 ZC有噪声同步 | SNR≈6dB, 偏移=%d, 检测=%d, 峰值=%.3f\n', ...
            offset, pos, peak);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.2 ZC有噪声 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 三、CFO估计 ==================== %%
fprintf('\n--- 3. CFO粗估计 ---\n\n');

%% 3.1 互相关法CFO估计
try
    rng(20);
    fs = 48000;
    [preamble, ~] = gen_zc_seq(256, 1);
    true_cfo = 50;                     % 50Hz频偏
    t = (0:255) / fs;
    rx = preamble .* exp(1j*2*pi*true_cfo*t);

    % 诊断：确认调用的是哪个cfo_estimate
    fprintf('  [诊断] cfo_estimate路径: %s\n', which('cfo_estimate'));

    [cfo_est, cfo_norm] = cfo_estimate(rx, preamble, fs, 'correlate');
    cfo_err = abs(cfo_est - true_cfo);
    fprintf('  [诊断] 3.1 真实=%.4fHz, 估计=%.4fHz, 归一化=%.6f, 误差=%.4fHz\n', ...
            true_cfo, cfo_est, cfo_norm, cfo_err);

    assert(cfo_err < 20, sprintf('CFO估计误差过大: 估计=%.4fHz, 真实=%dHz, 误差=%.4fHz', ...
           cfo_est, true_cfo, cfo_err));

    fprintf('[通过] 3.1 互相关CFO | 真实=%.1fHz, 估计=%.1fHz, 误差=%.1fHz\n', ...
            true_cfo, cfo_est, cfo_err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 互相关CFO | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 Schmidl-Cox法CFO估计
try
    fs = 48000;
    [half_seq, ~] = gen_zc_seq(128, 1);
    preamble_sc = [half_seq, half_seq]; % 双重复结构
    true_cfo = 30;
    t = (0:255) / fs;
    rx = preamble_sc .* exp(1j*2*pi*true_cfo*t);

    [cfo_est, cfo_norm] = cfo_estimate(rx, preamble_sc, fs, 'schmidl');
    cfo_err = abs(cfo_est - true_cfo);
    fprintf('  [诊断] 3.2 真实=%.4fHz, 估计=%.4fHz, 归一化=%.6f, 误差=%.4fHz\n', ...
            true_cfo, cfo_est, cfo_norm, cfo_err);

    assert(cfo_err < 20, sprintf('Schmidl CFO估计误差过大: 估计=%.4fHz, 真实=%dHz, 误差=%.4fHz', ...
           cfo_est, true_cfo, cfo_err));

    fprintf('[通过] 3.2 Schmidl-Cox CFO | 真实=%.1fHz, 估计=%.1fHz, 误差=%.1fHz\n', ...
            true_cfo, cfo_est, cfo_err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 Schmidl CFO | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 四、细定时同步 ==================== %%
fprintf('\n--- 4. 细定时同步 ---\n\n');

%% 4.1 Gardner TED
try
    proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
    addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
    addpath(fullfile(proj_root, '04_Modulation', 'src', 'Matlab'));

    rng(30);
    sps = 8;
    symbols = 2*randi([0 1],1,100)-1;
    [shaped, ~, ~] = pulse_shape(symbols, sps, 'rrc', 0.35, 6);
    [filtered, ~] = match_filter(shaped, sps, 'rrc', 0.35, 6);

    [timing_off, ted_out] = timing_fine(filtered, sps, 'gardner');
    assert(~isempty(ted_out), 'Gardner TED输出不应为空');

    fprintf('[通过] 4.1 Gardner TED | 定时偏移=%.2f样本, TED均值=%.4f\n', ...
            timing_off, mean(ted_out));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.1 Gardner TED | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 4.2 三种TED方法均可运行
try
    methods = {'gardner', 'mm', 'earlylate'};
    all_ok = true;
    for k = 1:3
        [~, ted] = timing_fine(filtered, sps, methods{k});
        if isempty(ted), all_ok = false; end
    end
    assert(all_ok, '某些TED方法输出为空');

    fprintf('[通过] 4.2 三种TED | gardner/mm/earlylate 均正常\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 4.2 三种TED | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 五、帧组装/解析回环 ==================== %%
fprintf('\n--- 5. 帧组装/解析回环 ---\n\n');

%% 5.1 SC-TDE帧回环
try
    rng(40);
    data = randn(1, 200) + 1j*randn(1, 200);
    params = struct('preamble_type','lfm','fs',48000,'fc',12000,'bw',8000);

    [frame, info] = frame_assemble_sctde(data, params);
    [data_rx, train_rx, sync_info] = frame_parse_sctde(frame, info);

    assert(sync_info.sync_pos > 0, '同步失败');
    assert(length(data_rx) == length(data), '数据长度不一致');
    err = max(abs(data_rx - data));
    assert(err < 1e-10, '数据不一致');

    fprintf('[通过] 5.1 SC-TDE帧回环 | 同步pos=%d, 数据误差=%.2e\n', ...
            sync_info.sync_pos, err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.1 SC-TDE帧 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.2 SC-FDE帧回环
try
    rng(41);
    data = randn(1, 300) + 1j*randn(1, 300);
    params = struct('preamble_type','lfm','fs',48000,'fc',12000,'bw',8000);

    [frame, info] = frame_assemble_scfde(data, params);
    [data_rx, sync_info] = frame_parse_scfde(frame, info);

    assert(sync_info.sync_pos > 0, '同步失败');
    assert(length(data_rx) == length(data), '数据长度不一致');

    fprintf('[通过] 5.2 SC-FDE帧回环 | 含前后导码, 数据长度=%d\n', length(data_rx));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.2 SC-FDE帧 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.3 OFDM帧回环（含CFO估计）
try
    rng(42);
    data = randn(1, 512) + 1j*randn(1, 512);
    params = struct('preamble_type','zc','fs',48000);

    [frame, info] = frame_assemble_ofdm(data, params);
    [data_rx, sync_info] = frame_parse_ofdm(frame, info);

    assert(sync_info.sync_pos > 0, '同步失败');
    assert(length(data_rx) == length(data), '数据长度不一致');
    assert(isfield(sync_info, 'cfo_hz'), '应包含CFO估计');

    fprintf('[通过] 5.3 OFDM帧回环 | ZC前导, CFO估计=%.2fHz\n', sync_info.cfo_hz);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.3 OFDM帧 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 5.4 OTFS帧回环
try
    rng(43);
    data = randn(1, 400) + 1j*randn(1, 400);
    params = struct('preamble_type','hfm','fs',48000,'fc',12000,'bw',8000);

    [frame, info] = frame_assemble_otfs(data, params);
    [data_rx, sync_info] = frame_parse_otfs(frame, info);

    assert(sync_info.sync_pos > 0, '同步失败');
    assert(length(data_rx) == length(data), '数据长度不一致');

    fprintf('[通过] 5.4 OTFS帧回环 | HFM前导(Doppler不变)\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 5.4 OTFS帧 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 六、多普勒补偿同步 ==================== %%
fprintf('\n--- 6. 多普勒补偿同步检测(V2.0) ---\n\n');

% 保存可视化数据
vis6 = struct();

%% 6.1 多普勒频移下的LFM同步
try
    rng(60);
    fs = 48000;
    [preamble, ~] = gen_lfm(fs, 0.01, 8000, 16000);
    offset = 500;
    L = length(preamble);
    fd_true = 30;  % 30Hz多普勒频移
    t_preamble = (0:L-1) / fs;

    preamble_shifted = preamble .* exp(1j*2*pi*fd_true*t_preamble);
    received = [zeros(1, offset), preamble_shifted, randn(1, 1000)*0.1];

    [pos_std, peak_std, corr_std] = sync_detect(received, preamble, 0.3);
    dp = struct('method','doppler','fs',fs,'fd_max',50,'num_fd',21);
    [pos_dp, peak_dp, corr_dp] = sync_detect(received, preamble, 0.3, dp);

    assert(abs(pos_dp - offset - 1) <= 2, '多普勒补偿同步偏差过大');
    assert(peak_dp >= peak_std - 1e-10, '多普勒补偿后峰值应不低于标准方法');

    fprintf('[通过] 6.1 多普勒补偿LFM | fd=%dHz, 标准峰值=%.3f, 补偿峰值=%.3f\n', ...
            fd_true, peak_std, peak_dp);
    pass_count = pass_count + 1;
    vis6.corr_std = corr_std; vis6.corr_dp = corr_dp; vis6.offset1 = offset;
    vis6.fd1 = fd_true; vis6.ok1 = true;
catch e
    fprintf('[失败] 6.1 多普勒补偿LFM | %s\n', e.message);
    fail_count = fail_count + 1;
    vis6.ok1 = false;
end

%% 6.2 多普勒补偿ZC同步
try
    rng(61);
    [preamble, ~] = gen_zc_seq(255, 7);
    offset = 300;
    L = length(preamble);
    fd_true = 40;
    t_preamble = (0:L-1) / fs;

    preamble_shifted = preamble .* exp(1j*2*pi*fd_true*t_preamble);
    noise = 0.3 * (randn(1, 1500) + 1j*randn(1, 1500));
    received = noise;
    received(offset+1 : offset+L) = received(offset+1 : offset+L) + preamble_shifted;

    [~, ~, corr_std_zc] = sync_detect(received, preamble, 0.3);
    dp = struct('method','doppler','fs',fs,'fd_max',60,'num_fd',25);
    [pos, peak, corr_dp_zc] = sync_detect(received, preamble, 0.3, dp);

    assert(abs(pos - offset - 1) <= 2, 'ZC多普勒补偿同步偏差过大');

    fprintf('[通过] 6.2 多普勒补偿ZC | fd=%dHz, 位置=%d, 峰值=%.3f\n', ...
            fd_true, pos, peak);
    pass_count = pass_count + 1;
    vis6.corr_std_zc = corr_std_zc; vis6.corr_dp_zc = corr_dp_zc;
    vis6.offset2 = offset; vis6.fd2 = fd_true; vis6.ok2 = true;
catch e
    fprintf('[失败] 6.2 多普勒补偿ZC | %s\n', e.message);
    fail_count = fail_count + 1;
    vis6.ok2 = false;
end

%% --- 可视化：多普勒补偿对比（独立于测试） --- %%
try
    if isfield(vis6,'ok1') && vis6.ok1 && isfield(vis6,'ok2') && vis6.ok2
        figure('Name','多普勒补偿同步对比','NumberTitle','off','Position',[50 50 1100 500]);
        subplot(1,2,1);
        plot(vis6.corr_std, 'b', 'LineWidth', 1); hold on;
        plot(vis6.corr_dp, 'r', 'LineWidth', 1);
        xl = line([vis6.offset1+1, vis6.offset1+1], [0 1.1], 'Color','k','LineStyle','--');
        legend('标准互相关', '多普勒补偿', '真实位置', 'Location','best');
        xlabel('采样点'); ylabel('归一化相关值');
        title(sprintf('6.1 LFM同步 | fd=%dHz', vis6.fd1)); grid on; ylim([0 1.1]);

        subplot(1,2,2);
        plot(vis6.corr_std_zc, 'b', 'LineWidth', 1); hold on;
        plot(vis6.corr_dp_zc, 'r', 'LineWidth', 1);
        line([vis6.offset2+1, vis6.offset2+1], [0 1.1], 'Color','k','LineStyle','--');
        legend('标准互相关', '多普勒补偿', '真实位置', 'Location','best');
        xlabel('采样点'); ylabel('归一化相关值');
        title(sprintf('6.2 ZC同步 | fd=%dHz', vis6.fd2)); grid on; ylim([0 1.1]);
    end
catch; end

%% ==================== 七、相位跟踪(V2.0) ==================== %%
fprintf('\n--- 7. 相位跟踪 ---\n\n');

% 保存可视化数据
vis7 = struct();

%% 7.1 PLL相位跟踪（恒定频偏）
try
    rng(70);
    N_sym = 500;
    bits = randi([0 3], 1, N_sym);
    qpsk = exp(1j * (pi/4 + bits*pi/2)) / sqrt(2);

    freq_offset = 0.005;
    phase_ramp = 2*pi*freq_offset*(0:N_sym-1);
    noise = 0.05 * (randn(1, N_sym) + 1j*randn(1, N_sym));
    rx = qpsk .* exp(1j * phase_ramp) + noise;

    pll_params = struct('Bn', 0.02, 'mod_order', 4);
    [ph_est_pll, ~, info_pll] = phase_track(rx, 'pll', pll_params);

    tail = floor(N_sym/2):N_sym;
    phase_err_rms = sqrt(mean(info_pll.phase_error(tail).^2));
    assert(phase_err_rms < 0.3, 'PLL收敛后相位误差过大');

    fprintf('[通过] 7.1 PLL | 频偏=%.3f, 收敛后RMS误差=%.4f rad\n', ...
            freq_offset, phase_err_rms);
    pass_count = pass_count + 1;
    vis7.phase_ramp = phase_ramp; vis7.ph_pll = ph_est_pll;
    vis7.err_pll = info_pll.phase_error; vis7.rx_pll = rx;
    vis7.corr_pll = info_pll.corrected; vis7.ok1 = true;
catch e
    fprintf('[失败] 7.1 PLL | %s\n', e.message);
    fail_count = fail_count + 1;
    vis7.ok1 = false;
end

%% 7.2 DFPT判决反馈相位跟踪
try
    rng(71);
    N_sym = 500;
    bits2 = randi([0 3], 1, N_sym);
    qpsk2 = exp(1j * (pi/4 + bits2*pi/2)) / sqrt(2);

    phase_drift = 0.3 * sin(2*pi*(0:N_sym-1)/N_sym);
    noise2 = 0.03 * (randn(1, N_sym) + 1j*randn(1, N_sym));
    rx2 = qpsk2 .* exp(1j * phase_drift) + noise2;

    dfpt_params = struct('mu', 0.05, 'mod_order', 4);
    [ph_est_dfpt, ~, info_dfpt] = phase_track(rx2, 'dfpt', dfpt_params);

    corrected_dfpt = info_dfpt.corrected;
    err_power = mean(abs(corrected_dfpt - qpsk2).^2);
    assert(err_power < 0.1, 'DFPT补偿后误差过大');

    fprintf('[通过] 7.2 DFPT | 正弦相位漂移, 补偿后MSE=%.4f\n', err_power);
    pass_count = pass_count + 1;
    vis7.phase_drift = phase_drift; vis7.ph_dfpt = ph_est_dfpt;
    vis7.err_dfpt = info_dfpt.phase_error; vis7.rx_dfpt = rx2;
    vis7.corr_dfpt = corrected_dfpt; vis7.ok2 = true;
catch e
    fprintf('[失败] 7.2 DFPT | %s\n', e.message);
    fail_count = fail_count + 1;
    vis7.ok2 = false;
end

%% 7.3 Kalman联合跟踪（线性频偏斜率）
try
    rng(72);
    N_sym = 500;
    bits3 = randi([0 3], 1, N_sym);
    qpsk3 = exp(1j * (pi/4 + bits3*pi/2)) / sqrt(2);

    Ts = 1/48000;
    freq_rate = 5;
    t = (0:N_sym-1) * Ts;
    phase_accel = 2*pi * 0.5 * freq_rate * t.^2;
    noise3 = 0.05 * (randn(1, N_sym) + 1j*randn(1, N_sym));
    rx3 = qpsk3 .* exp(1j * phase_accel) + noise3;

    kal_params = struct('Ts', Ts, 'q_phase', 1e-3, 'q_freq', 1e-4, ...
                        'q_frate', 1e-5, 'r_obs', 0.1, 'mod_order', 4);
    [ph_est_kal, freq_est_kal, info_kal] = phase_track(rx3, 'kalman', kal_params);

    assert(~isempty(freq_est_kal), 'Kalman应输出频偏估计');
    tail = floor(N_sym*0.6):N_sym;
    phase_err_rms_kal = sqrt(mean(info_kal.phase_error(tail).^2));
    assert(phase_err_rms_kal < 0.5, 'Kalman收敛后相位误差过大');

    fprintf('[通过] 7.3 Kalman | 线性频偏斜率=%dHz/s, 收敛后RMS=%.4f rad\n', ...
            freq_rate, phase_err_rms_kal);
    pass_count = pass_count + 1;
    vis7.phase_accel = phase_accel; vis7.ph_kal = ph_est_kal;
    vis7.freq_kal = freq_est_kal; vis7.rx_kal = rx3;
    vis7.corr_kal = info_kal.corrected; vis7.ok3 = true;
catch e
    fprintf('[失败] 7.3 Kalman | %s\n', e.message);
    fail_count = fail_count + 1;
    vis7.ok3 = false;
end

%% 7.4 三种相位跟踪方法均可运行
try
    rng(73);
    N_sym = 200;
    test_signal = exp(1j * pi/4 * ones(1, N_sym)) / sqrt(2);
    methods_pt = {'pll', 'dfpt', 'kalman'};
    all_ok = true;
    for k = 1:3
        [ph, fr, inf] = phase_track(test_signal, methods_pt{k});
        if isempty(ph) || isempty(inf.corrected), all_ok = false; end
    end
    assert(all_ok, '某些相位跟踪方法输出异常');

    fprintf('[通过] 7.4 三种方法 | pll/dfpt/kalman 均正常\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 7.4 三种方法 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 7.5 BPSK模式相位跟踪
try
    rng(74);
    N_sym = 300;
    bpsk = 2*randi([0 1], 1, N_sym) - 1;
    phase_offset = pi/6;
    rx_bpsk = bpsk * exp(1j * phase_offset) + 0.02*(randn(1,N_sym)+1j*randn(1,N_sym));

    p = struct('Bn', 0.03, 'mod_order', 2);
    [ph_est_bpsk, ~, info_bpsk] = phase_track(rx_bpsk, 'pll', p);

    tail = floor(N_sym/2):N_sym;
    est_phase_tail = mean(ph_est_bpsk(tail));
    assert(abs(est_phase_tail - phase_offset) < 0.15, 'BPSK相位估计偏差过大');

    fprintf('[通过] 7.5 BPSK PLL | 真实相偏=%.2frad, 估计=%.2frad\n', ...
            phase_offset, est_phase_tail);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 7.5 BPSK PLL | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% --- 可视化：相位跟踪综合图（独立于测试） --- %%
try
    if isfield(vis7,'ok1') && vis7.ok1 && isfield(vis7,'ok2') && vis7.ok2 ...
            && isfield(vis7,'ok3') && vis7.ok3
        figure('Name','相位跟踪结果','NumberTitle','off','Position',[60 40 1200 800]);

        % PLL
        subplot(3,3,1);
        plot(vis7.phase_ramp,'b','LineWidth',1); hold on;
        plot(vis7.ph_pll,'r--','LineWidth',1);
        legend('真实相位','PLL估计'); xlabel('符号索引'); ylabel('rad');
        title('7.1 PLL: 恒定频偏'); grid on;

        subplot(3,3,2);
        plot(vis7.err_pll,'Color',[0.2 0.6 0.2],'LineWidth',0.5);
        xlabel('符号索引'); ylabel('rad'); title('PLL 相位误差'); grid on;

        subplot(3,3,3);
        plot(real(vis7.rx_pll), imag(vis7.rx_pll), '.','Color',[.7 .7 .7],'MarkerSize',3); hold on;
        plot(real(vis7.corr_pll), imag(vis7.corr_pll), 'r.','MarkerSize',3);
        legend('补偿前','补偿后'); xlabel('I'); ylabel('Q');
        title('PLL 星座图'); grid on; axis equal; axis([-1.5 1.5 -1.5 1.5]);

        % DFPT
        subplot(3,3,4);
        plot(vis7.phase_drift,'b','LineWidth',1); hold on;
        plot(vis7.ph_dfpt,'r--','LineWidth',1);
        legend('真实相位','DFPT估计'); xlabel('符号索引'); ylabel('rad');
        title('7.2 DFPT: 正弦漂移'); grid on;

        subplot(3,3,5);
        plot(vis7.err_dfpt,'Color',[0.2 0.6 0.2],'LineWidth',0.5);
        xlabel('符号索引'); ylabel('rad'); title('DFPT 相位误差'); grid on;

        subplot(3,3,6);
        plot(real(vis7.rx_dfpt), imag(vis7.rx_dfpt), '.','Color',[.7 .7 .7],'MarkerSize',3); hold on;
        plot(real(vis7.corr_dfpt), imag(vis7.corr_dfpt), 'r.','MarkerSize',3);
        legend('补偿前','补偿后'); xlabel('I'); ylabel('Q');
        title('DFPT 星座图'); grid on; axis equal; axis([-1.5 1.5 -1.5 1.5]);

        % Kalman
        subplot(3,3,7);
        plot(vis7.phase_accel,'b','LineWidth',1); hold on;
        plot(vis7.ph_kal,'r--','LineWidth',1);
        legend('真实相位','Kalman估计'); xlabel('符号索引'); ylabel('rad');
        title('7.3 Kalman: 频偏斜率'); grid on;

        subplot(3,3,8);
        plot(vis7.freq_kal,'Color',[0.8 0.4 0],'LineWidth',1);
        xlabel('符号索引'); ylabel('Hz'); title('Kalman 频偏估计'); grid on;

        subplot(3,3,9);
        plot(real(vis7.rx_kal), imag(vis7.rx_kal), '.','Color',[.7 .7 .7],'MarkerSize',3); hold on;
        plot(real(vis7.corr_kal), imag(vis7.corr_kal), 'r.','MarkerSize',3);
        legend('补偿前','补偿后'); xlabel('I'); ylabel('Q');
        title('Kalman 星座图'); grid on; axis equal; axis([-1.5 1.5 -1.5 1.5]);
    end
catch; end

%% ==================== 八、多普勒同步误差分析(V2.0) ==================== %%
fprintf('\n--- 8. 多普勒下同步误差分析 ---\n\n');

% 保存可视化数据
vis8 = struct();

%% 8.1 双HFM帧同步——多普勒定时偏置消除
try
    rng(80);
    fs = 48000; fc = 12000; T_hfm = 0.05;
    bw = 8000; f_lo = fc - bw/2; f_hi = fc + bw/2;
    S_bias = T_hfm * fc / bw;  % 偏置灵敏度

    % 生成HFM+和HFM-基带模板
    [hfm_pb_pos, ~] = gen_hfm(fs, T_hfm, f_lo, f_hi);
    [hfm_pb_neg, ~] = gen_hfm(fs, T_hfm, f_hi, f_lo);
    L_hfm = length(hfm_pb_pos);
    t_hfm = (0:L_hfm-1)/fs;
    % 基带版本
    if abs(f_hi-f_lo) < 1e-6
        phase_pos = 2*pi*f_lo*t_hfm; phase_neg = phase_pos;
    else
        k_pos = f_lo*f_hi*T_hfm/(f_hi-f_lo);
        phase_pos = -2*pi*k_pos*log(1 - (f_hi-f_lo)/f_hi*t_hfm/T_hfm);
        k_neg = f_hi*f_lo*T_hfm/(f_lo-f_hi);
        phase_neg = -2*pi*k_neg*log(1 - (f_lo-f_hi)/f_lo*t_hfm/T_hfm);
    end
    hfm_bb_pos = exp(1j*(phase_pos - 2*pi*fc*t_hfm));
    hfm_bb_neg = exp(1j*(phase_neg - 2*pi*fc*t_hfm));

    % 扫描多普勒因子
    alpha_list = [0, 0.0005, 0.001, 0.003, 0.005, 0.01];
    snr_test = 15;  % dB
    tau_err_lfm = zeros(1, length(alpha_list));
    tau_err_hfm_pos = zeros(1, length(alpha_list));
    tau_err_dual = zeros(1, length(alpha_list));
    alpha_est_dual = zeros(1, length(alpha_list));
    offset_true = 200;  % 真实帧起始(采样点)

    guard = 500;
    for ai = 1:length(alpha_list)
        alpha = alpha_list(ai);
        % 构建帧：[zeros|HFM+|guard|HFM-|zeros]，模拟多普勒通过偏移HFM峰位置
        % HFM+定时偏置: Δτ+ = -α·S_bias (采样点: -α·S_bias·fs)
        % HFM-定时偏置: Δτ- = +α·S_bias
        bias_samp = round(alpha * S_bias * fs);
        hfm_neg_start = offset_true + L_hfm + guard;

        frame = zeros(1, offset_true + 2*L_hfm + guard + 1000);
        % HFM+放在 offset_true+1-bias_samp 处（偏置偏早）
        pos_start = max(1, offset_true + 1 - bias_samp);
        pos_end = min(pos_start + L_hfm - 1, length(frame));
        frame(pos_start : pos_end) = hfm_bb_pos(1 : pos_end-pos_start+1);
        % HFM-放在 hfm_neg_start+1+bias_samp 处（偏置偏晚）
        neg_start = hfm_neg_start + 1 + bias_samp;
        neg_end = min(neg_start + L_hfm - 1, length(frame));
        frame(neg_start : neg_end) = hfm_bb_neg(1 : neg_end-neg_start+1);

        % 加噪
        sig_pwr = mean(abs(hfm_bb_pos).^2);
        noise_var_t = sig_pwr * 10^(-snr_test/10);
        rng(80 + ai);
        frame_noisy = frame + sqrt(noise_var_t/2)*(randn(size(frame))+1j*randn(size(frame)));

        % LFM同步（对比基线，用LFM模板找HFM+位置）
        [lfm_ref, ~] = gen_lfm(fs, T_hfm, f_lo, f_hi);
        t_lfm_ref = (0:length(lfm_ref)-1)/fs;
        lfm_bb_ref = exp(1j*2*pi*(-bw/2*t_lfm_ref + 0.5*bw/T_hfm*t_lfm_ref.^2));
        [pos_lfm, ~, ~] = sync_detect(frame_noisy, lfm_bb_ref, 0.2);
        tau_err_lfm(ai) = pos_lfm - (offset_true + 1);

        % 单路HFM+同步
        [pos_hfm, ~, ~] = sync_detect(frame_noisy, hfm_bb_pos, 0.2);
        tau_err_hfm_pos(ai) = pos_hfm - (offset_true + 1);

        % 双HFM消偏同步
        sp = struct('S_bias', S_bias, 'alpha_max', 0.02, ...
                     'search_win', length(frame_noisy), ...
                     'sep_samples', L_hfm + guard, ...
                     'frame_gap', guard);
        [tau_dual, alpha_dual, ~, ~] = sync_dual_hfm(frame_noisy, hfm_bb_pos, hfm_bb_neg, fs, sp);
        % tau_dual是消偏后的帧起始估计
        tau_err_dual(ai) = tau_dual - (offset_true + 1);
        alpha_est_dual(ai) = alpha_dual;
    end

    % 打印对比表
    fprintf('  SNR=%ddB, S_bias=%.4fs, 帧偏移=%d采样点\n', snr_test, S_bias, offset_true);
    fprintf('  %-10s | %-12s | %-12s | %-12s | %-12s | %-12s\n', ...
        'α(v m/s)', 'LFM偏差', 'HFM+偏差', '双HFM偏差', 'α估计', 'α误差');
    fprintf('  %s\n', repmat('-', 1, 78));
    all_dual_ok = true;
    for ai = 1:length(alpha_list)
        v = alpha_list(ai) * 1500;
        fprintf('  %.4f(%4.1f) | %+8d samp | %+8d samp | %+8d samp | %+.2e | %+.2e\n', ...
            alpha_list(ai), v, tau_err_lfm(ai), tau_err_hfm_pos(ai), ...
            tau_err_dual(ai), alpha_est_dual(ai), alpha_est_dual(ai)-alpha_list(ai));
        % 双HFM定时误差应<10采样点
        if abs(tau_err_dual(ai)) > 20, all_dual_ok = false; end
    end
    assert(all_dual_ok, '双HFM消偏后定时误差过大(>20样本)');
    fprintf('[通过] 8.1 双HFM消偏 | 6个速度点, 定时偏差均<20样本\n');
    pass_count = pass_count + 1;
    vis8.alpha_list = alpha_list; vis8.tau_err_lfm = tau_err_lfm;
    vis8.tau_err_hfm = tau_err_hfm_pos; vis8.tau_err_dual = tau_err_dual;
    vis8.alpha_est = alpha_est_dual; vis8.ok1 = true;
catch e
    fprintf('[失败] 8.1 双HFM消偏 | %s\n', e.message);
    fail_count = fail_count + 1;
    vis8.ok1 = false;
end

%% 8.2 多普勒因子估计精度 vs SNR
try
    snr_list_test = [0, 5, 10, 15, 20, 25];
    alpha_test_val = 0.003;  % 约4.5m/s
    N_trial = 20;
    alpha_rmse = zeros(1, length(snr_list_test));
    bias_samp_test = round(alpha_test_val * S_bias * fs);

    for si = 1:length(snr_list_test)
        alpha_errs = zeros(1, N_trial);
        for trial = 1:N_trial
            rng(81*100 + si*10 + trial);
            % 用偏置模型构建帧（与8.1一致）
            frame_t = zeros(1, offset_true + 2*L_hfm + guard + 1000);
            ps = max(1, offset_true + 1 - bias_samp_test);
            pe = min(ps + L_hfm - 1, length(frame_t));
            frame_t(ps:pe) = hfm_bb_pos(1:pe-ps+1);
            ns = offset_true + L_hfm + guard + 1 + bias_samp_test;
            ne = min(ns + L_hfm - 1, length(frame_t));
            frame_t(ns:ne) = hfm_bb_neg(1:ne-ns+1);

            % 加噪
            sig_pwr_t = mean(abs(hfm_bb_pos).^2);
            nv = max(sig_pwr_t * 10^(-snr_list_test(si)/10), 1e-10);
            rx = frame_t + sqrt(nv/2)*(randn(size(frame_t))+1j*randn(size(frame_t)));

            sp = struct('S_bias', S_bias, 'alpha_max', 0.02, ...
                        'search_win', length(rx), 'sep_samples', L_hfm + guard, ...
                        'frame_gap', guard);
            [~, a_est, ~, ~] = sync_dual_hfm(rx, hfm_bb_pos, hfm_bb_neg, fs, sp);
            alpha_errs(trial) = a_est - alpha_test_val;
        end
        alpha_rmse(si) = sqrt(mean(alpha_errs.^2));
    end

    fprintf('[通过] 8.2 多普勒估计精度 | α=%.4f, %d次蒙特卡洛\n', alpha_test_val, N_trial);
    fprintf('  SNR(dB):  '); fprintf('%8d', snr_list_test); fprintf('\n');
    fprintf('  RMSE:     '); fprintf('%8.2e', alpha_rmse); fprintf('\n');
    % 高SNR下RMSE应<1e-3
    assert(alpha_rmse(end) < 5e-3, '高SNR多普勒估计RMSE过大');
    pass_count = pass_count + 1;
    vis8.snr_list = snr_list_test; vis8.alpha_rmse = alpha_rmse; vis8.ok2 = true;
catch e
    fprintf('[失败] 8.2 多普勒估计精度 | %s\n', e.message);
    fail_count = fail_count + 1;
    vis8.ok2 = false;
end

%% 8.3 PLL载波同步跟踪
try
    rng(82);
    N_sym = 1000;
    bits = randi([0 3], 1, N_sym);
    qpsk = exp(1j*(pi/4 + bits*pi/2)) / sqrt(2);

    % 模拟残余CFO + 加速度相位漂移
    cfo_hz = 3;  % 3Hz残余CFO
    sym_rate = 6000;
    t_sym = (0:N_sym-1)/sym_rate;
    phase_true = 2*pi*cfo_hz*t_sym + 0.5*sin(2*pi*0.5*t_sym);  % CFO+慢变
    noise = 0.05*(randn(1,N_sym)+1j*randn(1,N_sym));
    rx_pll = qpsk .* exp(1j*phase_true) + noise;

    [r_corrected, phi_track, pll_info] = pll_carrier_sync(rx_pll, 4, 0.02, 0.005);

    % 补偿后星座误差
    tail = floor(N_sym/2):N_sym;
    err_before = mean(abs(rx_pll(tail) - qpsk(tail)).^2);
    err_after = mean(abs(r_corrected(tail) - qpsk(tail)).^2);
    assert(err_after < err_before, 'PLL补偿后误差应减小');

    fprintf('[通过] 8.3 PLL载波同步 | CFO=%dHz, MSE: %.4f→%.4f (%.1fdB改善)\n', ...
        cfo_hz, err_before, err_after, 10*log10(err_before/err_after));
    pass_count = pass_count + 1;
    vis8.phase_true = phase_true; vis8.phi_track = phi_track;
    vis8.rx_pll_in = rx_pll; vis8.rx_pll_out = r_corrected;
    vis8.qpsk_ref = qpsk; vis8.ok3 = true;
catch e
    fprintf('[失败] 8.3 PLL载波同步 | %s\n', e.message);
    fail_count = fail_count + 1;
    vis8.ok3 = false;
end

%% --- 可视化：多普勒同步误差分析（独立于测试） --- %%
try
    if isfield(vis8,'ok1') && vis8.ok1
        figure('Name','多普勒同步误差分析','NumberTitle','off','Position',[50 50 1200 800]);

        % 定时偏差 vs 速度
        subplot(2,3,1);
        v_list = vis8.alpha_list * 1500;
        plot(v_list, vis8.tau_err_lfm, 'b-o', 'LineWidth', 1.2); hold on;
        plot(v_list, vis8.tau_err_hfm, 'r-s', 'LineWidth', 1.2);
        plot(v_list, vis8.tau_err_dual, 'g-^', 'LineWidth', 1.5);
        legend('LFM', 'HFM+(单路)', '双HFM消偏');
        xlabel('速度 (m/s)'); ylabel('定时偏差 (采样点)');
        title('定时误差 vs 速度'); grid on;

        % 多普勒估计误差
        subplot(2,3,2);
        plot(v_list, vis8.alpha_est - vis8.alpha_list, 'k-d', 'LineWidth', 1.2);
        xlabel('速度 (m/s)'); ylabel('\alpha 估计误差');
        title('多普勒估计误差'); grid on;

        % 多普勒估计值 vs 真值
        subplot(2,3,3);
        plot(vis8.alpha_list, vis8.alpha_est, 'ro', 'MarkerSize', 8, 'LineWidth', 1.5); hold on;
        plot(vis8.alpha_list, vis8.alpha_list, 'k--', 'LineWidth', 1);
        legend('估计值', '真值'); xlabel('\alpha_{true}'); ylabel('\alpha_{est}');
        title('多普勒估计精度'); grid on; axis equal;
    end

    if isfield(vis8,'ok2') && vis8.ok2
        % RMSE vs SNR
        subplot(2,3,4);
        semilogy(vis8.snr_list, vis8.alpha_rmse, 'b-o', 'LineWidth', 1.5);
        xlabel('SNR (dB)'); ylabel('\alpha RMSE');
        title(sprintf('多普勒RMSE vs SNR (\\alpha=%.3f)', alpha_test_val)); grid on;
    end

    if isfield(vis8,'ok3') && vis8.ok3
        % PLL相位跟踪
        subplot(2,3,5);
        plot(vis8.phase_true, 'b', 'LineWidth', 1); hold on;
        plot(vis8.phi_track, 'r--', 'LineWidth', 1);
        legend('真实相位', 'PLL跟踪'); xlabel('符号'); ylabel('rad');
        title('PLL载波相位跟踪'); grid on;

        % PLL补偿前后星座
        subplot(2,3,6);
        plot(real(vis8.rx_pll_in), imag(vis8.rx_pll_in), '.', 'Color', [.7 .7 .7], 'MarkerSize', 2); hold on;
        plot(real(vis8.rx_pll_out), imag(vis8.rx_pll_out), 'r.', 'MarkerSize', 2);
        legend('补偿前', 'PLL补偿后'); xlabel('I'); ylabel('Q');
        title('PLL载波同步星座图'); grid on; axis equal; axis([-1.5 1.5 -1.5 1.5]);
    end
catch; end

%% ==================== 九、异常输入 ==================== %%
fprintf('\n--- 9. 异常输入测试 ---\n\n');

try
    caught = 0;
    try sync_detect([], [1 -1]); catch; caught=caught+1; end
    try cfo_estimate([], [1], 48000); catch; caught=caught+1; end
    try timing_fine([], 8); catch; caught=caught+1; end
    try gen_barker(6); catch; caught=caught+1; end           % 非法Barker长度
    try gen_zc_seq(0); catch; caught=caught+1; end           % N<1
    try phase_track([]); catch; caught=caught+1; end         % 空信号
    try sync_detect([1 2 3], [1 -1], 0.5, struct('method','doppler')); catch; caught=caught+1; end  % doppler缺fs

    try sync_dual_hfm([], [1], [1], 48000, struct('S_bias',0.1)); catch; caught=caught+1; end
    try pll_carrier_sync([]); catch; caught=caught+1; end

    assert(caught == 9, '部分函数未对异常输入报错');

    fprintf('[通过] 9.1 异常输入拒绝 | 9项均正确报错\n');
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 9.1 异常输入 | %s\n', e.message);
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
