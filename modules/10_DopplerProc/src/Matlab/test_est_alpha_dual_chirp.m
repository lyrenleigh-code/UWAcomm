%% test_est_alpha_dual_chirp.m
% 单元测试：双 LFM（up+down chirp）时延差 α 估计器
% 对应 spec: specs/active/2026-04-20-alpha-estimator-dual-chirp-refinement.md
% 版本：V1.0.0（2026-04-20）

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

fprintf('========================================\n');
fprintf('  est_alpha_dual_chirp 单元测试 V1.0.0\n');
fprintf('========================================\n\n');

%% 1. 参数（与 SC-FDE runner 对齐）
fs    = 48000;
fc    = 12000;
f_lo  = 7950;
f_hi  = 16050;
B     = f_hi - f_lo;
T_pre = 0.03;          % 30 ms 前导持续时间
k     = B / T_pre;     % chirp 斜率 Hz/s

N_lfm = round(T_pre * fs);
t = (0:N_lfm-1) / fs;

% 基带 up-chirp：f(t) = f_lo - fc + k·t
phase_up = 2*pi * ((f_lo - fc) * t + 0.5 * k * t.^2);
LFM_up = exp(1j * phase_up);

% 基带 down-chirp：f(t) = f_hi - fc - k·t
phase_dn = 2*pi * ((f_hi - fc) * t - 0.5 * k * t.^2);
LFM_dn = exp(1j * phase_dn);

guard_samp = 1024;  % SC-FDE runner 实际使用值

% 帧：[LFM_up | guard | LFM_dn | tail_pad]
% 尾部 padding 足够大以容纳 α<0（时间拉伸）的 LFM_dn 溢出
tail_pad = ceil(3e-2 * 2 * (length(LFM_up) + guard_samp + length(LFM_dn))) + 100;
frame = [LFM_up, zeros(1, guard_samp), LFM_dn, zeros(1, tail_pad)];
N_frame = length(frame);

%% 2. 测试用例：α 扫描
alpha_list = [0, 1e-4, -1e-4, 5e-4, -5e-4, 1e-3, -1e-3, 3e-3, -3e-3];
% 边界工况 ±1e-2 / ±3e-2 单独评估（不 assert）
snr_db = 10;
rng(42);

% search_cfg：up 在前导 0~N_lfm+guard；dn 在 N_lfm+guard ~ 2·N_lfm+2·guard
cfg = struct();
cfg.up_start = 1;
cfg.up_end   = N_lfm + guard_samp;
cfg.dn_start = N_lfm + guard_samp + 1;
cfg.dn_end   = N_lfm + guard_samp + N_lfm + guard_samp;
cfg.nominal_delta_samples = N_lfm + guard_samp;  % τ_dn^nom - τ_up^nom
cfg.use_subsample = true;

fprintf('参数：fs=%dHz, fc=%dHz, B=%dHz, T_pre=%.2fms, k=%.2e Hz/s, N_lfm=%d\n', ...
    fs, fc, B, T_pre*1000, k, N_lfm);
fprintf('SNR = %d dB，使用抛物线插值\n\n', snr_db);

%% 3. 跑扫描
results = zeros(numel(alpha_list), 3);   % [alpha_true, alpha_est, rel_err]
pass_count = 0; fail_count = 0;
THRESHOLD_REL = 0.05;  % 5% 相对误差门槛
THRESHOLD_ABS = 5e-5;  % α=0 时绝对误差门槛

fprintf('%-12s %-14s %-12s %-12s %s\n', 'α_true', 'α_est', '|err|', 'rel_err', 'verdict');
fprintf('%s\n', repmat('-', 1, 70));

% 分档判定门槛（按 |α| 量级）
%   |α| < 3e-4     : 绝对门槛（样本分辨率主导）|err| < 5e-5
%   |α| ∈ [3e-4, 3e-3]: 相对门槛 5%
%   |α| ∈ [3e-3, 1e-2]: 相对门槛 30%（边界工况）
%   |α| = 3e-2     : 不强制（单独边界测试记录）

