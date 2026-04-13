function [h_est, H_est, mse_history] = ch_est_turbo_amp(y, Phi, N, max_iter, K_sparse)
% 功能：Turbo-AMP稀疏信道估计（AMP + 伯努利-高斯先验的Turbo框架）
% 版本：V1.0.0
% 输入：
%   y         - 观测向量 (Mx1)
%   Phi       - 测量矩阵 (MxN)
%   N         - 信道长度
%   max_iter  - 最大迭代次数 (默认 100)
%   K_sparse  - 稀疏度估计 (默认 ceil(N/10))
% 输出：
%   h_est       - 时域信道估计 (Nx1)
%   H_est       - 频域信道估计 (1xN)
%   mse_history - 收敛历史

%% ========== 入参解析 ========== %%
if nargin < 5 || isempty(K_sparse), K_sparse = ceil(N/10); end
if nargin < 4 || isempty(max_iter), max_iter = 100; end
y = y(:);
[M, ~] = size(Phi);

%% ========== 初始化 ========== %%
lambda = K_sparse / N;
var_x = 1;

h_est = zeros(N, 1);
z = y;
mse_history = zeros(max_iter, 1);

%% ========== Turbo-AMP迭代 ========== %%
for t = 1:max_iter
    h_old = h_est;

    % AMP线性步
    r = h_est + Phi' * z;
    tau = norm(z)^2 / M;

    % 伯努利-高斯去噪器
    tau_r = tau * ones(N, 1);
    log_ratio = log(lambda/(1-lambda)) + 0.5*log(tau_r./(tau_r + var_x)) ...
                + 0.5 * abs(r).^2 .* var_x ./ (tau_r .* (tau_r + var_x));
    pi_post = 1 ./ (1 + exp(-log_ratio));

    var_post = 1 ./ (1./tau_r + 1/var_x);
    mean_post = var_post .* r ./ tau_r;
    h_est = pi_post .* mean_post;

    % Onsager校正
    b = sum(pi_post) / M;
    z = y - Phi * h_est + b * z;

    mse_history(t) = norm(h_est - h_old)^2 / (norm(h_old)^2 + 1e-10);
    if mse_history(t) < 1e-8 && t > 3
        mse_history(t+1:end) = mse_history(t);
        break;
    end
end

H_est = fft(h_est.', N);

end
