function [h_est, H_est] = ch_est_gamp(y, Phi, N, max_iter, noise_var)
% 功能：GAMP（广义近似消息传递）信道估计
% 版本：V1.0.0
% 输入：
%   y         - 观测向量 (Mx1)
%   Phi       - 测量矩阵 (MxN)
%   N         - 信道长度
%   max_iter  - 最大迭代次数 (默认 100)
%   noise_var - 噪声方差 (默认自动估计)
% 输出：
%   h_est - 时域信道估计 (Nx1)
%   H_est - 频域信道估计 (1xN)
%
% 备注：
%   - GAMP支持非高斯先验和非高斯似然
%   - 此处使用伯努利-高斯先验（稀疏信道）+ 高斯似然

%% ========== 入参解析 ========== %%
if nargin < 5 || isempty(noise_var), noise_var = norm(y)^2 / (10*length(y)); end
if nargin < 4 || isempty(max_iter), max_iter = 100; end
y = y(:);
[M, ~] = size(Phi);

%% ========== 初始化 ========== %%
lambda = 0.1;                          % 先验稀疏率
var_x = 1;                             % 先验方差

x_hat = zeros(N, 1);                  % 信号估计
tau_x = var_x * ones(N, 1);           % 信号方差

Phi2 = abs(Phi).^2;                   % 逐元素平方

%% ========== GAMP迭代 ========== %%
s_hat = zeros(M, 1);

for t = 1:max_iter
    x_old = x_hat;

    % 输出线性步
    tau_p = Phi2 * tau_x;
    p_hat = Phi * x_hat - tau_p .* s_hat;

    % 输出非线性步（高斯似然）
    tau_s = 1 ./ (tau_p + noise_var);
    s_hat = (y - p_hat) .* tau_s;

    % 输入线性步
    tau_r = 1 ./ (Phi2' * tau_s);
    r_hat = x_hat + tau_r .* (Phi' * s_hat);

    % 输入非线性步（伯努利-高斯先验）
    [x_hat, tau_x] = bg_denoiser(r_hat, tau_r, lambda, var_x);

    % 收敛
    if norm(x_hat - x_old) / (norm(x_old) + 1e-10) < 1e-6
        break;
    end
end

h_est = x_hat;
H_est = fft(h_est.', N);

end

% --------------- 伯努利-高斯去噪器 --------------- %
function [x_hat, tau_x] = bg_denoiser(r, tau_r, lambda, var_x)
N = length(r);
% 后验活跃概率
log_ratio = log(lambda/(1-lambda)) + 0.5*log(tau_r./(tau_r + var_x)) ...
            + 0.5 * abs(r).^2 .* var_x ./ (tau_r .* (tau_r + var_x));
pi_post = 1 ./ (1 + exp(-log_ratio));

% 后验均值和方差
var_post = 1 ./ (1./tau_r + 1/var_x);
mean_post = var_post .* r ./ tau_r;

x_hat = pi_post .* mean_post;
tau_x = pi_post .* (var_post + abs(mean_post).^2) - abs(x_hat).^2;
tau_x = max(tau_x, 1e-10);
end
