function [alpha, diag_out] = est_alpha_cascade(rx_pb, hfm_up_pb, hfm_dn_pb, lfm_up_bb, lfm_dn_bb, fs, fc, k_lfm, hfm_params, lfm_cfg)
% EST_ALPHA_CASCADE HFM 粗估 + 通带 resample + 下变频 + LFM 精估 两级 α 估计
%
% 原理：
%   Stage 1：双 HFM 粗估 α_hfm（1-5% 相对误差，大 α 范围鲁棒，CFO 免疫）
%   Stage 2：通带 poly_resample 用 α_hfm 补偿 → rx_pb_comp（残余 α ≈ 1e-4~1e-3）
%   Stage 3：下变频 rx_pb_comp → bb_comp
%   Stage 4：双 LFM 精估残余 α_lfm（小 α 下公式线性，残余 ~1e-6）
%   合成：α_total = (1+α_hfm)·(1+α_lfm) - 1
%
% 精度：50 节（±1.7e-2）残余 <1e-5，远优于单独 HFM 或 LFM
%
% 输入：
%   rx_pb     - 接收通带实信号
%   hfm_up_pb, hfm_dn_pb - 通带 HFM+ / HFM- 模板（实数）
%   lfm_up_bb, lfm_dn_bb - 基带 LFM+ / LFM- 模板（复数，用于 est_alpha_dual_chirp）
%   fs, fc    - 采样率 / 载频
%   k_lfm     - LFM chirp rate (Hz/s)
%   hfm_params - sync_dual_hfm 参数（S_bias, frame_gap, sep_samples 等）
%   lfm_cfg    - est_alpha_dual_chirp cfg（up_start/end, dn_start/end, nominal_delta_samples）
%
% 输出：
%   alpha    - 最终估计的 α（符号与 gen_uwa_channel doppler_rate 一致）
%   diag_out - 诊断：alpha_hfm / alpha_lfm_res / 各自 info
%
% 版本：V1.0.0（2026-04-22）

%% Stage 1：HFM 粗估
[~, alpha_hfm, ~, hfm_info] = sync_dual_hfm(rx_pb, hfm_up_pb, hfm_dn_pb, fs, hfm_params);

%% Stage 2：通带 resample 补偿
% |α|>1e-3 才做通带 resample，tiny α 留给 LFM 阶段直接估（避免 rat() 对 tiny α 出 huge p/q）
if abs(alpha_hfm) > 1e-3
    [p_num, q_den] = rat(1 + alpha_hfm, 1e-6);
    rx_pb_comp = poly_resample(rx_pb, p_num, q_den);
else
    rx_pb_comp = rx_pb;
end

%% Stage 3：下变频到基带（复数）
% 用较宽 LPF 通过 LFM 带宽
lpf_bw = k_lfm * length(lfm_up_bb) / fs / 2 + 500;   % LFM 带宽 B = k·T
lpf_bw = min(lpf_bw, fs/2 - 100);
[bb_comp, ~] = downconvert(rx_pb_comp, fs, fc, lpf_bw);

%% Stage 4：LFM 精估残余 α
try
    [alpha_lfm_raw, lfm_info] = est_alpha_dual_chirp(bb_comp, lfm_up_bb, lfm_dn_bb, ...
                                                      fs, fc, k_lfm, lfm_cfg);
    % HFM 补偿后小残余场景下，est_alpha_dual_chirp 输出直接跟踪残余方向（不反号）
    alpha_lfm_res = +alpha_lfm_raw;
catch ME
    alpha_lfm_res = 0;
    lfm_info = struct('error', ME.message);
end

%% 合成总 α
% 如果 Stage2 skip 了（tiny α_hfm），则 LFM 阶段看到的是完整 α，不应再与 α_hfm 相乘
if abs(alpha_hfm) > 1e-3
    alpha = (1 + alpha_hfm) * (1 + alpha_lfm_res) - 1;
else
    alpha = alpha_lfm_res;   % Stage2 未补偿，LFM 直接估全 α
end

%% 诊断
diag_out.alpha_hfm     = alpha_hfm;
diag_out.alpha_lfm_res = alpha_lfm_res;
diag_out.alpha_total   = alpha;
diag_out.hfm_info      = hfm_info;
diag_out.lfm_info      = lfm_info;

end
