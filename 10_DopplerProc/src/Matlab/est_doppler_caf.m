function [alpha_est, tau_est, caf_map] = est_doppler_caf(r, preamble, fs, alpha_range, alpha_step, tau_range)
% 功能：二维CAF搜索法多普勒估计——通用高精度离线方法
% 版本：V1.0.0
% 输入：
%   r           - 接收信号 (1xN)
%   preamble    - 已知前导码 (1xL)
%   fs          - 采样率 (Hz)
%   alpha_range - α搜索范围 [min, max] (默认 [-0.02, 0.02])
%   alpha_step  - 搜索步长 (默认 1e-4)
%   tau_range   - 时延搜索范围 [min, max] 秒 (默认 [0, 0.1])
% 输出：
%   alpha_est - 多普勒因子估计值
%   tau_est   - 帧到达时延估计值 (秒)
%   caf_map   - CAF搜索面 (N_tau x N_alpha)
%
% 备注：
%   - CAF(τ,α) = |Σ r[n] · p*[round(n/(1+α) - τ·fs)]|²
%   - 复杂度 O(N_alpha × N × log(N))，建议两级搜索（粗1e-3 + 细1e-5）

%% ========== 入参解析 ========== %%
if nargin < 6 || isempty(tau_range), tau_range = [0, 0.1]; end
if nargin < 5 || isempty(alpha_step), alpha_step = 1e-4; end
if nargin < 4 || isempty(alpha_range), alpha_range = [-0.02, 0.02]; end
r = r(:).'; preamble = preamble(:).';

%% ========== 参数校验 ========== %%
if isempty(r), error('接收信号不能为空！'); end
if isempty(preamble), error('前导码不能为空！'); end

%% ========== CAF搜索 ========== %%
alpha_vec = alpha_range(1) : alpha_step : alpha_range(2);
N_alpha = length(alpha_vec);
L = length(preamble);
n_orig = 0:L-1;

% 时延搜索用互相关的峰值位置
caf_peak = zeros(1, N_alpha);
caf_tau = zeros(1, N_alpha);

for i = 1:N_alpha
    % 对前导码做多普勒伸缩
    n_scaled = n_orig / (1 + alpha_vec(i));
    p_scaled = interp1(n_orig, preamble, n_scaled, 'spline', 0);

    % 互相关
    [corr_out, lags] = xcorr(r, p_scaled);
    corr_abs = abs(corr_out).^2;

    % 限制在时延搜索范围内
    lag_sec = lags / fs;
    valid = lag_sec >= tau_range(1) & lag_sec <= tau_range(2);
    if any(valid)
        corr_valid = corr_abs;
        corr_valid(~valid) = 0;
        [caf_peak(i), peak_idx] = max(corr_valid);
        caf_tau(i) = lags(peak_idx) / fs;
    end
end

%% ========== 找最优 ========== %%
[~, best_alpha_idx] = max(caf_peak);
alpha_est = alpha_vec(best_alpha_idx);
tau_est = caf_tau(best_alpha_idx);

% 简化CAF map（只返回峰值曲线）
caf_map = caf_peak;

end
