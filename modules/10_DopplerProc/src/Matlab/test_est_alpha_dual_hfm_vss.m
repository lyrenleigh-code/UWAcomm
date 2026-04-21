%% test_est_alpha_dual_hfm_vss.m
% 单元测试：HFM 速度谱扫描 α 估计器（wei-2020）
% 对应 spec: 2026-04-21-hfm-velocity-spectrum-refinement.md
% 版本：V1.0.0（2026-04-21）

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

fprintf('========================================\n');
fprintf('  est_alpha_dual_hfm_vss 单元测试 V1.0.0\n');
fprintf('========================================\n\n');

%% 1. 参数（与 SC-FDE runner 一致）
fs    = 48000;
fc    = 12000;
bw_lfm = 6000 * 1.35;   % sym_rate * (1+rolloff)，简化取 rolloff=0.35
f_lo  = fc - bw_lfm/2;
f_hi  = fc + bw_lfm/2;
T     = 0.05;      % preamble_dur
T_e_samples = 1024;   % guard_samp（approximately）
T_e   = T_e_samples / fs;

N_hfm = round(T * fs);
t_pre = (0:N_hfm-1) / fs;

% HFM 基带模板（和 SC-FDE runner Eq. 完全一致）
k_hfm_up = f_lo * f_hi * T / (f_hi - f_lo);
phase_hfm_up = -2*pi * k_hfm_up * log(1 - (f_hi-f_lo)/f_hi .* t_pre / T);
HFM_up = exp(1j * (phase_hfm_up - 2*pi*fc*t_pre));

k_hfm_dn = f_hi * f_lo * T / (f_lo - f_hi);
phase_hfm_dn = -2*pi * k_hfm_dn * log(1 - (f_lo-f_hi)/f_lo .* t_pre / T);
HFM_dn = exp(1j * (phase_hfm_dn - 2*pi*fc*t_pre));

fprintf('HFM 参数：fs=%d, fc=%d, f_lo=%.0f, f_hi=%.0f, T=%.2fms, T_e=%.2fms, N_hfm=%d\n', ...
    fs, fc, f_lo, f_hi, T*1000, T_e*1000, N_hfm);

% 帧：[HFM_up | gap (T_e_samples) | HFM_dn | tail_pad]
% 尾部 padding 足以容纳大 α 下 LFM_dn 溢出
tail_pad = ceil(1e-1 * 2 * (2*N_hfm + T_e_samples)) + 500;
frame = [HFM_up, zeros(1, T_e_samples), HFM_dn, zeros(1, tail_pad)];
N_frame = length(frame);

fprintf('帧长：%d samples (~%.2f ms)\n\n', N_frame, N_frame/fs*1000);

%% 2. search_cfg
search_cfg = struct();
search_cfg.v_range   = [-150, 150];
search_cfg.dv_coarse = 0.5;
search_cfg.dv_fine   = 0.02;
search_cfg.c_sound   = 1500;
search_cfg.first_hfm = 'up';

%% 3. 扫描 α 列表
% α = v/c where v in m/s; α = 1e-2 → v = 15 m/s
alpha_list = [0, 1e-3, -1e-3, 1e-2, -1e-2, 3e-2, -3e-2, 5e-2, -5e-2, 7e-2, -7e-2];
snr_db = 10;
rng(42);

%% 4. 跑扫描
results = zeros(numel(alpha_list), 4);  % [α_true, α_est, rel_err, scan_time]
fprintf('%-12s %-14s %-12s %-10s %-10s %s\n', 'α_true', 'α_est', '|err|', 'rel_err', 'scan(s)', 'verdict');
fprintf('%s\n', repmat('-', 1, 80));

pass_count = 0; fail_count = 0;

