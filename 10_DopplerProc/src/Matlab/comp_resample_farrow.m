function y_resampled = comp_resample_farrow(y, alpha_est, fs)
% 功能：Farrow滤波器重采样——向量化三阶Lagrange插值
% 版本：V2.0.0
% 输入：
%   y, alpha_est, fs（同comp_resample_spline）
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   - 全向量化实现，无for循环，长数据性能与MATLAB resample相当
%   - 三阶Lagrange插值：4点邻域，每样本等效4乘3加
%   - 边界处理：两端补零3个样本

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 向量化Farrow重采样 ========== %%
ratio = 1 + alpha_est;

% 所有目标采样位置（浮点）
pos = (1:N) * ratio;
int_pos = floor(pos);
frac = pos - int_pos;

% 补零（两端各3个，防止边界越界）
pad = 3;
y_pad = [zeros(1, pad), y, zeros(1, pad)];

% 四个邻域样本的索引（向量化取值）
idx = int_pos + pad;                   % 中心索引（在补零数组中）
idx = max(2, min(idx, length(y_pad) - 2));  % 钳位防越界

x0 = y_pad(idx - 1);
x1 = y_pad(idx);
x2 = y_pad(idx + 1);
x3 = y_pad(idx + 2);

% 三阶Lagrange多项式系数（向量化）
c0 = x1;
c1 = -x0/3 - x1/2 + x2 - x3/6;
c2 = x0/2 - x1 + x2/2;
c3 = -x0/6 + x1/2 - x2/2 + x3/6;

% Horner求值（向量化）
y_resampled = ((c3 .* frac + c2) .* frac + c1) .* frac + c0;

end
