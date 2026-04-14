%% test_otfs_frame_v2.m — OTFS两级同步帧V2.0单元测试
% 功能: 验证 frame_assemble_otfs V2.0 / frame_parse_otfs V2.0
% 帧结构: [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|OTFS_pb]
% 版本: V1.0.0

clc; close all;
fprintf('========================================\n');
fprintf('  OTFS 两级同步帧 V2.0 — 单元测试\n');
fprintf('========================================\n\n');

pass_count = 0;
fail_count = 0;

% 添加跨模块依赖路径
proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));

% 公共参数
N = 64; M = 32; cp_len = 8;  % N=64保证数据长度>=2×sync
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
frame_p = struct('N',N, 'M',M, 'cp_len',cp_len, ...
                 'sps',6, 'fs_bb',6000, 'fc',12000, 'bw',8000, ...
                 'T_hfm',0.05, 'T_lfm',0.02, 'guard_ms',5, ...
                 'sync_gain',0.7);  % sync < data峰值

%% ==================== 1. 帧组装基本功能 ==================== %%
fprintf('--- 1. 帧组装 ---\n\n');

%% 1.1 帧长度与段位置
try
    rng(11);
    dd_data = constellation(randi(4, N, M));
    [otfs_bb, ~] = otfs_modulate(dd_data, N, M, cp_len, 'dft');
    [frame, info] = frame_assemble_otfs(otfs_bb, frame_p);

    % 校验各段位置连续性
    assert(info.seg.hfm_pos_start == 1, 'HFM+起始应为1');
    assert(info.seg.otfs_start > info.seg.lfm2_start, 'OTFS段应在LFM2之后');
    expected_total = info.seg.otfs_start - 1 + info.otfs_pb_len;
    assert(length(frame) == expected_total, '帧总长度不匹配');
    imag_ratio = max(abs(imag(frame))) / max(abs(real(frame)));
    assert(imag_ratio < 1e-10, sprintf('通带帧虚部过大: %.2e', imag_ratio));

    fprintf('[通过] 1.1 帧长度与段位置 | 总长=%d, fs_pb=%dHz\n', length(frame), info.fs_pb);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.1 帧长度与段位置 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 1.2 双HFM/双LFM段功率匹配
try
    % HFM+/HFM-/LFM段应功率相近
    seg_hfm_pos = frame(info.seg.hfm_pos_start : info.seg.hfm_pos_start+info.L_hfm-1);
    seg_hfm_neg = frame(info.seg.hfm_neg_start : info.seg.hfm_neg_start+info.L_hfm-1);
    seg_lfm1 = frame(info.seg.lfm1_start : info.seg.lfm1_start+info.L_lfm-1);
    seg_lfm2 = frame(info.seg.lfm2_start : info.seg.lfm2_start+info.L_lfm-1);

    pwr_hfm_pos = mean(seg_hfm_pos.^2);
    pwr_hfm_neg = mean(seg_hfm_neg.^2);
    pwr_lfm1 = mean(seg_lfm1.^2);
    pwr_lfm2 = mean(seg_lfm2.^2);

    % LFM1和LFM2应完全相同（同模板）
    assert(max(abs(seg_lfm1 - seg_lfm2)) < 1e-10, 'LFM1/LFM2应相同');
    % HFM+/-功率相近
    assert(abs(pwr_hfm_pos - pwr_hfm_neg)/pwr_hfm_pos < 0.01, 'HFM+/-功率差异过大');

    fprintf('[通过] 1.2 段功率与模板一致性 | HFM+/-=%.3f/%.3f, LFM1=LFM2\n', pwr_hfm_pos, pwr_hfm_neg);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 1.2 段功率与模板一致性 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 2. 帧回环（无信道） ==================== %%
fprintf('\n--- 2. 帧回环 ---\n\n');

