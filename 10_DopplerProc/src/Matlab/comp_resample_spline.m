function y_resampled = comp_resample_spline(y, alpha_est, fs)
% 功能：三次样条插值重采样——宽带多普勒补偿
% 版本：V1.0.0
% 输入：
%   y         - 接收信号 (1xN)
%   alpha_est - 估计的多普勒因子
%   fs        - 采样率 (Hz)
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   - 将被α伸缩的信号恢复到原始采样率
%   - 新采样时刻 t_new = t_orig * (1+α)
%   - 在新时刻上用三次样条插值

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 重采样 ========== %%
t_orig = (0:N-1) / fs;
t_new = t_orig * (1 + alpha_est);

% 三次样条插值（实部和虚部分别处理以提高精度）
if isreal(y)
    y_resampled = interp1(t_orig, y, t_new, 'spline', 0);
else
    y_real = interp1(t_orig, real(y), t_new, 'spline', 0);
    y_imag = interp1(t_orig, imag(y), t_new, 'spline', 0);
    y_resampled = y_real + 1j * y_imag;
end

% 截取到原始长度
y_resampled = y_resampled(1:min(N, length(y_resampled)));
if length(y_resampled) < N
    y_resampled = [y_resampled, zeros(1, N - length(y_resampled))];
end

end
