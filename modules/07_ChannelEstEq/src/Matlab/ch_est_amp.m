function [h_est, H_est, mse_history] = ch_est_amp(y, Phi, N, max_iter, damping)
% 功能：AMP（近似消息传递）稀疏信道估计
% 版本：V1.0.0
% 输入：
%   y        - 观测向量 (Mx1)
%   Phi      - 测量矩阵 (MxN)
%   N        - 信道长度
%   max_iter - 最大迭代次数 (默认 100)
%   damping  - 阻尼系数 (0~1，默认 0.8)
% 输出：
%   h_est       - 时域信道估计 (Nx1)
%   H_est       - 频域信道估计 (1xN)
%   mse_history - 迭代MSE历史 (max_iter x 1，需提供真实信道才有意义)

%% ========== 入参解析 ========== %%
if nargin < 5 || isempty(damping), damping = 0.8; end
if nargin < 4 || isempty(max_iter), max_iter = 100; end
y = y(:);
[M, ~] = size(Phi);

%% ========== AMP迭代 ========== %%
h_est = zeros(N, 1);
z = y;                                 % 残差
mse_history = zeros(max_iter, 1);

for t = 1:max_iter
    h_old = h_est;

    % 线性步
    r = h_est + Phi' * z;

    % 估计噪声水平
    tau = norm(z)^2 / M;

    % 软阈值去噪（稀疏先验）
    threshold = damping * sqrt(tau * log(N));
    h_est = soft_threshold(r, threshold);

    % Onsager校正项
    b = sum(h_est ~= 0) / M;
    z = y - Phi * h_est + b * z;

    mse_history(t) = norm(h_est - h_old)^2 / (norm(h_old)^2 + 1e-10);

    % 收敛检查
    if mse_history(t) < 1e-8 && t > 5
        mse_history(t+1:end) = mse_history(t);
        break;
    end
end

H_est = fft(h_est.', N);

end

% --------------- 辅助函数 --------------- %
function v = soft_threshold(x, tau)
v = sign(x) .* max(abs(x) - tau, 0);
end
