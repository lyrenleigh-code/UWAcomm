function y_resampled = comp_resample_spline(y, alpha_est, fs)
% 功能：三次样条插值重采样——宽带多普勒补偿
% 版本：V3.0.0
% 输入：
%   y         - 接收信号 (1xN)
%   alpha_est - 估计的多普勒因子
%   fs        - 采样率 (Hz)
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   - 使用griddedInterpolant替代interp1，预计算样条系数，评估更快
%   - 均匀网格优化：输入网格为1:N，griddedInterpolant内部有特化路径
%   - 复数信号：分实虚两路各建一个插值对象（比interp1两次调用更快）

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 计算新采样位置 ========== %%
idx_new = (1:N) * (1 + alpha_est);
idx_new = max(1, min(idx_new, N));     % 钳位到有效范围

%% ========== griddedInterpolant样条插值 ========== %%
x_grid = (1:N)';                       % 均匀网格（列向量）

if isreal(y)
    F = griddedInterpolant(x_grid, y(:), 'spline');
    y_resampled = F(idx_new(:)).';
else
    F_re = griddedInterpolant(x_grid, real(y(:)), 'spline');
    F_im = griddedInterpolant(x_grid, imag(y(:)), 'spline');
    y_resampled = F_re(idx_new(:)).' + 1j * F_im(idx_new(:)).';
end

end
