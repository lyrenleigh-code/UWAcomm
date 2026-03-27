function [h_est, H_est, mse_history] = ch_est_vamp(y, Phi, N, max_iter, noise_var)
% 功能：VAMP（变分近似消息传递）信道估计
% 版本：V1.1.0
% 输入：
%   y         - 观测向量 (Mx1)
%   Phi       - 测量矩阵 (MxN)
%   N         - 信道长度
%   max_iter  - 最大迭代次数 (默认 100)
%   noise_var - 噪声方差
% 输出：
%   h_est       - 时域信道估计 (Nx1)
%   H_est       - 频域信道估计 (1xN)
%   mse_history - 收敛历史
%
% 备注：
%   - VAMP交替在LMMSE模块和去噪模块之间传递外信息
%   - 对测量矩阵条件更鲁棒（不要求iid高斯，区别于AMP）
%   - 使用伯努利-高斯去噪器实现稀疏先验

%% ========== 入参解析 ========== %%
if nargin < 5 || isempty(noise_var), noise_var = norm(y)^2 / (10*length(y)); end
if nargin < 4 || isempty(max_iter), max_iter = 100; end
y = y(:);
[M, ~] = size(Phi);

%% ========== 预计算 ========== %%
PhiTPhi = Phi' * Phi;
PhiTy = Phi' * y;

% 稀疏先验参数
lambda = 0.1;                          % 先验稀疏率
var_x = 1;                            % 非零抽头先验方差

%% ========== 初始化 ========== %%
r1 = zeros(N, 1);                     % 模块1→模块2的外信息均值
gamma1 = 1e-2;                        % 模块1→模块2的外信息精度

mse_history = zeros(max_iter, 1);

%% ========== VAMP迭代 ========== %%
for t = 1:max_iter
    h_old = r1;

    % ===== 模块1：LMMSE估计器 =====
    % x1 = (Phi'*Phi/sigma^2 + gamma1*I)^{-1} * (Phi'*y/sigma^2 + gamma1*r1)
    Sigma1 = inv(PhiTPhi / noise_var + gamma1 * eye(N));
    x1 = Sigma1 * (PhiTy / noise_var + gamma1 * r1);

    % 发散度 alpha1 = gamma1/N * trace(Sigma1)
    alpha1 = gamma1 * trace(Sigma1) / N;

    % 外信息传递：模块1 → 模块2
    eta1 = gamma1 / (1 - alpha1 + 1e-10);
    gamma2 = max(eta1 - gamma1, 1e-6);
    r2 = (eta1 * x1 - gamma1 * r1) / (gamma2 + 1e-10);

    % ===== 模块2：伯努利-高斯去噪器 =====
    tau2 = 1 / gamma2;                 % 等效噪声方差

    % 后验支撑概率
    log_ratio = log(lambda / (1 - lambda + 1e-10)) ...
                + 0.5 * log(tau2 / (tau2 + var_x)) ...
                + 0.5 * abs(r2).^2 .* var_x ./ (tau2 * (tau2 + var_x));
    pi_post = 1 ./ (1 + exp(-log_ratio));
    pi_post = max(min(pi_post, 1-1e-6), 1e-6);

    % 后验均值和方差
    var_post = 1 ./ (gamma2 + 1/var_x);
    mean_post = var_post .* (gamma2 * r2);
    x2 = pi_post .* mean_post;

    % 发散度 alpha2 = (1/N) * sum(d x2 / d r2)
    alpha2 = mean(pi_post .* gamma2 .* var_post);

    % 外信息传递：模块2 → 模块1
    eta2 = gamma2 / (1 - alpha2 + 1e-10);
    gamma1 = max(eta2 - gamma2, 1e-6);
    r1 = (eta2 * x2 - gamma2 * r2) / (gamma1 + 1e-10);

    % 收敛检查
    mse_history(t) = norm(x2 - h_old)^2 / (norm(h_old)^2 + 1e-10);
    if mse_history(t) < 1e-8 && t > 5
        mse_history(t+1:end) = mse_history(t);
        break;
    end
end

h_est = x2;
H_est = fft(h_est.', N);

end
