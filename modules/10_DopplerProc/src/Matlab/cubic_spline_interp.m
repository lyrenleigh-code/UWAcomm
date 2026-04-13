function yq = cubic_spline_interp(y, xq)
% 功能：三次样条插值（自实现，不调用MATLAB系统函数）
% 版本：V1.0.0
% 输入：
%   y  - 均匀网格上的采样值 (1xN，对应网格点 1,2,...,N)
%   xq - 查询位置 (1xM，浮点索引，范围[1,N])
% 输出：
%   yq - 插值结果 (1xM)
%
% 备注：
%   - 假设输入在均匀网格 x=1:N 上采样（间距h=1）
%   - 自然边界条件：两端二阶导为零
%   - 三对角系统用Thomas算法O(N)求解
%   - 不调用interp1/griddedInterpolant/spline等系统函数

%% ========== 参数校验 ========== %%
y = y(:).';
xq = xq(:).';
N = length(y);
M = length(xq);

if N < 2, error('至少需要2个数据点！'); end

%% ========== 步骤1：求解三对角系统得二阶导数 ========== %%
% 自然三次样条：在均匀网格(h=1)上，三对角方程为
% m(i-1) + 4*m(i) + m(i+1) = 6*(y(i+1) - 2*y(i) + y(i-1))
% 边界条件：m(1)=0, m(N)=0

m = zeros(1, N);                       % 二阶导数（节点处）

if N > 2
    % 右端向量
    n_inner = N - 2;
    d = zeros(1, n_inner);
    for i = 1:n_inner
        d(i) = 6 * (y(i+2) - 2*y(i+1) + y(i));
    end

    % Thomas算法求解三对角系统 [1,4,1]*m_inner = d
    % 下对角=1, 主对角=4, 上对角=1
    c_prime = zeros(1, n_inner);       % 修改后的上对角
    d_prime = zeros(1, n_inner);       % 修改后的右端

    % 前向消元
    c_prime(1) = 1 / 4;
    d_prime(1) = d(1) / 4;
    for i = 2:n_inner
        denom = 4 - c_prime(i-1);
        c_prime(i) = 1 / denom;
        d_prime(i) = (d(i) - d_prime(i-1)) / denom;
    end

    % 回代
    m_inner = zeros(1, n_inner);
    m_inner(n_inner) = d_prime(n_inner);
    for i = n_inner-1:-1:1
        m_inner(i) = d_prime(i) - c_prime(i) * m_inner(i+1);
    end

    m(2:N-1) = m_inner;
end

%% ========== 步骤2：在查询位置上评估三次多项式 ========== %%
% 钳位查询位置到[1, N]
xq_clamped = max(1, min(xq, N - 1e-10));

% 确定每个查询点所在的区间
idx = floor(xq_clamped);              % 区间左端索引 (1-based)
idx = max(1, min(idx, N-1));           % 确保不越界
t = xq_clamped - idx;                 % 区间内的局部坐标 [0,1)

% 三次样条公式（h=1的简化形式）：
% S(x) = (1-t)*y(i) + t*y(i+1)
%       + t*(1-t)*[(1-t)*(m(i)/6*2 + ...) ...]
% 标准公式（h=1）：
% S(t) = (1-t)*y_i + t*y_{i+1} + t*(1-t)*((a-1)*t + (b-1)*(1-t))
% 其中 a = m_{i+1}/6, b = m_i/6 ... 不对
%
% 正确公式（均匀网格h=1）：
% S_i(t) = m_i/6*(1-t)^3 + m_{i+1}/6*t^3
%        + (y_i - m_i/6)*(1-t) + (y_{i+1} - m_{i+1}/6)*t

yi = y(idx);                           % 左端值
yi1 = y(idx + 1);                     % 右端值
mi = m(idx);                          % 左端二阶导
mi1 = m(idx + 1);                    % 右端二阶导

t1 = 1 - t;                           % (1-t)

yq = mi/6 .* t1.^3 + mi1/6 .* t.^3 ...
   + (yi - mi/6) .* t1 + (yi1 - mi1/6) .* t;

end
