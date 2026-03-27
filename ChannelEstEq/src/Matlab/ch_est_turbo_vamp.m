function [h_est, H_est, mse_history] = ch_est_turbo_vamp(y, Phi, N, max_iter, K_sparse, noise_var)
% 功能：Turbo-VAMP稀疏信道估计（结合VAMP和稀疏先验的Turbo框架）
% 版本：V1.0.0
% 输入：
%   y         - 观测向量 (Mx1)
%   Phi       - 测量矩阵 (MxN)
%   N         - 信道长度
%   max_iter  - 最大迭代次数 (默认 50)
%   K_sparse  - 稀疏度估计 (默认 ceil(N/10))
%   noise_var - 噪声方差
% 输出：
%   h_est       - 时域信道估计 (Nx1)
%   H_est       - 频域信道估计 (1xN)
%   mse_history - NMSE收敛历史 (max_iter x 1)

%% ========== 入参解析 ========== %%
if nargin < 6 || isempty(noise_var), noise_var = norm(y)^2 / (10*length(y)); end
if nargin < 5 || isempty(K_sparse), K_sparse = ceil(N/10); end
if nargin < 4 || isempty(max_iter), max_iter = 50; end
y = y(:);
[M, ~] = size(Phi);

%% ========== 预计算 ========== %%
lambda = K_sparse / N;                 % 先验稀疏率
var_x = 1;                            % 非零抽头先验方差

PhiTPhi = Phi' * Phi;
PhiTy = Phi' * y;

%% ========== 初始化 ========== %%
h_est = zeros(N, 1);
rho = lambda * ones(N, 1);            % 后验支撑概率
mse_history = zeros(max_iter, 1);

%% ========== Turbo-VAMP迭代 ========== %%
for t = 1:max_iter
    h_old = h_est;

    % 模块A：LMMSE估计
    Gamma = diag(rho .* var_x);
    Sigma = inv(PhiTPhi / noise_var + inv(Gamma + 1e-8*eye(N)));
    mu_A = Sigma * PhiTy / noise_var;

    % 外信息：A → B
    tau_ext_A = 1 ./ (1./diag(Sigma) - 1./(rho .* var_x + 1e-10));
    tau_ext_A = max(tau_ext_A, 1e-10);
    r_ext_A = tau_ext_A .* (mu_A ./ diag(Sigma) - h_est ./ (rho .* var_x + 1e-10));

    % 模块B：伯努利-高斯去噪
    log_ratio = log(lambda/(1-lambda + 1e-10)) ...
                + 0.5*log(tau_ext_A ./ (tau_ext_A + var_x)) ...
                + 0.5 * abs(r_ext_A).^2 .* var_x ./ (tau_ext_A .* (tau_ext_A + var_x));
    rho = 1 ./ (1 + exp(-log_ratio));
    rho = max(min(rho, 1-1e-6), 1e-6);

    var_post = 1 ./ (1./tau_ext_A + 1/var_x);
    mean_post = var_post .* r_ext_A ./ tau_ext_A;
    h_est = rho .* mean_post;

    mse_history(t) = norm(h_est - h_old)^2 / (norm(h_old)^2 + 1e-10);

    if mse_history(t) < 1e-8 && t > 3
        mse_history(t+1:end) = mse_history(t);
        break;
    end
end

H_est = fft(h_est.', N);

end