for ai = 1:numel(alpha_list)
    alpha_true = alpha_list(ai);

    % 1) 正确物理模型：rx_bb(t) = frame_bb((1+α)·t) · exp(j·2π·fc·α·t)
    %    前者是时间压缩，后者是下变频后残余 CFO（passband α 载体的下变频残留）
    n_orig  = 0:N_frame-1;
    if alpha_true == 0
        rx_clean = frame;
    else
        n_query = n_orig * (1 + alpha_true);
        rx_compressed = interp1(n_orig, frame, n_query, 'spline', 0);
        t_rx = n_orig / fs;
        rx_clean = rx_compressed .* exp(1j * 2*pi * fc * alpha_true * t_rx);
    end

    % 2) AWGN
    sig_pwr = mean(abs(rx_clean).^2);
    noise_pwr = sig_pwr * 10^(-snr_db/10);
    noise = sqrt(noise_pwr/2) * (randn(size(rx_clean)) + 1j*randn(size(rx_clean)));
    rx = rx_clean + noise;

    % 3) 估计
    [alpha_est, diag_out] = est_alpha_dual_chirp(rx, LFM_up, LFM_dn, fs, fc, k, cfg);

    % 4) 分档验收
    abs_err = abs(alpha_est - alpha_true);
    abs_alpha = abs(alpha_true);
    if abs_alpha < 3e-4
        rel_err = abs_err;  % 小 α 用绝对门槛
        verdict = (abs_err < THRESHOLD_ABS);
    elseif abs_alpha <= 3e-3
        rel_err = abs_err / abs_alpha;
        verdict = (rel_err < THRESHOLD_REL);
    else
        rel_err = abs_err / abs_alpha;
        verdict = (rel_err < 0.30);  % 边界工况放宽
    end
    results(ai, :) = [alpha_true, alpha_est, rel_err];
    if verdict, pass_count = pass_count + 1; mark = '✓';
    else,       fail_count = fail_count + 1; mark = '✗';
    end

    fprintf('%-+12.3e %-+14.3e %-12.2e %-12.4f %s\n', ...
            alpha_true, alpha_est, abs_err, rel_err, mark);
end

fprintf('%s\n', repmat('-', 1, 70));
fprintf('汇总: %d PASS / %d FAIL (共 %d 点)\n', pass_count, fail_count, numel(alpha_list));

%% 4. 边界工况（不 assert，仅记录）
fprintf('\n--- 边界工况（|α|=1e-2/3e-2，仅记录）---\n');
alpha_list_edge = [1e-2, -1e-2, 3e-2, -3e-2];
for ai = 1:numel(alpha_list_edge)
    alpha_true = alpha_list_edge(ai);
    n_orig  = 0:N_frame-1;
    n_query = n_orig * (1 + alpha_true);
    rx_clean = interp1(n_orig, frame, n_query, 'spline', 0);
    sig_pwr = mean(abs(rx_clean).^2);
    noise = sqrt(sig_pwr * 10^(-snr_db/10)/2) * ...
            (randn(size(rx_clean)) + 1j*randn(size(rx_clean)));
    rx = rx_clean + noise;
    % 重生成 rx（含 CFO 项）
    n_orig  = 0:N_frame-1;
    n_query = n_orig * (1 + alpha_true);
    rx_compressed = interp1(n_orig, frame, n_query, 'spline', 0);
    t_rx = n_orig / fs;
    rx_clean = rx_compressed .* exp(1j * 2*pi * fc * alpha_true * t_rx);
    rx = rx_clean + sqrt(mean(abs(rx_clean).^2) * 10^(-snr_db/10)/2) * ...
         (randn(size(rx_clean)) + 1j*randn(size(rx_clean)));
    [alpha_est, ~] = est_alpha_dual_chirp(rx, LFM_up, LFM_dn, fs, fc, k, cfg);
    rel_err = abs(alpha_est - alpha_true) / abs(alpha_true);
    fprintf('α=%+.2e → est=%+.3e, rel_err=%.3f\n', ...
            alpha_true, alpha_est, rel_err);
end

%% 5. 可视化
fig = figure('Visible','on','Position',[100 100 900 400]);
subplot(1,2,1);
plot(results(:,1), results(:,2), 'o-', 'LineWidth', 1.5, 'MarkerSize', 8);
hold on;
a_range = [min(alpha_list), max(alpha_list)];
plot(a_range, a_range, 'k--', 'LineWidth', 1);
hold off; grid on;
xlabel('\alpha_{true}'); ylabel('\alpha_{est}');
title('α 估计（双 LFM 时延差法）');
legend({'estimator','ideal y=x'}, 'Location','best');

subplot(1,2,2);
plot(abs(results(:,1)), results(:,3), 's-', 'LineWidth', 1.5, 'MarkerSize', 8);
set(gca,'XScale','log','YScale','log');
grid on;
xlabel('|\alpha_{true}|'); ylabel('相对误差 |err|/|α|');
title('估计精度');
yline(0.05, 'r--', '5% 门槛');

if fail_count > 0
    error('test_est_alpha_dual_chirp:HasFailures', '%d 项失败', fail_count);
end
fprintf('\n=== 全部测试通过 ===\n');
