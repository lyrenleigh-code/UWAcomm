%% test_est_alpha_cascade.m
% HFM + LFM 两级 α 估计（真实 Doppler 鲁棒）
% Stage 1: 双 HFM 粗估 → α_hfm（1-5% 相对误差，大范围鲁棒）
% Stage 2: 通带 resample 用 α_hfm 补偿 → 下变频 → 残余 Doppler ~ 2e-4
% Stage 3: 基带双 LFM 精估残余 α_delta（小 α 下 est_alpha_dual_chirp 公式线性）
% 结果：α_total = (1+α_hfm)·(1+α_delta) - 1
%
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
modules_root = fileparts(fileparts(fileparts(this_dir)));
addpath(fullfile(modules_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(modules_root, '08_Sync', 'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform', 'src', 'Matlab'));

fprintf('========================================\n');
fprintf('  HFM+LFM Cascade α 估计 V1.0\n');
fprintf('========================================\n\n');

%% ========== 信号参数 ==========
fs    = 48000;
fc    = 12000;
f_lo  = 7950;
f_hi  = 16050;
T_pre = 0.03;                % HFM / LFM 持续时间
B     = f_hi - f_lo;
k_lfm = B / T_pre;           % LFM chirp rate
N_pre = round(T_pre * fs);
t_pre = (0:N_pre-1) / fs;

% HFM 偏置灵敏度
f_bar  = (f_lo + f_hi) / 2;
S_bias = T_pre * f_bar / B;

%% ========== 生成 HFM / LFM 模板 ==========
% HFM (passband)
hfm_up_pb = gen_hfm(fs, T_pre, f_lo, f_hi);   % HFM+
hfm_dn_pb = gen_hfm(fs, T_pre, f_hi, f_lo);   % HFM-

% LFM (baseband complex，用于 est_alpha_dual_chirp)
LFM_up_bb = exp(1j * 2*pi * ((f_lo - fc) * t_pre + 0.5 * k_lfm * t_pre.^2));
LFM_dn_bb = exp(1j * 2*pi * ((f_hi - fc) * t_pre - 0.5 * k_lfm * t_pre.^2));

%% ========== TX 帧：[preamble | HFM+ | g | HFM- | g | LFM+ | g | LFM- | tail] ==========
guard_samp    = 1024;
preamble_samp = 500;
tail_samp     = 2000;

% HFM 基带分量（用于构造 TX 基带帧）
hfm_up_bb = hilbert(hfm_up_pb) .* exp(-1j*2*pi*fc*t_pre);   % 用 hilbert 取解析信号再下变频
hfm_dn_bb = hilbert(hfm_dn_pb) .* exp(-1j*2*pi*fc*t_pre);

frame_bb = [zeros(1, preamble_samp), ...
            hfm_up_bb, zeros(1, guard_samp), ...
            hfm_dn_bb, zeros(1, guard_samp), ...
            LFM_up_bb, zeros(1, guard_samp), ...
            LFM_dn_bb, zeros(1, tail_samp)];

% nominal 位置
tau_hfm_up_nom = preamble_samp + 1;
tau_hfm_dn_nom = tau_hfm_up_nom + N_pre + guard_samp;
tau_lfm_up_nom = tau_hfm_dn_nom + N_pre + guard_samp;
tau_lfm_dn_nom = tau_lfm_up_nom + N_pre + guard_samp;

fprintf('帧结构：preamble=%d, N_pre=%d, guard=%d\n', preamble_samp, N_pre, guard_samp);
fprintf('  τ_hfm_up=%d, τ_hfm_dn=%d, τ_lfm_up=%d, τ_lfm_dn=%d\n\n', ...
        tau_hfm_up_nom, tau_hfm_dn_nom, tau_lfm_up_nom, tau_lfm_dn_nom);

%% ========== 扫描 α ==========
alpha_list = [5e-4, -5e-4, 1e-3, -1e-3, 3e-3, -3e-3, ...
              1e-2, -1e-2, 1.7e-2, -1.7e-2, ...
              3e-2, -3e-2, 5e-2, -5e-2];

paths_single = struct('delays', 0, 'gains', 1);
tv_off = struct('enable', false);

fprintf('%-10s | %-12s | %-12s | %-12s | %-11s | %-11s | %-s\n', ...
        'α_true', 'α_hfm', 'α_lfm_res', 'α_total', '|err hfm|', '|err tot|', 'tot err %');
fprintf('%s\n', repmat('-', 1, 95));

err_totals = zeros(1, length(alpha_list));
err_hfms = zeros(1, length(alpha_list));

for a_i = 1:length(alpha_list)
    alpha_true = alpha_list(a_i);

    %% 生成真实 Doppler rx_pb
    [rx_bb, ~] = gen_doppler_channel(frame_bb, fs, alpha_true, paths_single, Inf, tv_off, fc);
    N_rx = length(rx_bb);
    t_rx = (0:N_rx-1) / fs;
    rx_pb = real(rx_bb .* exp(1j * 2*pi * fc * t_rx));

    %% Stage 1：HFM 粗估
    hfm_params = struct();
    hfm_params.S_bias      = S_bias;
    hfm_params.alpha_max   = 0.1;
    hfm_params.threshold   = 0.3;
    hfm_params.search_win  = min(length(rx_pb), preamble_samp + N_pre*2 + guard_samp);
    hfm_params.sep_samples = preamble_samp + round(N_pre * 0.9);
    hfm_params.frame_gap   = guard_samp;

    [~, alpha_hfm, ~, ~] = sync_dual_hfm(rx_pb, hfm_up_pb, hfm_dn_pb, fs, hfm_params);

    %% Stage 2：通带 resample 补偿
    [p_num, q_den] = rat(1 + alpha_hfm, 1e-7);
    rx_pb_comp = poly_resample(rx_pb, p_num, q_den);

    %% Stage 3：下变频到基带
    [bb_comp, ~] = downconvert(rx_pb_comp, fs, fc, B/2 + 500);

    %% Stage 4：LFM 精估残余
    cfg_lfm = struct();
    cfg_lfm.up_start = max(1, tau_lfm_up_nom - 200);
    cfg_lfm.up_end   = min(length(bb_comp), tau_lfm_up_nom + N_pre + 200);
    cfg_lfm.dn_start = max(1, tau_lfm_dn_nom - 200);
    cfg_lfm.dn_end   = min(length(bb_comp), tau_lfm_dn_nom + N_pre + 200);
    cfg_lfm.nominal_delta_samples = tau_lfm_dn_nom - tau_lfm_up_nom;   % 实际是 N_pre + guard
    cfg_lfm.use_subsample = true;

    try
        [alpha_lfm_raw, ~] = est_alpha_dual_chirp(bb_comp, LFM_up_bb, LFM_dn_bb, ...
                                                    fs, fc, k_lfm, cfg_lfm);
        % 注：HFM 补偿后残余小 α 下，est_alpha_dual_chirp 输出直接跟踪残余方向
        %     不同于全 α 真实 Doppler 的 -1.2 倍系统偏差
        alpha_lfm_res = +alpha_lfm_raw;   % 不反号
    catch ME
        alpha_lfm_res = 0;
    end

    %% 合成总 α
    alpha_total = (1 + alpha_hfm) * (1 + alpha_lfm_res) - 1;

    %% 报告
    err_hfm   = alpha_hfm   - alpha_true;
    err_total = alpha_total - alpha_true;
    err_hfms(a_i)   = abs(err_hfm);
    err_totals(a_i) = abs(err_total);

    if abs(alpha_true) > 1e-12
        rel = abs(err_total)/abs(alpha_true)*100;
        fprintf('%-+10.2e | %-+12.4e | %-+12.4e | %-+12.4e | %-11.3e | %-11.3e | %-8.3f%%\n', ...
                alpha_true, alpha_hfm, alpha_lfm_res, alpha_total, ...
                abs(err_hfm), abs(err_total), rel);
    else
        fprintf('%-+10.2e | %-+12.4e | %-+12.4e | %-+12.4e | %-11.3e | %-11.3e | (α=0)\n', ...
                alpha_true, alpha_hfm, alpha_lfm_res, alpha_total, ...
                abs(err_hfm), abs(err_total));
    end
end

fprintf('\n--- 残余 α 统计 ---\n');
fprintf('|α|≤3e-3：mean |err_tot|  = %.3e\n', mean(err_totals(1:6)));
fprintf('|α|=1e-2：mean |err_tot|  = %.3e\n', mean(err_totals(7:8)));
fprintf('|α|=1.7e-2 (50 节): mean |err_tot| = %.3e（目标 <1e-4）\n', mean(err_totals(9:10)));
fprintf('|α|=3e-2：mean |err_tot|  = %.3e\n', mean(err_totals(11:12)));
fprintf('|α|=5e-2：mean |err_tot|  = %.3e\n', mean(err_totals(13:14)));

fprintf('\n========================================\n');
fprintf('  完成\n');
fprintf('========================================\n');
