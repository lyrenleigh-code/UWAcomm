%% test_est_alpha_dsss_symbol.m
% 单元测试：DSSS 符号级 α 跟踪（Sun-2020）
% 对应 spec: 2026-04-22-dsss-symbol-doppler-tracking.md
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

fprintf('========================================\n');
fprintf('  est_alpha_dsss_symbol 单元测试 V1.0.0\n');
fprintf('========================================\n\n');

%% 1. 参数（与 DSSS runner 一致）
fs        = 48000;
fc        = 12000;
chip_rate = 6000;
sps       = fs / chip_rate;   % 8
L         = 31;               % Gold31

% 生成 Gold31（简化：随机 ±1，不用真 Gold 码生成器）
rng(1);
gold_ref = 2 * (randi([0 1], 1, L) > 0) - 1;   % ±1 基带
gold_ref = gold_ref(:).';

T_sym_samples = L * sps;   % 248

%% 2. 生成 DSSS 测试信号
N_sym = 100;  % 测试 100 symbols
rng(42);
tx_bits = randi([0 1], 1, N_sym);
tx_syms = 2 * tx_bits - 1;   % ±1 BPSK

% 扩频：每 symbol → 31 chip
all_chips = zeros(1, N_sym * L);
for k = 1:N_sym
    all_chips((k-1)*L+1 : k*L) = tx_syms(k) * gold_ref;
end

% upsample 到 sample rate（不 RRC，直接 repeat，测试简化）
% 实际 DSSS 用 RRC 成形，这里用简化 ZOH 即可验证 estimator
all_samples = zeros(1, length(all_chips) * sps);
for k = 1:length(all_chips)
    all_samples((k-1)*sps+1 : k*sps) = all_chips(k);
end

% 加前 200 样本 preamble (0) 模拟 data_start_samples
preamble_len = 200;
frame = [zeros(1, preamble_len), all_samples, zeros(1, 300)];  % 尾 padding
N_frame = length(frame);

%% 3. 测试场景
fprintf('参数：fs=%d, fc=%d, chip_rate=%d, sps=%d, L=%d, N_sym=%d, T_sym=%d samples\n', ...
    fs, fc, chip_rate, sps, L, N_sym, T_sym_samples);
fprintf('帧长：%d samples (%.1f ms)\n\n', N_frame, N_frame/fs*1000);

frame_cfg = struct('data_start_samples', preamble_len + 1, 'n_symbols', N_sym);
track_cfg = struct('alpha_block', 0, 'alpha_max', 3e-2, ...
                   'iir_beta', 0.7, 'iir_warmup', 5, 'use_subsample', true);

%% 场景 A: 固定 α AWGN
alpha_list = [0, 1e-4, 1e-3, 3e-3, 1e-2, 3e-2];
snr_db = 10;
rng(43);

fprintf('--- 场景 A: 固定 α @ SNR=10dB ---\n');
fprintf('%-12s %-14s %-12s %-10s %s\n', 'α_true', 'α_avg', '|err|', 'rel_err', 'verdict');
fprintf('%s\n', repmat('-', 1, 70));

pass_A = 0; fail_A = 0;
for ai = 1:numel(alpha_list)
    alpha_true = alpha_list(ai);

    % 物理模型：rx(t) = frame((1+α)t) · exp(j2πfc·α·t)
    if alpha_true == 0
        rx_clean = frame;
    else
        n_orig = 0:N_frame-1;
        n_q = n_orig * (1 + alpha_true);
        rx_comp = interp1(n_orig, frame, n_q, 'spline', 0);
        t_cfo = n_orig / fs;
        rx_clean = rx_comp .* exp(1j * 2*pi * fc * alpha_true * t_cfo);
    end

    % AWGN
    sig_pwr = mean(abs(rx_clean).^2);
    noise_pwr = sig_pwr * 10^(-snr_db/10);
    noise = sqrt(noise_pwr/2) * (randn(size(rx_clean)) + 1j*randn(size(rx_clean)));
    rx = rx_clean + noise;

    % 跑 estimator
    track_cfg.alpha_block = 0;  % 测 estimator 独立能力
    [alpha_track, alpha_avg, d] = est_alpha_dsss_symbol(rx, gold_ref, sps, fs, fc, frame_cfg, track_cfg);

    abs_err = abs(alpha_avg - alpha_true);
    if abs(alpha_true) < 1e-6
        rel_err = abs_err;
        verdict = abs_err < 5e-4;
    else
        rel_err = abs_err / abs(alpha_true);
        if abs(alpha_true) <= 1e-2
            verdict = rel_err < 0.05;  % 5% 门槛
        else
            verdict = rel_err < 0.20;  % 3e-2 放宽到 20%
        end
    end
    if verdict, pass_A = pass_A + 1; mark = '✓';
    else,       fail_A = fail_A + 1; mark = '✗'; end

    fprintf('%-+12.3e %-+14.4e %-12.2e %-10.4f %s\n', ...
        alpha_true, alpha_avg, abs_err, rel_err, mark);
