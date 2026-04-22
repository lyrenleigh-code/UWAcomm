%% test_est_alpha_passband_chirp.m
% 单元测试：通带 LFM 匹配滤波 α 估计器（用于真实 Doppler 场景）
% 验证：生成已知 α 的 rx_pb（通过 gen_doppler_channel + upconvert），
%       用 est_alpha_passband_chirp 估计 α，对比 α_true
%
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);
addpath(fullfile(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))))), ...
                  '09_Waveform', 'src', 'Matlab'));

fprintf('========================================\n');
fprintf('  est_alpha_passband_chirp 验证测试 V1.0\n');
fprintf('========================================\n\n');

%% ========== 信号参数 ==========
fs    = 48000;
fc    = 12000;
f_lo  = 7950;
f_hi  = 16050;
T_lfm = 0.03;            % 30 ms
B     = f_hi - f_lo;
k     = B / T_lfm;       % chirp rate = 270 kHz/s
N_lfm = round(T_lfm * fs);
t_lfm = (0:N_lfm-1) / fs;

%% ========== TX 基带 LFM 模板（与 SC-FDE runner 一致）==========
% 基带 up-chirp：实际频率 f_lo~f_hi，基带频率 (f_lo-fc)~(f_hi-fc)
phase_up = 2*pi * ((f_lo - fc) * t_lfm + 0.5 * k * t_lfm.^2);
LFM_up_bb = exp(1j * phase_up);

% 基带 dn-chirp：实际 f_hi→f_lo
phase_dn = 2*pi * ((f_hi - fc) * t_lfm - 0.5 * k * t_lfm.^2);
LFM_dn_bb = exp(1j * phase_dn);

% 通带模板（upconvert 到 fc）
LFM_up_pb = real(LFM_up_bb .* exp(1j * 2*pi * fc * t_lfm));
LFM_dn_pb = real(LFM_dn_bb .* exp(1j * 2*pi * fc * t_lfm));

%% ========== 构造 TX 基带帧（带 LFM_up + guard + LFM_dn）==========
guard_samp = 1024;
N_preamble = 0;   % 本测试跳过 HFM
% 基带帧：[LFM_up_bb | guard | LFM_dn_bb | tail]
tail = 2000;
frame_bb = [LFM_up_bb, zeros(1, guard_samp), LFM_dn_bb, zeros(1, tail)];

% nominal peak positions（帧内样本坐标）：LFM 匹配滤波 peak 在 chirp 结束处
tau_up_nom = length(LFM_up_bb);                                      % = N_lfm
tau_dn_nom = tau_up_nom + guard_samp + length(LFM_dn_bb);            % = 2·N_lfm + guard
dtau_nom_samp = tau_dn_nom - tau_up_nom;                             % = N_lfm + guard_samp

fprintf('帧参数：\n');
fprintf('  fs=%d, fc=%d, N_lfm=%d, guard=%d\n', fs, fc, N_lfm, guard_samp);
fprintf('  tau_up_nom=%d, tau_dn_nom=%d, dtau_nom=%d (samples)\n', ...
        tau_up_nom, tau_dn_nom, dtau_nom_samp);
fprintf('  chirp rate k=%.1f Hz/s, 2·fc/k=%.4f s\n\n', k, 2*fc/k);

%% ========== 扫描 α ==========
alpha_list = [1e-4, -1e-4, 5e-4, -5e-4, 1e-3, -1e-3, ...
              3e-3, -3e-3, 1e-2, -1e-2, 1.7e-2, -1.7e-2, ...
              3e-2, -3e-2, 5e-2, -5e-2];

paths_single = struct('delays', 0, 'gains', 1);  % 单径，排除多径扰动
tv_off = struct('enable', false);

fprintf('%-10s | %-14s | %-14s | %-12s | %-s\n', ...
        'α_true', 'α_est', '|err|', 'rel err', 'tau_up→dn');
fprintf('%s\n', repmat('-', 1, 80));

for a_i = 1:length(alpha_list)
    alpha_true = alpha_list(a_i);

    %% 生成真实 Doppler rx_pb（单径，SNR=Inf 无噪声）
    [rx_bb, ci] = gen_doppler_channel(frame_bb, fs, alpha_true, paths_single, Inf, tv_off, fc);
    N_rx = length(rx_bb);
    t_rx = (0:N_rx-1) / fs;
    rx_pb = real(rx_bb .* exp(1j * 2*pi * fc * t_rx));

    %% 估计 α
    cfg = struct();
    cfg.up_start = 1;
    cfg.up_end   = min(length(rx_pb), tau_up_nom + 500);
    cfg.dn_start = max(1, tau_dn_nom - 500);
    cfg.dn_end   = min(length(rx_pb), tau_dn_nom + 500);
    cfg.nominal_delta_samples = dtau_nom_samp;
    cfg.tau_up_nom = tau_up_nom;
    cfg.tau_dn_nom = tau_dn_nom;
    cfg.use_subsample = true;

    [alpha_est, diag_out] = est_alpha_passband_chirp(rx_pb, LFM_up_pb, LFM_dn_pb, ...
                                                      fs, fc, k, cfg);

    err = alpha_est - alpha_true;
    if abs(alpha_true) > 1e-12
        rel_err = abs(err) / abs(alpha_true) * 100;
        fprintf('%-+10.2e | %-+14.4e | %-14.3e | %-+11.2f%% | %.1f→%.1f\n', ...
                alpha_true, alpha_est, abs(err), rel_err, diag_out.tau_up, diag_out.tau_dn);
    else
        fprintf('%-+10.2e | %-+14.4e | %-14.3e | (α=0)       | %.1f→%.1f\n', ...
                alpha_true, alpha_est, abs(err), diag_out.tau_up, diag_out.tau_dn);
    end
end

fprintf('\n========================================\n');
fprintf('  完成\n');
fprintf('========================================\n');
