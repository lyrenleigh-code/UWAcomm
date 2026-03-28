function [h_est, H_est, gamma] = ch_est_sbl(y, Phi, N, max_iter, tol)
% 功能：SBL（稀疏贝叶斯学习）信道估计
% 版本：V1.0.0
% 输入：
%   y        - 观测向量 (Mx1)
%   Phi      - 测量矩阵 (MxN)
%   N        - 信道长度
%   max_iter - 最大迭代次数 (默认 100)
%   tol      - 收敛阈值 (默认 1e-6)
% 输出：
%   h_est - 时域信道估计 (Nx1)
%   H_est - 频域信道估计 (1xN)
%   gamma - 各抽头的超参数（方差，Nx1，大值=活跃抽头）
%
% 备注：
%   - SBL通过EM算法自动学习稀疏先验，无需已知稀疏度K
%   - 每个抽头的先验方差gamma_i由数据驱动估计
%   - gamma_i→0的抽头被自动置零（实现稀疏性）
%   - 相比OMP更鲁棒，但复杂度更高 O(iter*N^2*M)

%% ========== 入参解析 ========== %%
if nargin < 5 || isempty(tol), tol = 1e-6; end
if nargin < 4 || isempty(max_iter), max_iter = 100; end
y = y(:);
[M, ~] = size(Phi);

%% ========== 参数校验 ========== %%
if isempty(y), error('观测向量不能为空！'); end

%% ========== 初始化 ========== %%
gamma = ones(N, 1);                    % 超参数初始化
sigma2 = norm(y)^2 / (10 * M);        % 噪声方差初始估计

%% ========== EM迭代 ========== %%
for iter = 1:max_iter
    gamma_old = gamma;

    % E步：后验均值和协方差
    Gamma = diag(gamma);
    Sigma_inv = Phi' * Phi / sigma2 + inv(Gamma + 1e-10*eye(N));
    Sigma = inv(Sigma_inv);
    mu = Sigma * (Phi' * y) / sigma2;  % 后验均值

    % M步：更新超参数
    for i = 1:N
        gamma(i) = abs(mu(i))^2 + Sigma(i,i);
    end

    % 更新噪声方差
    residual = y - Phi * mu;
    sigma2 = (norm(residual)^2 + sigma2 * sum(1 - diag(Sigma) ./ gamma)) / M;
    sigma2 = max(sigma2, 1e-10);

    % 收敛检查
    if norm(gamma - gamma_old) / (norm(gamma_old) + 1e-10) < tol
        break;
    end
end

%% ========== 输出 ========== %%
h_est = mu;

% 置零小于阈值的抽头
threshold = max(gamma) * 1e-4;
h_est(gamma < threshold) = 0;

H_est = fft(h_est.', N);

end
