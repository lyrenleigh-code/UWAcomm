function [h_est, H_est, mse_history] = ch_est_vamp(y, Phi, N, max_iter, noise_var, K_sparse)
% 功能：VAMP（变分近似消息传递）信道估计
% 版本：V1.3.0
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
%   - VAMP交替在LMMSE模块和BG去噪模块之间传递外信息
%   - M<N欠定场景用Woodbury恒等式提高数值稳定性
%   - 外信息精度加阻尼和上下界保护防止发散

%% ========== 入参解析 ========== %%
if nargin < 6, K_sparse = []; end
if nargin < 5 || isempty(noise_var), noise_var = norm(y)^2 / (10*length(y)); end
if nargin < 4 || isempty(max_iter), max_iter = 100; end
y = y(:);
[M, ~] = size(Phi);

%% ========== 先验参数 ========== %%
if ~isempty(K_sparse) && K_sparse > 0
    lambda = K_sparse / N;
    var_x = max((norm(y)^2/M - noise_var) / (lambda + 1e-10), 0.1);
else
    lambda = 0.05;
    var_x = norm(y)^2 / (M * 0.05);
end

%% ========== 预计算（Woodbury：当M<N时更稳定） ========== %%
% inv(Phi'Phi/σ² + γI) = (1/γ)(I - Phi'(σ²γI + PhiPhi')^{-1}Phi) 当γ>0
PhiPhiT = Phi * Phi';                 % MxM（比NxN小）
PhiTy = Phi' * y;

damping = 0.5;                        % 阻尼系数
gamma_max = 1e4;                       % 精度上界
gamma_min = 1e-6;                      % 精度下界

%% ========== 初始化 ========== %%
r1 = zeros(N, 1);
gamma1 = max(min(1 / var_x, gamma_max), gamma_min);

mse_history = zeros(max_iter, 1);
x2 = zeros(N, 1);

%% ========== VAMP迭代 ========== %%
for t = 1:max_iter
    h_old = x2;

    % ===== 模块1：LMMSE估计器（Woodbury形式） =====
    % Sigma1 = (1/γ1)(I - Phi'(σ²γ1 I_M + PhiPhi')^{-1} Phi)
    A = noise_var * gamma1 * eye(M) + PhiPhiT;
    A_inv_Phi = A \ Phi;               % Mx N
    x1 = (PhiTy / noise_var + gamma1 * r1) / gamma1 ...
         - Phi' * (A \ (Phi * (PhiTy / noise_var + gamma1 * r1))) / gamma1;

    % 简化：直接用标准形式（小规模可承受）
    Sigma1_diag = 1/gamma1 - (1/gamma1^2) * sum((Phi' * inv(A)) .* Phi', 2);
    Sigma1_diag = max(Sigma1_diag, 1e-10);

    % 发散度
    alpha1 = gamma1 * mean(Sigma1_diag);
    alpha1 = min(alpha1, 0.99);        % 钳位防止eta1爆炸

    % 外信息传递：模块1 → 模块2
    eta1 = gamma1 / (1 - alpha1);
    gamma2_new = eta1 - gamma1;
    gamma2_new = max(min(gamma2_new, gamma_max), gamma_min);
    gamma2 = gamma2_new;

    r2 = (eta1 * x1 - gamma1 * r1) / (gamma2 + 1e-10);

    % ===== 模块2：伯努利-高斯去噪器 =====
    tau2 = 1 / gamma2;

    % 后验支撑概率
    log_ratio = log(lambda / (1 - lambda + 1e-10)) ...
                + 0.5 * log(tau2 / (tau2 + var_x + 1e-10)) ...
                + 0.5 * abs(r2).^2 .* var_x ./ (tau2 * (tau2 + var_x) + 1e-10);
    log_ratio = max(min(log_ratio, 30), -30);  % 防止exp溢出
    pi_post = 1 ./ (1 + exp(-log_ratio));

    % 后验均值和方差
    var_post = 1 / (gamma2 + 1/var_x);
    mean_post = var_post * gamma2 * r2;
    x2 = pi_post .* mean_post;

    % 发散度
    alpha2 = mean(pi_post) * gamma2 * var_post;
    alpha2 = min(alpha2, 0.99);

    % 外信息传递：模块2 → 模块1（加阻尼）
    eta2 = gamma2 / (1 - alpha2);
    gamma1_new = eta2 - gamma2;
    gamma1_new = max(min(gamma1_new, gamma_max), gamma_min);
    gamma1 = damping * gamma1_new + (1 - damping) * gamma1;  % 阻尼

    r1_new = (eta2 * x2 - gamma2 * r2) / (gamma1_new + 1e-10);
    r1 = damping * r1_new + (1 - damping) * r1;              % 阻尼

    % EM更新先验（每10次）
    if mod(t, 10) == 0
        lambda = max(min(mean(pi_post), 0.5), 1e-3);
        active_moment = pi_post .* (abs(mean_post).^2 + var_post);
        if sum(pi_post) > 0.1
            var_x = max(sum(active_moment) / (sum(pi_post) + 1e-10), 0.01);
        end
    end

    % 收敛检查
    mse_history(t) = norm(x2 - h_old)^2 / (norm(h_old)^2 + 1e-10);
    if mse_history(t) < 1e-8 && t > 10
        mse_history(t+1:end) = mse_history(t);
        break;
    end
end

h_est = x2;
H_est = fft(h_est.', N);

end
