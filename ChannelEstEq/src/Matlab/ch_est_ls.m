function [H_est, h_est] = ch_est_ls(Y_pilot, X_pilot, N, pilot_indices)
% 功能：LS（最小二乘）信道估计——频域导频处直接相除
% 版本：V1.0.0
% 输入：
%   Y_pilot       - 导频位置接收值 (1xP 复数)
%   X_pilot       - 导频位置发送值 (1xP 复数)
%   N             - 总子载波数/FFT点数 (用于插值到全频带)
%   pilot_indices - 导频子载波索引 (1xP，1-based，可选)
%                   提供时做线性插值到N个子载波；不提供时假设全频带导频
% 输出：
%   H_est - 频域信道估计 (1xN 复数)
%   h_est - 时域信道估计 (1xN 复数，IFFT结果)
%
% 备注：
%   - LS估计：H_ls(k) = Y(k)/X(k)，无需噪声方差先验
%   - 优点：简单无偏；缺点：噪声增强，高频处波动大
%   - 导频间的频率响应通过线性插值获得

%% ========== 参数校验 ========== %%
if isempty(Y_pilot) || isempty(X_pilot), error('导频数据不能为空！'); end
if length(Y_pilot) ~= length(X_pilot), error('收发导频长度不一致！'); end

%% ========== LS估计 ========== %%
H_pilot = Y_pilot ./ X_pilot;

%% ========== 插值到全频带 ========== %%
if nargin >= 4 && ~isempty(pilot_indices) && length(pilot_indices) < N
    % 线性插值
    H_est = interp1(pilot_indices, H_pilot, 1:N, 'linear', 'extrap');
else
    H_est = H_pilot;
    if length(H_est) < N
        H_est = [H_est, zeros(1, N - length(H_est))];
    end
end

%% ========== 时域信道 ========== %%
h_est = ifft(H_est);

end