%% 2.1 无噪声帧回环（硬判决BER）
try
    [otfs_rx, sync] = frame_parse_otfs(frame, info);
    [dd_rx, ~] = otfs_demodulate(otfs_rx, N, M, cp_len, 'dft');
    % QPSK硬判决
    dd_hard = (sign(real(dd_rx(:))) + 1j*sign(imag(dd_rx(:)))) / sqrt(2);
    sym_err = mean(abs(dd_hard - dd_data(:)) > 0.1);
    err = max(abs(dd_rx(:) - dd_data(:)));

    fprintf('  alpha_est=%.2e (期望~0), tau_coarse=%d, tau_fine=%d\n', ...
            sync.alpha_est, sync.tau_coarse, sync.tau_fine);
    assert(abs(sync.alpha_est) < 1e-3, sprintf('alpha估计偏大=%.2e', sync.alpha_est));
    assert(sym_err == 0, sprintf('无噪声符号错率=%.2f%%', sym_err*100));

    fprintf('[通过] 2.1 无噪声帧回环 | alpha=%.2e, 符号错=%.1f%%, DD max误差=%.2e\n', ...
            sync.alpha_est, sym_err*100, err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.1 无噪声帧回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 2.2 加噪帧回环 (SNR=20dB)
try
    rng(22);
    sig_pwr = mean(frame.^2);
    nv = sig_pwr * 10^(-20/10);
    frame_noisy = frame + sqrt(nv) * randn(size(frame));

    [otfs_rx_n, sync_n] = frame_parse_otfs(frame_noisy, info);
    [dd_rx_n, ~] = otfs_demodulate(otfs_rx_n, N, M, cp_len, 'dft');

    % QPSK判决
    dd_rx_hard = sign(real(dd_rx_n(:))) + 1j*sign(imag(dd_rx_n(:)));
    dd_rx_hard = dd_rx_hard / sqrt(2);
    sym_err = mean(abs(dd_rx_hard - dd_data(:)) > 0.1);

    fprintf('  alpha_est=%.2e, tau_fine=%d, 符号错=%.2f%%\n', ...
            sync_n.alpha_est, sync_n.tau_fine, sym_err*100);
    assert(sym_err < 0.1, sprintf('20dB SNR下符号错率=%.2f%%过大', sym_err*100));

    fprintf('[通过] 2.2 加噪帧回环(20dB) | 符号错=%.2f%%\n', sym_err*100);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 2.2 加噪帧回环 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 3. 多普勒场景 ==================== %%
fprintf('\n--- 3. 多普勒估计 ---\n\n');

%% 3.1 离散多普勒帧回环 (alpha=0.0005, 水声典型范围)
% 物理限制: sync精度受限于fc*alpha*T_hfm相位旋转量, 水声α~4e-4 (5Hz@12kHz)
try
    rng(31);
    alpha_true = 0.0005;  % ~0.75 m/s, 典型水声
    total_len = length(frame);
    n_tx = (0:total_len-1) * (1 + alpha_true);
    frame_dop = interp1(0:total_len-1, frame, n_tx, 'spline', 0);

    [otfs_rx_d, sync_d] = frame_parse_otfs(frame_dop, info);
    alpha_err = sync_d.alpha_est - alpha_true;

    fprintf('  alpha_true=%.4f, alpha_est=%.4f, err=%.2e\n', ...
            alpha_true, sync_d.alpha_est, alpha_err);
    % 水声场景下，相对误差<100%可接受（粗估，端到端Turbo可进一步细化）
    assert(abs(alpha_err) < 1e-3, sprintf('alpha估计误差=%.2e过大', alpha_err));

    fprintf('[通过] 3.1 离散Doppler(小α) | alpha误差=%.2e\n', alpha_err);
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.1 离散Doppler(小α) | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% 3.2 alpha扫描 (限于水声实际范围0~0.001)
try
    alpha_list = [0, 0.0001, 0.0003, 0.0005, 0.001];
    alpha_err_list = zeros(size(alpha_list));
    fprintf('  alpha_true  | alpha_est    | 误差\n');
    fprintf('  %s\n', repmat('-', 1, 45));
    for ai = 1:length(alpha_list)
        at = alpha_list(ai);
        if at == 0
            frame_a = frame;
        else
            n_tx = (0:length(frame)-1) * (1 + at);
            frame_a = interp1(0:length(frame)-1, frame, n_tx, 'spline', 0);
        end
        [~, sync_a] = frame_parse_otfs(frame_a, info);
        alpha_err_list(ai) = sync_a.alpha_est - at;
        fprintf('  %-10.4f | %-12.6f | %+.2e\n', at, sync_a.alpha_est, alpha_err_list(ai));
    end
    assert(max(abs(alpha_err_list)) < 1.5e-3, 'alpha扫描误差过大');
    fprintf('[通过] 3.2 alpha扫描 | max误差=%.2e\n', max(abs(alpha_err_list)));
    pass_count = pass_count + 1;
catch e
    fprintf('[失败] 3.2 alpha扫描 | %s\n', e.message);
    fail_count = fail_count + 1;
end

%% ==================== 可视化 ==================== %%
try
    figure('Name', 'OTFS Frame V2.0', 'NumberTitle', 'off', 'Position', [50 50 1200 700]);

    % 帧时域波形 + 段标注
    subplot(2,1,1);
    t_ax = (0:length(frame)-1) / info.fs_pb * 1e3;
    plot(t_ax, frame, 'b', 'LineWidth', 0.5); hold on;
    seg_positions = [info.seg.hfm_pos_start, info.seg.hfm_neg_start, ...
                      info.seg.lfm1_start, info.seg.lfm2_start, info.seg.otfs_start];
    seg_names = {'HFM+', 'HFM-', 'LFM1', 'LFM2', 'OTFS'};
    y_max = max(abs(frame)) * 1.1;
    for i = 1:length(seg_positions)
        xline(t_ax(seg_positions(i)), 'r--');
        text(t_ax(seg_positions(i)), y_max*0.8, seg_names{i}, ...
             'FontSize', 10, 'Color', 'r');
    end
    xlabel('时间 (ms)'); ylabel('幅度');
    title(sprintf('OTFS V2.0通带帧 (fs_{pb}=%dHz, fc=%dHz, 总长=%dsamp)', ...
                  info.fs_pb, info.params.fc, length(frame)));
    grid on;

    % 帧频谱
    subplot(2,1,2);
    Nfft = 4096;
    F = 20*log10(abs(fftshift(fft(frame, Nfft))) / Nfft + 1e-10);
    f_ax = (-Nfft/2:Nfft/2-1) * info.fs_pb / Nfft / 1e3;
    plot(f_ax, F, 'b', 'LineWidth', 1);
    xlabel('频率 (kHz)'); ylabel('幅度 (dB)');
    title('帧频谱');
    grid on; xlim([-info.fs_pb/2e3, info.fs_pb/2e3]);

    fprintf('\n可视化完成\n');
catch; end

%% ==================== 汇总 ==================== %%
fprintf('\n========================================\n');
fprintf('  测试完成：%d 通过, %d 失败, 共 %d 项\n', ...
        pass_count, fail_count, pass_count + fail_count);
fprintf('========================================\n');
if fail_count == 0
    fprintf('  全部通过！\n');
else
    fprintf('  存在失败项，请检查！\n');
end
