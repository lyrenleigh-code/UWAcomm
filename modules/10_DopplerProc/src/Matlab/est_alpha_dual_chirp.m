function [alpha, diag] = est_alpha_dual_chirp(bb_raw, LFM_up, LFM_dn, fs, fc, k, search_cfg)
% 功能：双 LFM（up + down chirp）时延差法估计恒定多普勒伸缩率 α
% 版本：V1.1.0（2026-04-23：加 search_cfg.sign_convention 参数化符号约定，
%               消除 runner 里 `-alpha_lfm_raw` hack）
%       V1.0.0（2026-04-20）
% 对应 spec: specs/active/2026-04-20-alpha-estimator-dual-chirp-refinement.md
%
% 原理：
%   α 使时间轴伸缩 t → (1+α)·t。对 up/down LFM 对做匹配滤波：
%     - up-chirp peak 位置漂移 Δτ_up = -α·f_lo/k
%     - down-chirp peak 位置漂移 Δτ_dn = +α·f_hi/k
%   Δτ_obs - Δτ_nom = (Δτ_dn - Δτ_up) ≈ 2·α·fc/k
%   ⇒ α = k · (Δτ_obs - Δτ_nom) / (2 · fc)
%
%   相比同形双 LFM 相位差法（对 α 不敏感），本方法:
%     - 基于峰值位置差（无相位模糊）
%     - 动态范围受 guard 窗限制（典型 ±3e-2）
%     - 精度 σ_α ≈ k / (2·fc·fs)（抛物线插值后再高一个量级）
%
% 输入：
%   bb_raw      - 1×N complex，下变频基带接收信号（含 up/down LFM 前导）
%   LFM_up      - 1×N_lfm complex，up-chirp 模板（原始信号形式，函数内部自动 conj+fliplr）
%   LFM_dn      - 1×N_lfm complex，down-chirp 模板
%   fs          - 采样率 (Hz)
%   fc          - 载波频率 (Hz)
%   k           - chirp 斜率 (Hz/s)，正值，|k| = B / T_pre
%   search_cfg  - struct:
%       .up_start/.up_end          up-chirp 峰搜索窗样本索引（1-based）
%       .dn_start/.dn_end          down-chirp 峰搜索窗样本索引
%       .nominal_delta_samples     τ_dn^nom - τ_up^nom（样本数，理论无 α 时）
%       .use_subsample [optional]  true 启用峰值抛物线插值（默认 true）
%       .sign_convention [optional] 符号约定（默认 'raw'，backwards-compat）：
%         'raw'         — 公式原值。cascade stage 4（HFM 补偿后残余）用此
%         'uwa-channel' — 取反号以匹配 gen_uwa_channel.doppler_rate 的正号=靠近约定
%                         直接 RX 未经 HFM 预补偿的 bb_raw 时用此，省 runner 里
%                         `alpha_lfm = -alpha_lfm_raw` hack
%
% 输出：
%   alpha       - scalar double，α 估计
%   diag        - struct，诊断字段：
%       .tau_up/.tau_dn            peak 样本位置（整数）
%       .tau_up_frac/.tau_dn_frac  子样本偏移（[-0.5, 0.5]）
%       .peak_up/.peak_dn          peak 复数值幅度
%       .snr_up/.snr_dn            peak / median(|corr|) 比（启发式 SNR）
%       .dtau_samples_obs          观测 Δτ（含子样本）
%       .dtau_samples_nom          nominal Δτ
%       .dtau_residual_s           残差（秒）

%% 1. 入参校验
assert(isvector(bb_raw), 'bb_raw 必须是向量');
assert(isvector(LFM_up) && isvector(LFM_dn), 'LFM_up/LFM_dn 必须是向量');
assert(k > 0, 'k 必须为正值（up-chirp 斜率）');
assert(fs > 0 && fc > 0, 'fs/fc 必须为正');
required_fields = {'up_start','up_end','dn_start','dn_end','nominal_delta_samples'};
for f = required_fields
    assert(isfield(search_cfg, f{1}), 'search_cfg 缺字段: %s', f{1});
end
use_subsample = true;
if isfield(search_cfg, 'use_subsample'), use_subsample = search_cfg.use_subsample; end
sign_convention = 'raw';
if isfield(search_cfg, 'sign_convention') && ~isempty(search_cfg.sign_convention)
    sign_convention = lower(search_cfg.sign_convention);
end
assert(ismember(sign_convention, {'raw','uwa-channel'}), ...
       'est_alpha_dual_chirp: sign_convention 必须是 ''raw'' 或 ''uwa-channel''');

