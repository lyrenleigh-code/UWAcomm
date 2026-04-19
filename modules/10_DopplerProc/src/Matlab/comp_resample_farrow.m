function y_resampled = comp_resample_farrow(y, alpha_est, fs, mode)
% 功能：Farrow滤波器重采样——支持快速模式和高精度模式
% 版本：V5.0.0（2026-04-19 alpha 符号约定与 spline V7 对齐，见代码内注释）
% 输入：
%   y         - 接收信号 (1xN，实数或复数)
%   alpha_est - 估计的多普勒因子
%   fs        - 采样率 (Hz)
%   mode      - 运行模式（字符串，默认 'fast'）
%               'fast'     : 三阶Lagrange插值（4点，全向量化）
%               'accurate' : 五阶Lagrange插值（6点，精度更高）
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   fast模式：三阶(4点)Lagrange，每样本等效7次乘法
%   accurate模式：五阶(6点)Lagrange，每样本等效15次乘法，旁瓣抑制更好
%   两种模式均全向量化，不调用MATLAB系统插值函数

%% ========== 入参 ========== %%
if nargin < 4 || isempty(mode), mode = 'fast'; end
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 新采样位置 ========== %%
% V5.0.0 修复（2026-04-19）：与 comp_resample_spline V7 对齐符号约定
% alpha_est > 0 表示接收端靠近（时间压缩），pos 应 < (1:N)
% 旧 V4 代码 pos = (1:N) * (1+alpha) 方向相反，切换 comp_method 会产生二倍补偿误差
pos = (1:N) / (1 + alpha_est);
int_pos = floor(pos);
frac = pos - int_pos;

%% ========== 按模式选择 ========== %%
switch mode
    case 'fast'
        y_resampled = lagrange3_vectorized(y, int_pos, frac, N);
    case 'accurate'
        y_resampled = lagrange5_vectorized(y, int_pos, frac, N);
    otherwise
        error('不支持的模式: %s！支持 fast/accurate', mode);
end

end

% --------------- 三阶Lagrange（4点） --------------- %
function yq = lagrange3_vectorized(y, int_pos, frac, N)
pad = 2;
y_pad = [zeros(1, pad), y, zeros(1, pad)];
idx = max(2, min(int_pos + pad, length(y_pad) - 2));

x0 = y_pad(idx - 1);
x1 = y_pad(idx);
x2 = y_pad(idx + 1);
x3 = y_pad(idx + 2);

yq = x1 + frac .* ((-x0/3 - x1/2 + x2 - x3/6) + ...
     frac .* ((x0 - 2*x1 + x2)/2 + ...
     frac .* (-x0 + 3*x1 - 3*x2 + x3)/6));
end

% --------------- 五阶Lagrange（6点） --------------- %
function yq = lagrange5_vectorized(y, int_pos, frac, N)
pad = 3;
y_pad = [zeros(1, pad), y, zeros(1, pad)];
idx = max(3, min(int_pos + pad, length(y_pad) - 3));

xm2 = y_pad(idx - 2);
xm1 = y_pad(idx - 1);
x0  = y_pad(idx);
x1  = y_pad(idx + 1);
x2  = y_pad(idx + 2);
x3  = y_pad(idx + 3);

% 五阶Lagrange（Neville算法展开为Horner形式）
t = frac;
t1 = t - 1; t2 = t + 1; t3 = t - 2; t4 = t + 2;

% L_k(t) = prod(t - t_j, j≠k) / prod(t_k - t_j, j≠k)
% 采样点在 -2,-1,0,1,2,3 处，t ∈ [0,1)
L0 = t .* t1 .* t3 .* t2 .* (t-3) / 120;     % 除以 (-2)(-1)(0-(-2))... 简化
% 直接用标准Lagrange公式（已简化为向量运算）
tm1 = t + 1; tm2 = t + 2;
tp1 = t - 1; tp2 = t - 2; tp3 = t - 3;

w0 = t .* tp1 .* tp2 .* tp3 .* tm1 / (-120);    % 对应 xm2, 节点-2
w1 = t .* tp1 .* tp2 .* tp3 .* tm2 / 24;         % 对应 xm1, 节点-1
w2 = tp1 .* tp2 .* tp3 .* tm1 .* tm2 / (-12);    % 对应 x0,  节点 0
w3 = t .* tp2 .* tp3 .* tm1 .* tm2 / 12;          % 对应 x1,  节点 1
w4 = t .* tp1 .* tp3 .* tm1 .* tm2 / (-24);       % 对应 x2,  节点 2
w5 = t .* tp1 .* tp2 .* tm1 .* tm2 / 120;         % 对应 x3,  节点 3

yq = w0 .* xm2 + w1 .* xm1 + w2 .* x0 + w3 .* x1 + w4 .* x2 + w5 .* x3;
end
