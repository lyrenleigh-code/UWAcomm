function [h_est, H_est] = ch_est_vamp(y, Phi, N, max_iter, noise_var)
% 功能：VAMP（变分近似消息传递）信道估计
% 版本：V1.0.0
% 输入：
%   y         - 观测向量 (Mx1)
%   Phi       - 测量矩阵 (MxN)
%   N         - 信道长度
%   max_iter  - 最大迭代次数 (默认 100)
%   noise_var - 噪声方差
% 输出：
%   h_est - 时域信道估计 (Nx1)
%   H_est - 频域信道估计 (1xN)
%
% 备注：
%   - VAMP对测量矩阵条件更鲁棒（不要求iid高斯）
%   - 基于SVD分解，交替在信号域和测量域更新

%% ========== 入参解析 ========== %%
if nargin < 5 || isempty(noise_var), noise_var = norm(y)^2 / (10*length(y)); end
if nargin < 4 || isempty(max_iter), max_iter = 100; end
y = y(:);

%% ========== SVD预计算 ========== %%
[U, S, V] = svd(Phi, 'econ');
s = diag(S);
s2 = s.^2;
Uty = U' * y;

%% ========== 初始化 ========== %%
r1 = zeros(N, 1);
gamma1 = 1;

%% ========== VAMP迭代 ========== %%
for t = 1:max_iter
    % LMMSE估计器（测量域）
    d = s2 ./ (s2 * gamma1 + noise_var);
    x1 = V * (d .* (Uty + noise_var * (U' * (Phi * r1 / gamma1))));
    % 简化：直接用正则化LS
    alpha1 = mean(d);
    eta1 = gamma1 / (1 - alpha1 * gamma1);
    r2 = (eta1 * x1 - gamma1 * r1) / (eta1 - gamma1 + 1e-10);
    gamma2 = eta1 - gamma1;
    gamma2 = max(gamma2, 1e-6);

    % 去噪器（信号域，软阈值）
    tau = 1 / gamma2;
    threshold = sqrt(2 * tau * log(N));
    x2 = sign(r2) .* max(abs(r2) - threshold, 0);

    alpha2 = sum(x2 ~= 0) / N;
    eta2 = gamma2 / (1 - alpha2 + 1e-10);
    r1 = (eta2 * x2 - gamma2 * r2) / (eta2 - gamma2 + 1e-10);
    gamma1 = max(eta2 - gamma2, 1e-6);
end

h_est = x2;
H_est = fft(h_est.', N);

end