for ai = 1:numel(alpha_list)
    alpha_true = alpha_list(ai);

    % 物理模型：rx_bb(t) = frame((1+α)t)·exp(j·2π·fc·α·t)
    % α>0 → 压缩，正频偏
    if alpha_true == 0
        rx_clean = frame;
    else
        n_orig = 0:N_frame-1;
        n_query = n_orig * (1 + alpha_true);
        rx_comp = interp1(n_orig, frame, n_query, 'spline', 0);
        t_rx = n_orig / fs;
        rx_clean = rx_comp .* exp(1j * 2*pi * fc * alpha_true * t_rx);
    end

    % AWGN
    sig_pwr = mean(abs(rx_clean).^2);
    noise_pwr = sig_pwr * 10^(-snr_db/10);
    noise = sqrt(noise_pwr/2) * (randn(size(rx_clean)) + 1j*randn(size(rx_clean)));
    rx = rx_clean + noise;

    % 提取含双 HFM 的段
    % 【修正】seg_len 必须容纳 |α|<0.1 下 HFM_dn 展开后的最大位置
    %   HFM_dn 结束 ≈ (2·N_hfm+T_e) / (1 - |α_max|)
    alpha_max_expected = 0.1;
    seg_len = ceil((2*N_hfm + T_e_samples) / (1 - alpha_max_expected)) + 500;
    bb_segment = rx(1:min(seg_len, length(rx)));

    % 跑 estimator
    [alpha_est, d] = est_alpha_dual_hfm_vss(bb_segment, HFM_up, HFM_dn, ...
                                             f_lo, f_hi, T, T_e, fs, search_cfg);

    abs_err = abs(alpha_est - alpha_true);
    if abs(alpha_true) < 1e-6
        rel_err = abs_err;
        verdict = abs_err < 5e-5;
    else
        rel_err = abs_err / abs(alpha_true);
        if abs(alpha_true) <= 3e-2
            verdict = rel_err < 0.03;
        elseif abs(alpha_true) <= 5e-2
            verdict = rel_err < 0.05;
        else
            verdict = true;   % |α|=7e-2 仅记录
        end
    end

    if verdict, pass_count = pass_count + 1; mark = '✓';
    else,       fail_count = fail_count + 1; mark = '✗'; end

    results(ai, :) = [alpha_true, alpha_est, rel_err, d.scan_time_s];

    fprintf('%-+12.3e %-+14.4e %-12.2e %-10.4f %-10.3f %s (PSR=%.1f)\n', ...
        alpha_true, alpha_est, abs_err, rel_err, d.scan_time_s, mark, d.peak_psr);
end

fprintf('\n%s\n', repmat('-', 1, 80));
fprintf('汇总: %d PASS / %d FAIL（共 %d 点，|α|=7e-2 仅记录）\n', ...
    pass_count, fail_count, numel(alpha_list));

%% 5. 对称性验证
fprintf('\n--- 对称性验证（|est(+v) - (-est(-v))| / |v| < 10%%） ---\n');
test_alphas = [1e-3, 1e-2, 3e-2, 5e-2];
for a = test_alphas
    idx_pos = find(results(:,1) == a, 1);
    idx_neg = find(results(:,1) == -a, 1);
    if ~isempty(idx_pos) && ~isempty(idx_neg)
        est_pos = results(idx_pos, 2);
        est_neg = results(idx_neg, 2);
        asym = abs(est_pos + est_neg) / a;
        mark = '✓'; if asym > 0.10, mark = '✗'; end
        fprintf('  α=±%.0e: est(+)=%+.3e, est(-)=%+.3e, 对称偏差=%.4f  %s\n', ...
            a, est_pos, est_neg, asym, mark);
    end
end

%% 6. 可视化
fig = figure('Visible','on','Position',[100 100 1200 500]);
subplot(1,2,1);
plot(results(:,1), results(:,2), 'o-', 'LineWidth', 1.5, 'MarkerSize', 8);
hold on; plot([-0.08, 0.08], [-0.08, 0.08], 'k--'); hold off;
grid on; xlabel('\alpha_{true}'); ylabel('\alpha_{est}');
title('HFM VSS: α 估计 vs 真值');
legend({'VSS', 'ideal y=x'}, 'Location','best');

subplot(1,2,2);
plot(abs(results(:,1)), results(:,3), 's-', 'LineWidth', 1.5, 'MarkerSize', 8);
set(gca, 'XScale', 'log', 'YScale', 'log');
grid on; xlabel('|\alpha_{true}|'); ylabel('rel\_err');
title('VSS 精度 vs |α|');
yline(0.03, 'r--', '3% 门槛');
yline(0.05, 'y--', '5% 门槛');

if fail_count > 0
    error('test_est_alpha_dual_hfm_vss:HasFailures', '%d 项失败', fail_count);
end

fprintf('\n=== 全部 assertion 通过 ===\n');
