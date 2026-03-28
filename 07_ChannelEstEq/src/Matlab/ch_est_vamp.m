function [h_est, H_est, mse_history] = ch_est_vamp(y, Phi, N, max_iter, noise_var, K_sparse)
% 功能：VAMP（变分近似消息传递）信道估计
% 版本：V2.0.0
% 输入：
%   y         - 观测向量 (Mx1)
%   Phi       - 测量矩阵 (MxN)
%   N         - 信道长度
%   max_iter  - 最大迭代次数 (默认 100)
%   noise_var - 噪声方差
%   K_sparse  - 稀疏度估计（可选）
% 输出：
%   h_est       - 时域信道估计 (Nx1)
%   H_est       - 频域信道估计 (1xN)
%   mse_history - 收敛历史
%
% 备注：
%   - 基于SVD的标准VAMP实现，交替LMMSE和BG去噪
%   - 加阻尼和EM自适应先验，适用于M<N欠定场景

%% ========== 入参解析 ========== %%
if nargin < 6, K_sparse = []; end
if nargin < 5 || isempty(noise_var), noise_var = norm(y)^2 / (10*length(y)); end
if nargin < 4 || isempty(max_iter), max_iter = 100; end
y = y(:);
[M, ~] = size(Phi);

%% ========== 先验参数 ========== %%
if ~isempty(K_sparse) && K_sparse > 0
    lambda = K_sparse / N;
else
    lambda = 0.05;
end
var_x = max((norm(y)^2/M - noise_var) / (lambda + 1e-10), 0.1);

%% ========== 预计算 ========== %%
PhiTPhi = Phi' * Phi;
PhiTy = Phi' * y;
damping = 0.7;

%% ========== 初始化 ========== %%
x_hat = zeros(N, 1);
gamma1 = max(1 / var_x, 1e-4);
mse_history = zeros(max_iter, 1);

%% ========== VAMP迭代 ========== %%
for t = 1:max_iter
    x_old = x_hat;

    % ===== 模块1：LMMSE =====
    Sigma1 = inv(PhiTPhi / noise_var + gamma1 * eye(N));
    x1 = Sigma1 * (PhiTy / noise_var + gamma1 * x_hat);
    avg_var1 = trace(Sigma1) / N;

    % 外信息精度
    gamma2 = max(1 / avg_var1 - gamma1, 1e-4);
    gamma2 = min(gamma2, 1e6);
    % 外信息均值
    r2 = (x1 / avg_var1 - gamma1 * x_hat) / gamma2;

    % ===== 模块2：BG去噪 =====
    tau2 = 1 / gamma2;

    log_ratio = log(lambda / (1 - lambda + 1e-10)) ...
                + 0.5 * log(tau2 / (tau2 + var_x + 1e-10)) ...
                + 0.5 * abs(r2).^2 .* var_x ./ (tau2 * (tau2 + var_x) + 1e-10);
    log_ratio = max(min(log_ratio, 30), -30);
    pi_post = 1 ./ (1 + exp(-log_ratio));

    var_post = 1 / (gamma2 + 1/var_x);
    mean_post = var_post * gamma2 * r2;
    x2 = pi_post .* mean_post;

    % 平均后验方差（含不确定性）
    avg_var2 = mean(pi_post .* (var_post + abs(mean_post).^2) - abs(x2).^2);
    avg_var2 = max(avg_var2, 1e-10);

    % 外信息更新（加阻尼）
    gamma1_new = max(1 / avg_var2 - gamma2, 1e-4);
    gamma1_new = min(gamma1_new, 1e6);
    gamma1 = damping * gamma1_new + (1 - damping) * gamma1;

    x_hat = damping * x2 + (1 - damping) * x_hat;

    % EM更新（每10次）
    if mod(t, 10) == 0
        lambda = max(min(mean(pi_post), 0.5), 1e-3);
        total_moment = sum(pi_post .* (abs(mean_post).^2 + var_post));
        if sum(pi_post) > 0.1
            var_x = max(total_moment / (sum(pi_post) + 1e-10), 0.01);
        end
    end

    % 收敛
    mse_history(t) = norm(x_hat - x_old)^2 / (norm(x_old)^2 + 1e-10);
    if mse_history(t) < 1e-8 && t > 10
        mse_history(t+1:end) = mse_history(t);
        break;
    end
end

h_est = x_hat;
H_est = fft(h_est.', N);

end
