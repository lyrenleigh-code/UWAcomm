function [alpha, diag_out] = est_alpha_passband_chirp(rx_pb, LFM_up_pb, LFM_dn_pb, fs, fc, k_chirp, cfg)
% EST_ALPHA_PASSBAND_CHIRP 通带 LFM 匹配滤波 α 估计（真实 Doppler 鲁棒）
%
% 原理：直接在通带实信号 rx_pb 上做 LFM 匹配滤波，用峰位差 + 范围-多普勒耦合
%       公式估 α。避开下变频引入的 fc·α CFO 对 bb 峰位的污染。
%
% 数学：
%   Doppler (1+α) 下，TX LFM chirp rate k 在 RX 匹配滤波输出的 peak 时延：
%     τ_up_obs ≈ τ_up_nom/(1+α) + fc·α/k     (up-chirp, k>0)
%     τ_dn_obs ≈ τ_dn_nom/(1+α) - fc·α/k     (dn-chirp, k'=-k)
%   峰位差：
%     dtau_obs - dtau_nom ≈ -α·dtau_nom - 2·fc·α/k
%                         ≈ -α·(dtau_nom + 2·fc/k)         (主项)
%   => α ≈ -dtau_residual / (dtau_nom + 2·fc/k)            (时间秒单位)
%   在样本单位：dtau_nom_s = dtau_nom_samp/fs，转换后
%
% 输入：
%   rx_pb      - 通带实信号 (1xN 实数)
%   LFM_up_pb  - 通带 up-chirp 模板 (1xN_lfm 实数)
%   LFM_dn_pb  - 通带 dn-chirp 模板 (1xN_lfm 实数)
%   fs, fc     - 采样率 / 载频 (Hz)
%   k_chirp    - chirp 斜率 (Hz/s, 取 up-chirp 值，必 >0)
%   cfg        - struct:
%     .up_start, .up_end   - up-chirp 搜索窗（rx_pb 索引）
%     .dn_start, .dn_end   - dn-chirp 搜索窗
%     .nominal_delta_samples - 名义 peak 时延差（样本）
%     .use_subsample       - true 时用抛物线内插亚样本 peak 位置
%
% 输出：
%   alpha      - 估计的 Doppler α（符号与 gen_uwa_channel doppler_rate 一致）
%   diag_out   - 诊断信息 struct（tau_up/dn, peak values）
%
% 版本：V1.0.0（2026-04-22）

if nargin < 7, cfg = struct(); end
if ~isfield(cfg, 'use_subsample'), cfg.use_subsample = true; end
if ~isfield(cfg, 'up_start'), cfg.up_start = 1; end
if ~isfield(cfg, 'up_end'),   cfg.up_end   = length(rx_pb); end
if ~isfield(cfg, 'dn_start'), cfg.dn_start = 1; end
if ~isfield(cfg, 'dn_end'),   cfg.dn_end   = length(rx_pb); end

%% 匹配滤波器（翻转模板）
mf_up = fliplr(LFM_up_pb);
mf_dn = fliplr(LFM_dn_pb);

%% 卷积相关（上下 chirp 分别在各自搜索窗内找 peak）
up_end = min(cfg.up_end, length(rx_pb));
dn_end = min(cfg.dn_end, length(rx_pb));

corr_up = filter(mf_up, 1, rx_pb(cfg.up_start:up_end));
corr_dn = filter(mf_dn, 1, rx_pb(cfg.dn_start:dn_end));

[peak_up_val, up_idx] = max(abs(corr_up));
[peak_dn_val, dn_idx] = max(abs(corr_dn));

% 全局索引（rx_pb 坐标）
tau_up = cfg.up_start + up_idx - 1;
tau_dn = cfg.dn_start + dn_idx - 1;

%% 亚样本 peak 精化（抛物线内插）
if cfg.use_subsample
    tau_up = tau_up + parabolic_offset(corr_up, up_idx);
    tau_dn = tau_dn + parabolic_offset(corr_dn, dn_idx);
end

%% α 估计：基于平均峰位全局时间压缩比率
% 原理：up/dn-chirp 的峰位各自受全局时间压缩 + 非对称 range-Doppler 耦合
%       R-D 耦合在 up/dn 之间反向，取平均可近似抵消 → 只剩全局压缩
%   (τ_up + τ_dn) / 2 ≈ (τ_up_nom + τ_dn_nom) / (2·(1+α))
%   α ≈ (τ_nom_avg / τ_obs_avg) - 1
tau_up_nom = cfg.tau_up_nom;
tau_dn_nom = cfg.tau_dn_nom;
tau_avg_obs = (tau_up + tau_dn) / 2;
tau_avg_nom = (tau_up_nom + tau_dn_nom) / 2;
alpha = tau_avg_nom / tau_avg_obs - 1;

% 诊断：保留峰位差相关量
dtau_obs = tau_dn - tau_up;
dtau_nom = cfg.nominal_delta_samples;
dtau_residual_samp = dtau_obs - dtau_nom;

%% 诊断
diag_out.tau_up = tau_up;
diag_out.tau_dn = tau_dn;
diag_out.dtau_obs = dtau_obs;
diag_out.dtau_residual_samp = dtau_residual_samp;
diag_out.peak_up = peak_up_val;
diag_out.peak_dn = peak_dn_val;

end

%% 辅助：抛物线内插亚样本 peak
function offset = parabolic_offset(x, idx)
    if idx <= 1 || idx >= length(x)
        offset = 0;
        return;
    end
    y_m1 = abs(x(idx-1));
    y_0  = abs(x(idx));
    y_p1 = abs(x(idx+1));
    denom = (y_m1 - 2*y_0 + y_p1);
    if abs(denom) < eps
        offset = 0;
    else
        offset = 0.5 * (y_m1 - y_p1) / denom;
    end
end
