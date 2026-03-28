function [H_est, h_est] = ch_est_mmse(Y_pilot, X_pilot, N, noise_var, pilot_indices)
% 功能：MMSE信道估计——利用噪声方差进行正则化，抑制噪声增强
% 版本：V1.0.0
% 输入：
%   Y_pilot       - 导频位置接收值 (1xP 复数)
%   X_pilot       - 导频位置发送值 (1xP 复数)
%   N             - 总子载波数
%   noise_var     - 噪声方差 sigma^2
%   pilot_indices - 导频子载波索引 (1xP，可选)
% 输出：
%   H_est - 频域信道估计 (1xN)
%   h_est - 时域信道估计 (1xN)
%
% 备注：
%   - MMSE：H(k) = Y(k)*X*(k) / (|X(k)|^2 + sigma^2)
%   - 相比LS，MMSE在低SNR时噪声抑制更好

%% ========== 参数校验 ========== %%
if isempty(Y_pilot) || isempty(X_pilot), error('导频数据不能为空！'); end
if noise_var < 0, error('噪声方差不能为负！'); end

%% ========== MMSE估计 ========== %%
H_pilot = (Y_pilot .* conj(X_pilot)) ./ (abs(X_pilot).^2 + noise_var);

%% ========== 插值到全频带 ========== %%
if nargin >= 5 && ~isempty(pilot_indices) && length(pilot_indices) < N
    H_est = interp1(pilot_indices, H_pilot, 1:N, 'linear', 'extrap');
else
    H_est = H_pilot;
    if length(H_est) < N
        H_est = [H_est, zeros(1, N - length(H_est))];
    end
end

%% ========== 时域 ========== %%
h_est = ifft(H_est);

end
