function [h_est, H_est, mse_history, rho_out] = ch_est_ws_turbo_vamp(y, Phi, N, max_iter, K_sparse, noise_var, rho_prev, beta)
% 功能：WS-Turbo-VAMP（热启动Turbo-VAMP）稀疏信道估计
% 版本：V2.0.0
% 输入：
%   y         - 观测向量 (Mx1)
%   Phi       - 测量矩阵 (MxN)
%   N         - 信道长度
%   max_iter  - 最大迭代次数 (默认 50)
%   K_sparse  - 稀疏度估计
%   noise_var - 噪声方差
%   rho_prev  - 前帧后验支撑概率 (Nx1，首帧传 zeros(N,1))
%   beta      - 时间相关系数 (0~1，默认 0.6)
% 输出：
%   h_est, H_est, mse_history, rho_out
%
% 备注：
%   基于Turbo-VAMP v2.0（正确的VAMP框架），唯一区别在BG去噪器的先验LLR：
%   LLR_prior = log(λ/(1-λ)) + β·log(ρ_prev/(1-ρ_prev))

%% ========== 入参解析 ========== %%
if nargin < 8 || isempty(beta), beta = 0.6; end
if nargin < 7 || isempty(rho_prev), rho_prev = zeros(N, 1); end
if nargin < 6 || isempty(noise_var), noise_var = norm(y)^2 / (10*length(y)); end
if nargin < 5 || isempty(K_sparse), K_sparse = ceil(N/10); end
if nargin < 4 || isempty(max_iter), max_iter = 50; end
y = y(:); rho_prev = rho_prev(:);
[M, ~] = size(Phi);

%% ========== 先验参数 ========== %%
lambda = K_sparse / N;
var_x = max((norm(y)^2/M - noise_var) / (lambda + 1e-10), 0.1);

% 热启动LLR修正
LLR_base = log(lambda / (1 - lambda + 1e-10));
rho_prev_clip = max(min(rho_prev, 1-1e-6), 1e-6);
LLR_warm = beta * log(rho_prev_clip ./ (1 - rho_prev_clip));

%% ========== 预计算 ========== %%
PhiTPhi = Phi' * Phi;
PhiTy = Phi' * y;

%% ========== 初始化 ========== %%
x_hat = zeros(N, 1);
gamma1 = max(1 / var_x, 1e-4);
mse_history = zeros(max_iter, 1);

%% ========== WS-Turbo-VAMP迭代 ========== %%
for t = 1:max_iter
    x_old = x_hat;
    damp = min(0.3 + 0.5 * t / max_iter, 0.9);

    % ===== 模块A：LMMSE =====
    Sigma1 = inv(PhiTPhi / noise_var + gamma1 * eye(N));
    x1 = Sigma1 * (PhiTy / noise_var + gamma1 * x_hat);
    avg_var1 = trace(Sigma1) / N;

    gamma2 = max(1 / avg_var1 - gamma1, 1e-4);
    gamma2 = min(gamma2, 1e6);
    r2 = (x1 / avg_var1 - gamma1 * x_hat) / gamma2;

    % ===== 模块B：BG去噪（使用热启动LLR） =====
    tau2 = 1 / gamma2;

    log_ratio = LLR_base + LLR_warm ...
                + 0.5 * log(tau2 / (tau2 + var_x + 1e-10)) ...
                + 0.5 * abs(r2).^2 .* var_x ./ (tau2 * (tau2 + var_x) + 1e-10);
    log_ratio = max(min(log_ratio, 30), -30);
    pi_post = 1 ./ (1 + exp(-log_ratio));

    var_post = 1 / (gamma2 + 1/var_x);
    mean_post = var_post * gamma2 * r2;
    x2 = pi_post .* mean_post;

    avg_var2 = mean(pi_post .* (var_post + abs(mean_post).^2) - abs(x2).^2);
    avg_var2 = max(avg_var2, 1e-10);

    gamma1_new = max(1 / avg_var2 - gamma2, 1e-4);
    gamma1_new = min(gamma1_new, 1e6);
    gamma1 = damp * gamma1_new + (1 - damp) * gamma1;
    x_hat = damp * x2 + (1 - damp) * x_hat;

    % EM更新（每3次）
    if mod(t, 3) == 0
        lambda = max(min(mean(pi_post), 0.5), 1e-3);
        total_moment = sum(pi_post .* (abs(mean_post).^2 + var_post));
        if sum(pi_post) > 0.1
            var_x = max(total_moment / (sum(pi_post) + 1e-10), 0.01);
        end
        % 更新LLR_base（lambda变了）
        LLR_base = log(lambda / (1 - lambda + 1e-10));
    end

    mse_history(t) = norm(x_hat - x_old)^2 / (norm(x_old)^2 + 1e-10);
    if mse_history(t) < 1e-8 && t > 5
        mse_history(t+1:end) = mse_history(t);
        break;
    end
end

rho_out = pi_post;
h_est = x_hat;
H_est = fft(h_est.', N);

end
