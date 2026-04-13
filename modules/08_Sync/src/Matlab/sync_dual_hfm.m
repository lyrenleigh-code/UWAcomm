function [tau_est, alpha_est, qual, info] = sync_dual_hfm(r, hfm_pos, hfm_neg, fs, params)
% 功能：双HFM帧同步——正负扫频HFM偏置对消，联合估计无偏时延和多普勒因子
% 版本：V1.1.0 — 修正α估计公式，加入帧间隔多普勒压缩修正项
% 输入：
%   r        - 接收信号 (1xN 复数/实数)
%   hfm_pos  - HFM+本地模板（正扫频, f0<f1）(1xL)
%   hfm_neg  - HFM-本地模板（负扫频, f0>f1）(1xL)
%   fs       - 采样率 (Hz)
%   params   - 参数结构体
%       .S_bias     : 偏置灵敏度 T*f_bar/B (秒，必须)
%       .alpha_max  : 预期最大|α| (默认 0.01)
%       .search_win : 搜索窗长度 (采样点，默认 length(r)/2)
%       .threshold  : 归一化峰值检测门限 (默认 0.3)
%       .sep_samples: HFM+与HFM-之间的最小间隔(采样点，默认 L)
%                     用于分段搜索防止互相关串扰
%       .frame_gap  : HFM+尾到HFM-头的帧内标称间距(采样点，默认 0)
%                     串联形式需提供(= guard + L_hfm)，并联=0
% 输出：
%   tau_est   - 无偏帧起始时延 (采样点, 1-based)
%   alpha_est - 多普勒因子估计
%   qual      - 同步质量 (峰值/噪底比, 线性)
%   info      - 详细信息
%       .tau_pos     : HFM+相关峰位置 (采样点, 含亚采样精度)
%       .tau_neg     : HFM-相关峰位置
%       .peak_pos    : HFM+峰值
%       .peak_neg    : HFM-峰值
%       .corr_pos    : HFM+归一化相关输出
%       .corr_neg    : HFM-归一化相关输出
%
% 原理：
%   HFM+偏置: Δτ+ ≈ -α·S_bias (正扫频峰值偏早)
%   HFM-偏置: Δτ- ≈ +α·S_bias (负扫频峰值偏晚)
%   消偏:     τ_true = (τ+ + τ-) / 2
%   多普勒:   α = (τ- - τ+) / (2·S_bias)

%% ========== 1. 入参解析 ========== %%
if nargin < 5 || isempty(params), params = struct(); end
if ~isfield(params, 'S_bias'), error('必须提供params.S_bias(偏置灵敏度)！'); end
if ~isfield(params, 'alpha_max'), params.alpha_max = 0.01; end
if ~isfield(params, 'threshold'), params.threshold = 0.3; end

r = r(:).';
hfm_pos = hfm_pos(:).';
hfm_neg = hfm_neg(:).';
L = length(hfm_pos);
M = length(r);

if ~isfield(params, 'search_win'), params.search_win = M - L + 1; end
if ~isfield(params, 'sep_samples'), params.sep_samples = L; end
if ~isfield(params, 'frame_gap'), params.frame_gap = 0; end

%% ========== 2. 参数校验 ========== %%
if isempty(r), error('接收信号不能为空！'); end
if L > M, error('HFM模板长度(%d)大于接收信号长度(%d)！', L, M); end

%% ========== 3. 两路归一化互相关 ========== %%
num_corr = min(params.search_win, M - L + 1);
corr_pos = zeros(1, num_corr);
corr_neg = zeros(1, num_corr);

energy_pos = sum(abs(hfm_pos).^2);
energy_neg = sum(abs(hfm_neg).^2);

for n = 1:num_corr
    seg = r(n : n+L-1);
    seg_energy = sum(abs(seg).^2);
    if seg_energy < 1e-20, continue; end

    corr_pos(n) = abs(sum(seg .* conj(hfm_pos))) / sqrt(seg_energy * energy_pos);
    corr_neg(n) = abs(sum(seg .* conj(hfm_neg))) / sqrt(seg_energy * energy_neg);
end

%% ========== 4. 分段峰值检测（max峰+插值，无首达径阈值偏差）========== %%
% HFM+: 搜前段（到sep_samples之前）
half_win = min(params.sep_samples, num_corr);
[~, n_peak_pos] = max(corr_pos(1:half_win));

% HFM-: 从HFM+峰位置+间隔之后开始搜索
neg_start = n_peak_pos + params.sep_samples;
if neg_start < num_corr
    corr_neg_search = corr_neg(neg_start:end);
    [~, max_pos_n_rel] = max(corr_neg_search);
    n_peak_neg = neg_start + max_pos_n_rel - 1;
else
    [~, n_peak_neg] = max(corr_neg);
end

%% ========== 5. 亚采样抛物线插值精化 ========== %%
delta_pos = parabola_interp(corr_pos, n_peak_pos);
delta_neg = parabola_interp(corr_neg, n_peak_neg);

tau_pos_precise = n_peak_pos + delta_pos;  % 精确采样点位置(1-based)
tau_neg_precise = n_peak_neg + delta_neg;

%% ========== 6. 联合估计（偏置对消 + 帧间隔压缩修正）========== %%
% 串联形式：HFM+在前，HFM-在后，间隔frame_gap采样点
% 考虑多普勒对帧间隔的压缩效应：
%   τ_neg - τ_pos = G/(1+α) + 2*α*S_bias*fs
%   一阶近似：  ≈ G + α*(2*S_bias*fs - G)
%   故：α ≈ (τ_neg - τ_pos - G) / (2*S_bias*fs - G)
%
% 并联形式(frame_gap=0, L=0): 退化为 (τ++τ-)/2
nominal_gap = params.frame_gap + L;  % HFM+头到HFM-头的标称距离(G)
denom = 2 * params.S_bias * fs - nominal_gap;
if abs(denom) < 1e-6
    % 退化情况：nominal_gap ≈ 2*S_bias*fs，无法估计α
    alpha_est = 0;
else
    alpha_est = (tau_neg_precise - tau_pos_precise - nominal_gap) / denom;
end
tau_est = round(tau_pos_precise + alpha_est * params.S_bias * fs);

%% ========== 7. 同步质量评估 ========== %%
noise_floor = (mean(corr_pos) + mean(corr_neg)) / 2;
qual = (corr_pos(n_peak_pos) + corr_neg(n_peak_neg)) / (2 * max(noise_floor, 1e-10));

%% ========== 8. 合理性检验 ========== %%
if abs(alpha_est) > params.alpha_max
    warning('sync_dual_hfm: α估计=%.4f超出范围±%.4f', alpha_est, params.alpha_max);
end

%% ========== 9. 输出详细信息 ========== %%
info.tau_pos = tau_pos_precise;
info.tau_neg = tau_neg_precise;
info.peak_pos = corr_pos(n_peak_pos);
info.peak_neg = corr_neg(n_peak_neg);
info.corr_pos = corr_pos;
info.corr_neg = corr_neg;
info.S_bias = params.S_bias;

end

% --------------- 辅助函数：抛物线插值 --------------- %
function delta = parabola_interp(corr, n_peak)
% 在粗峰值位置附近三点抛物线插值，返回亚采样偏移量
if n_peak <= 1 || n_peak >= length(corr)
    delta = 0;
    return;
end
y_m1 = corr(n_peak - 1);
y_0  = corr(n_peak);
y_p1 = corr(n_peak + 1);
denom = 2 * (2*y_0 - y_p1 - y_m1);
if abs(denom) < 1e-20
    delta = 0;
else
    delta = (y_p1 - y_m1) / denom;
end
end
