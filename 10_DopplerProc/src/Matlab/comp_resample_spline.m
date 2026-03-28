function y_resampled = comp_resample_spline(y, alpha_est, fs)
% 功能：三次样条插值重采样——宽带多普勒补偿
% 版本：V2.0.0
% 输入：
%   y         - 接收信号 (1xN)
%   alpha_est - 估计的多普勒因子
%   fs        - 采样率 (Hz)
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   - 新采样时刻 t_new = t_orig * (1+α)
%   - 使用索引域插值避免浮点时间轴的精度损失
%   - 复数信号用interp1直接处理（MATLAB R2016b+支持）

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 重采样（索引域，避免浮点时间轴） ========== %%
% 原始索引 1:N，新采样位置
idx_new = (1:N) * (1 + alpha_est);

% 钳位到有效范围
idx_new = max(1, min(idx_new, N));

% 三次样条插值
if isreal(y)
    y_resampled = interp1(1:N, y, idx_new, 'spline', 0);
else
    % 分实虚部处理（兼容性更好）
    y_resampled = interp1(1:N, real(y), idx_new, 'spline', 0) + ...
                  1j * interp1(1:N, imag(y), idx_new, 'spline', 0);
end

end
