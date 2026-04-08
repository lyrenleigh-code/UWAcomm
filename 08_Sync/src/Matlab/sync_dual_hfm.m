function [tau_est, alpha_est, qual, info] = sync_dual_hfm(r, hfm_pos, hfm_neg, fs, params)
% 功能：双HFM帧同步——正负扫频HFM偏置对消，联合估计无偏时延和多普勒因子
% 版本：V1.0.0
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

%% ========== 4. 首达径峰值检测 ========== %%
% HFM+峰值
[max_peak_p, max_pos_p] = max(corr_pos);
first_p = find(corr_pos > 0.6 * max_peak_p, 1, 'first');
if ~isempty(first_p), n_peak_pos = first_p; else, n_peak_pos = max_pos_p; end

% HFM-峰值
[max_peak_n, max_pos_n] = max(corr_neg);
first_n = find(corr_neg > 0.6 * max_peak_n, 1, 'first');
if ~isempty(first_n), n_peak_neg = first_n; else, n_peak_neg = max_pos_n; end

%% ========== 5. 亚采样抛物线插值精化 ========== %%
delta_pos = parabola_interp(corr_pos, n_peak_pos);
delta_neg = parabola_interp(corr_neg, n_peak_neg);

tau_pos_precise = n_peak_pos + delta_pos;  % 精确采样点位置(1-based)
tau_neg_precise = n_peak_neg + delta_neg;

%% ========== 6. 联合估计（偏置对消）========== %%
% τ_true = (τ+ + τ-) / 2  (偏置对消)
% α = (τ- - τ+) / (2 * S_bias * fs)  (从偏置差估计多普勒)
tau_est = round((tau_pos_precise + tau_neg_precise) / 2);
alpha_est = (tau_neg_precise - tau_pos_precise) / (2 * params.S_bias * fs);

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
