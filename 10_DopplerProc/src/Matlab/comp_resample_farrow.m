function y_resampled = comp_resample_farrow(y, alpha_est, fs)
% 功能：Farrow滤波器重采样——向量化三阶Lagrange插值
% 版本：V3.0.0
% 输入：
%   y         - 接收信号 (1xN，实数或复数)
%   alpha_est - 估计的多普勒因子
%   fs        - 采样率 (Hz)
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   - 三阶Lagrange插值：4点邻域，通过4个点的精确多项式
%   - 全向量化：一次性计算所有N个输出样本
%   - 精度略低于Catmull-Rom（C0连续 vs C1连续）
%   - 不调用任何MATLAB系统插值函数

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 新采样位置 ========== %%
pos = (1:N) * (1 + alpha_est);

%% ========== 向量化Lagrange插值 ========== %%
pad = 2;
y_pad = [zeros(1, pad), y, zeros(1, pad)];

int_pos = floor(pos);
frac = pos - int_pos;

idx = int_pos + pad;
idx = max(2, min(idx, length(y_pad) - 2));

% 四邻域
x0 = y_pad(idx - 1);
x1 = y_pad(idx);
x2 = y_pad(idx + 1);
x3 = y_pad(idx + 2);

% Lagrange三阶系数 + Horner求值（合并写减少临时变量）
%   c0 = x1
%   c1 = -x0/3 - x1/2 + x2 - x3/6
%   c2 = (x0 - 2*x1 + x2) / 2
%   c3 = (-x0 + 3*x1 - 3*x2 + x3) / 6
y_resampled = x1 + frac .* ((-x0/3 - x1/2 + x2 - x3/6) + ...
              frac .* ((x0 - 2*x1 + x2)/2 + ...
              frac .* (-x0 + 3*x1 - 3*x2 + x3)/6));

end
