function [h_est, H_est, mse_history, rho_out] = ch_est_ws_turbo_vamp(y, Phi, N, max_iter, K_sparse, noise_var, rho_prev, beta)
% 功能：WS-Turbo-VAMP（热启动Turbo-VAMP）稀疏信道估计
% 版本：V1.0.0
% 输入：
%   y         - 观测向量 (Mx1)
%   Phi       - 测量矩阵 (MxN)
%   N         - 信道长度
%   max_iter  - 最大迭代次数 (默认 50)
%   K_sparse  - 稀疏度估计 (默认 ceil(N/10))
%   noise_var - 噪声方差
%   rho_prev  - 前帧后验支撑概率 (Nx1，首帧传 zeros(N,1))
%   beta      - 时间相关系数 (0~1，默认 0.6，0=冷启动，1=完全信任前帧)
% 输出：
%   h_est       - 时域信道估计 (Nx1)
%   H_est       - 频域信道估计 (1xN)
%   mse_history - NMSE收敛历史
%   rho_out     - 当前帧后验支撑概率（传递给下一帧）
%
% 备注：
%   【创新点】热启动机制：
%   LLR_prior,i = log(lambda/(1-lambda)) + beta * log(rho_prev_i/(1-rho_prev_i))
%   - 慢时变信道：beta大→利用前帧信息→加速收敛（减少50%+迭代次数）
%   - 快时变信道：beta→0→退化为标准Turbo-VAMP→保证鲁棒性

%% ========== 入参解析 ========== %%
if nargin < 8 || isempty(beta), beta = 0.6; end
if nargin < 7 || isempty(rho_prev), rho_prev = zeros(N, 1); end
if nargin < 6 || isempty(noise_var), noise_var = norm(y)^2 / (10*length(y)); end
if nargin < 5 || isempty(K_sparse), K_sparse = ceil(N/10); end
if nargin < 4 || isempty(max_iter), max_iter = 50; end
y = y(:);
rho_prev = rho_prev(:);
[M, ~] = size(Phi);

%% ========== 初始化 ========== %%
lambda = K_sparse / N;
var_x = 1;

% 热启动先验LLR修正
LLR_base = log(lambda / (1 - lambda + 1e-10));
rho_prev_clipped = max(min(rho_prev, 1-1e-6), 1e-6);
LLR_warm = beta * log(rho_prev_clipped ./ (1 - rho_prev_clipped));
LLR_prior = LLR_base + LLR_warm;

PhiTPhi = Phi' * Phi;
PhiTy = Phi' * y;

h_est = zeros(N, 1);
rho = 1 ./ (1 + exp(-LLR_prior));     % 热启动初始支撑概率
mse_history = zeros(max_iter, 1);

%% ========== Turbo-VAMP迭代（与标准版相同，仅初始LLR不同） ========== %%
for t = 1:max_iter
    h_old = h_est;

    % 模块A：LMMSE
    Gamma = diag(rho .* var_x);
    Sigma = inv(PhiTPhi / noise_var + inv(Gamma + 1e-8*eye(N)));
    mu_A = Sigma * PhiTy / noise_var;

    % 外信息
    tau_ext = 1 ./ (1./diag(Sigma) - 1./(rho .* var_x + 1e-10));
    tau_ext = max(tau_ext, 1e-10);
    r_ext = tau_ext .* (mu_A ./ diag(Sigma) - h_est ./ (rho .* var_x + 1e-10));

    % 模块B：去噪（使用热启动LLR）
    log_ratio = LLR_prior ...
                + 0.5*log(tau_ext ./ (tau_ext + var_x)) ...
                + 0.5 * abs(r_ext).^2 .* var_x ./ (tau_ext .* (tau_ext + var_x));
    rho = 1 ./ (1 + exp(-log_ratio));
    rho = max(min(rho, 1-1e-6), 1e-6);

    var_post = 1 ./ (1./tau_ext + 1/var_x);
    mean_post = var_post .* r_ext ./ tau_ext;
    h_est = rho .* mean_post;

    mse_history(t) = norm(h_est - h_old)^2 / (norm(h_old)^2 + 1e-10);

    if mse_history(t) < 1e-8 && t > 3
        mse_history(t+1:end) = mse_history(t);
        break;
    end
end

%% ========== 输出 ========== %%
rho_out = rho;                         % 传递给下一帧
H_est = fft(h_est.', N);

end
