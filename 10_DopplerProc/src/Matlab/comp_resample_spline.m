function y_resampled = comp_resample_spline(y, alpha_est, fs)
% 功能：三次样条插值重采样——宽带多普勒补偿
% 版本：V4.0.0
% 输入：
%   y         - 接收信号 (1xN)
%   alpha_est - 估计的多普勒因子
%   fs        - 采样率 (Hz)
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   - 调用自实现的cubic_spline_interp（不依赖MATLAB系统插值函数）
%   - 均匀网格三次样条，Thomas算法O(N)求解三对角系统
%   - 复数信号分实虚两路分别插值

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 计算新采样位置 ========== %%
idx_new = (1:N) * (1 + alpha_est);
idx_new = max(1, min(idx_new, N));     % 钳位

%% ========== 三次样条插值 ========== %%
if isreal(y)
    y_resampled = cubic_spline_interp(y, idx_new);
else
    y_resampled = cubic_spline_interp(real(y), idx_new) + ...
                  1j * cubic_spline_interp(imag(y), idx_new);
end

end