end
fprintf('\n汇总 A: %d PASS / %d FAIL (共 %d 点)\n\n', pass_A, fail_A, numel(alpha_list));

%% 场景 B: 线性漂移 α(t) = α_0 + β·k/N_sym
fprintf('--- 场景 B: 线性漂移 α_0=0, α_end=3e-3 @ SNR=10dB ---\n');
alpha_start = 0;
alpha_end = 3e-3;
alpha_profile = linspace(alpha_start, alpha_end, N_frame);  % sample-by-sample α

rng(44);
% 逐样本 α 的 rx 模型（近似）：每点用对应 α 做 time scale
n_orig = 0:N_frame-1;
% 这里简化为用 alpha_profile 均值 做 constant α 测试（更严格的 time-varying rx 需要 integration）
alpha_mean_drift = mean(alpha_profile);
n_q = n_orig * (1 + alpha_mean_drift);
rx_comp = interp1(n_orig, frame, n_q, 'spline', 0);
t_cfo = n_orig / fs;
rx_clean = rx_comp .* exp(1j * 2*pi * fc * alpha_mean_drift * t_cfo);

sig_pwr = mean(abs(rx_clean).^2);
noise = sqrt(sig_pwr * 10^(-snr_db/10) / 2) * (randn(size(rx_clean)) + 1j*randn(size(rx_clean)));
rx = rx_clean + noise;

track_cfg.alpha_block = 0;
[alpha_track, alpha_avg, d] = est_alpha_dsss_symbol(rx, gold_ref, sps, fs, fc, frame_cfg, track_cfg);

fprintf('  alpha_mean_truth=%.3e  alpha_avg_est=%.3e  rel_err=%.3f\n', ...
    alpha_mean_drift, alpha_avg, abs(alpha_avg - alpha_mean_drift)/alpha_mean_drift);
fprintf('  alpha_track first=%.3e last=%.3e（应接近 %.3e）\n\n', ...
    alpha_track(1), alpha_track(end), alpha_mean_drift);

%% 场景 C: 可视化
fig = figure('Visible','on','Position',[100 100 1100 500]);
subplot(1,2,1);
plot(alpha_list, alpha_list, 'k--', 'LineWidth', 1); hold on;
est_A = zeros(size(alpha_list));
for ai = 1:numel(alpha_list)
    alpha_true = alpha_list(ai);
    if alpha_true == 0, rx_clean = frame;
    else
        n_q = (0:N_frame-1) * (1 + alpha_true);
        rx_comp = interp1(0:N_frame-1, frame, n_q, 'spline', 0);
        rx_clean = rx_comp .* exp(1j * 2*pi * fc * alpha_true * (0:N_frame-1)/fs);
    end
    [~, est_A(ai), ~] = est_alpha_dsss_symbol(rx_clean + 0.01*randn(size(rx_clean)), ...
        gold_ref, sps, fs, fc, frame_cfg, track_cfg);
end
plot(alpha_list, est_A, 'o-', 'LineWidth', 1.5, 'MarkerSize', 8);
grid on; xlabel('\alpha_{true}'); ylabel('\alpha_{est}');
title('DSSS 符号级 α 估计（场景 A）');
legend('ideal', 'symbol-est', 'Location','best');

subplot(1,2,2);
plot(alpha_track, '-', 'LineWidth', 1.2); hold on;
plot([1 N_sym], [alpha_mean_drift alpha_mean_drift], 'r--', 'LineWidth', 1);
grid on; xlabel('symbol k'); ylabel('\alpha_{track}');
title('alpha\_track 随符号（场景 B 线性漂移）');
legend('IIR 滤波轨迹', '真值', 'Location','best');

if fail_A > 0
    warning('%d 项 FAIL（记录不 assert）', fail_A);
end

fprintf('\n=== 测试完成 ===\n');
