function [alpha_est, V_spectrum, alpha_vec] = velocity_spectrum(r, hfm_pos, hfm_neg, fs, params)
% 功能：速度谱扫描法多普勒估计——利用正负HFM峰值对齐度构建速度谱
% 版本：V1.0.0
% 输入：
%   r        - 接收信号 (1xN)
%   hfm_pos  - HFM+本地模板 (1xL)
%   hfm_neg  - HFM-本地模板 (1xL)
%   fs       - 采样率 (Hz)
%   params   - 参数结构体
%       .alpha_range : 搜索范围 [min, max] (默认 [-0.01, 0.01])
%       .alpha_step  : 搜索步长 (默认 1e-4)
%       .S_bias      : HFM偏置灵敏度 T*f_bar/B (秒)
% 输出：
%   alpha_est  - 多普勒因子估计
%   V_spectrum - 速度谱 (1xN_alpha)
%   alpha_vec  - 对应的α候选值
%
% 原理：
%   对每个候选α_k, 将接收信号重采样后分别与HFM+/HFM-互相关
%   两路峰值位置差 |τ+(α_k) - τ-(α_k)| 在真实α处最小（偏置正好补偿）
%   V(α_k) = 1 / (|τ+ - τ-| + ε) → 谱峰对应真实多普勒

%% ========== 1. 入参解析 ========== %%
if nargin < 5 || isempty(params), params = struct(); end
if ~isfield(params, 'alpha_range'), params.alpha_range = [-0.01, 0.01]; end
if ~isfield(params, 'alpha_step'), params.alpha_step = 1e-4; end
if ~isfield(params, 'S_bias'), error('必须提供params.S_bias！'); end

r = r(:).'; hfm_pos = hfm_pos(:).'; hfm_neg = hfm_neg(:).';
L = length(hfm_pos);

%% ========== 2. 速度谱扫描 ========== %%
alpha_vec = params.alpha_range(1) : params.alpha_step : params.alpha_range(2);
N_alpha = length(alpha_vec);
V_spectrum = zeros(1, N_alpha);

for i = 1:N_alpha
    ak = alpha_vec(i);

    % 对接收信号按候选α重采样
    N_r = length(r);
    t_new = (1:N_r) / (1 + ak);
    t_new = min(t_new, N_r);
    r_resampled = interp1(1:N_r, real(r), t_new, 'spline', 0) + ...
                  1j * interp1(1:N_r, imag(r), t_new, 'spline', 0);

    % 两路互相关峰值位置
    [~, lags_p] = xcorr(r_resampled, hfm_pos);
    corr_p = abs(xcorr(r_resampled, hfm_pos));
    [~, idx_p] = max(corr_p);
    tau_p = lags_p(idx_p);

    corr_n = abs(xcorr(r_resampled, hfm_neg));
    [~, idx_n] = max(corr_n);
    tau_n = lags_p(idx_n);  % lags same length

    % 速度谱：峰值对齐度
    V_spectrum(i) = 1 / (abs(tau_p - tau_n) / fs + 1e-10);
end

%% ========== 3. 谱峰检测 + 抛物线插值 ========== %%
[~, peak_idx] = max(V_spectrum);
if peak_idx > 1 && peak_idx < N_alpha
    y_m1 = V_spectrum(peak_idx-1);
    y_0 = V_spectrum(peak_idx);
    y_p1 = V_spectrum(peak_idx+1);
    denom = 2*(2*y_0 - y_p1 - y_m1);
    if abs(denom) > 1e-20
        delta = (y_p1 - y_m1) / denom;
    else
        delta = 0;
    end
    alpha_est = alpha_vec(peak_idx) + delta * params.alpha_step;
else
    alpha_est = alpha_vec(peak_idx);
end

end