%% 2. 匹配滤波模板（conj + 翻转）
mf_up = conj(fliplr(LFM_up(:).'));
mf_dn = conj(fliplr(LFM_dn(:).'));

%% 3. 匹配滤波
bb_row = bb_raw(:).';
corr_up = filter(mf_up, 1, bb_row);
corr_dn = filter(mf_dn, 1, bb_row);
corr_up_abs = abs(corr_up);
corr_dn_abs = abs(corr_dn);

%% 4. 各自搜索窗内找 peak
up_end = min(search_cfg.up_end, length(corr_up_abs));
dn_end = min(search_cfg.dn_end, length(corr_dn_abs));
up_win = search_cfg.up_start:up_end;
dn_win = search_cfg.dn_start:dn_end;
assert(~isempty(up_win) && ~isempty(dn_win), 'up/dn 搜索窗空');

[peak_up_val, up_rel] = max(corr_up_abs(up_win));
[peak_dn_val, dn_rel] = max(corr_dn_abs(dn_win));
tau_up = search_cfg.up_start + up_rel - 1;  % 整数样本
tau_dn = search_cfg.dn_start + dn_rel - 1;

%% 5. 子样本抛物线插值（可选）
tau_up_frac = 0;
tau_dn_frac = 0;
if use_subsample
    tau_up_frac = parabolic_offset(corr_up_abs, tau_up);
    tau_dn_frac = parabolic_offset(corr_dn_abs, tau_dn);
end

%% 6. α 估计（核心公式）
% 物理模型：rx_bb(t) = frame_bb((1+α)t) · exp(j·2π·fc·α·t)
% 两个效应：
%   (a) 全局时间压缩：peak 位置缩放为 τ_nom/(1+α) ≈ τ_nom·(1-α)
%       贡献 Δτ_dn - Δτ_up = -α · dtau_nom
%   (b) chirp doppler（CFO 导致 up/down chirp peak 反向漂移）：
%       Δτ_up^chirp = -α·fc/k,  Δτ_dn^chirp = +α·fc/k
%       贡献 Δτ_dn - Δτ_up = +2·α·fc/k
% 合计：dtau_residual = α · (2·fc/k - dtau_nom)
% 解得 α = dtau_residual / (2·fc/k - dtau_nom)
dtau_samples_obs = (tau_dn + tau_dn_frac) - (tau_up + tau_up_frac);
dtau_samples_nom = search_cfg.nominal_delta_samples;
dtau_residual_s = (dtau_samples_obs - dtau_samples_nom) / fs;
dtau_nom_s = dtau_samples_nom / fs;
denom = 2*fc/k - dtau_nom_s;
assert(abs(denom) > 1e-8, 'est_alpha_dual_chirp: 病态参数 2fc/k ≈ dtau_nom，估计退化');
alpha = dtau_residual_s / denom;

%% 6b. 符号约定（V1.1）
if strcmp(sign_convention, 'uwa-channel')
    alpha = -alpha;   % 匹配 gen_uwa_channel.doppler_rate 正号=靠近/压缩
end

%% 7. 诊断
corr_up_median = median(corr_up_abs(up_win));
corr_dn_median = median(corr_dn_abs(dn_win));
diag.tau_up         = tau_up;
diag.tau_dn         = tau_dn;
diag.tau_up_frac    = tau_up_frac;
diag.tau_dn_frac    = tau_dn_frac;
diag.peak_up        = peak_up_val;
diag.peak_dn        = peak_dn_val;
diag.snr_up         = peak_up_val / max(corr_up_median, eps);
diag.snr_dn         = peak_dn_val / max(corr_dn_median, eps);
diag.dtau_samples_obs = dtau_samples_obs;
diag.dtau_samples_nom = dtau_samples_nom;
diag.dtau_residual_s  = dtau_residual_s;

end

%% ============ 子函数 ============

function off = parabolic_offset(corr_abs, peak_idx)
% 抛物线三点插值：用 peak 两侧的点拟合抛物线，返回子样本偏移 off ∈ (-0.5, 0.5)
if peak_idx <= 1 || peak_idx >= length(corr_abs)
    off = 0; return;
end
y0 = corr_abs(peak_idx - 1);
y1 = corr_abs(peak_idx);
y2 = corr_abs(peak_idx + 1);
denom = 2 * (y0 - 2*y1 + y2);
if abs(denom) < eps
    off = 0;
else
    off = (y0 - y2) / denom;
    % 保护：插值偏移应在 (-0.5, 0.5) 范围内
    off = max(-0.5, min(0.5, off));
end
end
