%% test_est_alpha_dual_hfm_real.m
% 验证：用 sync_dual_hfm 在真实 Doppler rx_pb 上直接估 α
% 思路：HFM 是 Doppler 不变信号 — 压缩只造成时移不改频率结构 —
%       双 HFM 峰位差直接给 α，无 range-Doppler 耦合歧义
%
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
modules_root = fileparts(fileparts(fileparts(this_dir)));   % .../modules
addpath(fullfile(modules_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(modules_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform', 'src', 'Matlab'));

fprintf('========================================\n');
fprintf('  双 HFM α 估计（真实 Doppler rx_pb）V1.0\n');
fprintf('========================================\n\n');

%% ========== 信号参数（与 SC-FDE runner 一致）==========
fs       = 48000;
fc       = 12000;
f_lo_hfm = 7950;
f_hi_hfm = 16050;
T_hfm    = 0.03;
B_hfm    = f_hi_hfm - f_lo_hfm;

% HFM 偏置灵敏度 S = T·f̄/B，其中 f̄ = (f_lo+f_hi)/2
f_bar    = (f_lo_hfm + f_hi_hfm) / 2;
S_bias   = T_hfm * f_bar / B_hfm;

fprintf('HFM 参数：T=%.3fs, B=%.0fHz, f_bar=%.0fHz, S_bias=%.4fs\n', ...
        T_hfm, B_hfm, f_bar, S_bias);

%% ========== 生成 HFM 模板（通带实信号）==========
hfm_pos_pb = gen_hfm(fs, T_hfm, f_lo_hfm, f_hi_hfm);   % 正扫频 HFM+
hfm_neg_pb = gen_hfm(fs, T_hfm, f_hi_hfm, f_lo_hfm);   % 负扫频 HFM-
N_hfm = length(hfm_pos_pb);

%% ========== TX 基带帧：[HFM+ | guard | HFM- | guard | tail] ==========
% 基带模板（用于生成 TX 复基带帧）
t_hfm = (0:N_hfm-1) / fs;
hfm_pos_bb = hfm_pos_pb .* exp(-1j * 2*pi * fc * t_hfm);   % 下变频到基带
hfm_neg_bb = hfm_neg_pb .* exp(-1j * 2*pi * fc * t_hfm);

guard_samp    = 1024;
tail_samp     = 2000;
preamble_samp = 500;                          % 给 HFM+ peak 留早移空间（α>0 时 peak 会左移）
frame_bb = [zeros(1, preamble_samp), hfm_pos_bb, zeros(1, guard_samp), ...
            hfm_neg_bb, zeros(1, tail_samp)];

% 名义位置
tau_pos_nom = preamble_samp + 1;                               % HFM+ 起始位置
tau_neg_nom = preamble_samp + N_hfm + guard_samp + 1;          % HFM- 起始位置
frame_gap   = guard_samp;                                      % HFM+ 尾到 HFM- 头的间隔

fprintf('\n帧参数：N_hfm=%d, guard=%d, frame_gap=%d\n', N_hfm, guard_samp, frame_gap);
fprintf('名义 tau_pos=%d, tau_neg=%d\n\n', tau_pos_nom, tau_neg_nom);

%% ========== 扫描 α ==========
alpha_list = [1e-4, -1e-4, 5e-4, -5e-4, 1e-3, -1e-3, ...
              3e-3, -3e-3, 1e-2, -1e-2, 1.7e-2, -1.7e-2, ...
              3e-2, -3e-2, 5e-2, -5e-2];

paths_single = struct('delays', 0, 'gains', 1);
tv_off = struct('enable', false);

fprintf('%-10s | %-12s | %-12s | %-10s | %-10s | %-8s | %-8s\n', ...
        'α_true', 'single α', 'iter α (×2)', '|err single|', '|err iter|', 'rel(s)', 'rel(iter)');
fprintf('%s\n', repmat('-', 1, 95));

errors = zeros(1, length(alpha_list));

for a_i = 1:length(alpha_list)
    alpha_true = alpha_list(a_i);

    %% 生成真实 Doppler rx_pb
    [rx_bb, ~] = gen_doppler_channel(frame_bb, fs, alpha_true, paths_single, Inf, tv_off, fc);
    N_rx = length(rx_bb);
    t_rx = (0:N_rx-1) / fs;
    rx_pb = real(rx_bb .* exp(1j * 2*pi * fc * t_rx));

    %% 双 HFM 同步估计 α
    params = struct();
    params.S_bias      = S_bias;
    params.alpha_max   = 0.1;
    params.threshold   = 0.3;
    params.search_win  = min(length(rx_pb), preamble_samp + N_hfm * 2 + guard_samp);
    % HFM+ 搜索范围：包含 preamble + HFM+，不超 HFM+ 尾 + guard 中部
    params.sep_samples = preamble_samp + round(N_hfm * 0.9);
    params.frame_gap   = guard_samp;
    % 注：tau_est 返回 tau_pos_nom 附近（通常第一个 preamble zero 之后），
    %     estimator α 公式基于 τ_neg-τ_pos，与 preamble 长度无关

    % 单次
    [~, alpha_single, ~, info] = sync_dual_hfm(rx_pb, hfm_pos_pb, hfm_neg_pb, fs, params);

    % 迭代（V1.1：max 3 + 自适应早停 + 阻尼）
    opts_iter = struct('max_iter', 3, 'stop_thres', 1e-4, 'damping', 0.9);
    [alpha_iter, diag_iter] = est_alpha_dual_hfm_iter(rx_pb, hfm_pos_pb, hfm_neg_pb, ...
                                                       fs, fc, params, opts_iter);

    err_single = alpha_single - alpha_true;
    err_iter   = alpha_iter - alpha_true;
    errors(a_i) = err_iter;
    if abs(alpha_true) > 1e-12
        rel_err_s = abs(err_single) / abs(alpha_true) * 100;
        rel_err_i = abs(err_iter)   / abs(alpha_true) * 100;
        fprintf('%-+10.2e | %-+12.4e | %-+12.4e | %-10.3e | %-10.3e | %-8.2f%% | %-8.2f%%\n', ...
                alpha_true, alpha_single, alpha_iter, abs(err_single), abs(err_iter), rel_err_s, rel_err_i);
    else
        fprintf('%-+10.2e | %-+12.4e | %-+12.4e | %-10.3e | %-10.3e | (α=0)    | (α=0)\n', ...
                alpha_true, alpha_single, alpha_iter, abs(err_single), abs(err_iter));
    end
end

fprintf('\n--- 误差统计 ---\n');
fprintf('|α|=1e-4 两点 mean |err| = %.3e\n', mean(abs(errors(1:2))));
fprintf('|α|=1e-3 两点 mean |err| = %.3e\n', mean(abs(errors(5:6))));
fprintf('|α|=1e-2 两点 mean |err| = %.3e\n', mean(abs(errors(9:10))));
fprintf('|α|=1.7e-2 两点 mean |err| = %.3e\n', mean(abs(errors(11:12))));
fprintf('|α|=3e-2 两点 mean |err| = %.3e\n', mean(abs(errors(13:14))));

fprintf('\n========================================\n');
fprintf('  完成\n');
fprintf('========================================\n');
