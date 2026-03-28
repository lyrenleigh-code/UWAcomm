function y_resampled = comp_resample_spline(y, alpha_est, fs)
% 功能：Catmull-Rom三次样条重采样——C1连续，全向量化
% 版本：V5.0.0
% 输入：
%   y         - 接收信号 (1xN，实数或复数)
%   alpha_est - 估计的多普勒因子
%   fs        - 采样率 (Hz)
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   - Catmull-Rom样条：局部4点三次插值，C1连续（一阶导连续）
%   - 不需要全局三对角系统求解（区别于自然三次样条）
%   - 全向量化：无for循环，性能与Farrow相当
%   - 精度优于Lagrange（Farrow），C1光滑性更好
%   - 不调用任何MATLAB系统插值函数

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 新采样位置 ========== %%
pos = (1:N) * (1 + alpha_est);

%% ========== 向量化Catmull-Rom插值 ========== %%
% 补零两端各2个（4点模板需要i-1到i+2）
pad = 2;
y_pad = [zeros(1, pad), y, zeros(1, pad)];

% 整数和小数部分
int_pos = floor(pos);
frac = pos - int_pos;

% 中心索引（在补零数组中）
idx = int_pos + pad;
idx = max(2, min(idx, length(y_pad) - 2));

% 四邻域采样值
x0 = y_pad(idx - 1);                  % y(i-1)
x1 = y_pad(idx);                      % y(i)
x2 = y_pad(idx + 1);                  % y(i+1)
x3 = y_pad(idx + 2);                  % y(i+2)

% Catmull-Rom系数（向量化）
% S(t) = 0.5 * [(-x0+3x1-3x2+x3)t³ + (2x0-5x1+4x2-x3)t² + (-x0+x2)t + 2x1]
a3 = 0.5 * (-x0 + 3*x1 - 3*x2 + x3);
a2 = 0.5 * (2*x0 - 5*x1 + 4*x2 - x3);
a1 = 0.5 * (-x0 + x2);
a0 = x1;

% Horner求值
y_resampled = ((a3 .* frac + a2) .* frac + a1) .* frac + a0;

end
