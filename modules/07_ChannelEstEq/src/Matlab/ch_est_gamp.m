function [h_est, H_est] = ch_est_gamp(y, Phi, N, max_iter, noise_var)
% 功能：GAMP（广义近似消息传递）信道估计
% 版本：V1.4.0（2026-04-23：偏向 LS 残差比较 res_gamp > 0.8*res_ls 即选 LS；
%               V1.3 CV split 砍 trn 20% 让 LS 自身条件数恶化，反引入新灾难；
%               V1.4 回退到 in-sample，要求 GAMP 必须显著优才用，否则偏 LS）
%       V1.3.0（2026-04-23）— 已撤回：CV hold-out 残差比较；obs/dim 不够
%       V1.2.0（2026-04-23：GAMP+LS 双跑取小残差，彻底消除 6 径全活跃
%               信道 ~10% 灾难率；V1.1 单 fallback 仅救 80%）
%       V1.1.0（2026-04-23：加 divergence guard + Tikhonov LS fallback，
%               解决 SC-FDE 静态 6 径信道 ~10% (TX bits, noise) 组合下
%               GAMP 收敛到错误固定点导致 |h_est|=10^25 数值发散）
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
%   - V1.1：BG prior（lambda=0.1，10% 稀疏假设）对 custom6 6 径全活跃信道
%     misspec，~10% 的 (TX bits, noise) 组合下 GAMP 不收敛 → 输出幅度无界
%   - V1.1 修复策略：检测发散后回退到 Tikhonov 正则化 LS
%   - V1.2：单 fallback 还剩 6.7% 灾难（GAMP 看似收敛但残差大）；改双跑
%     比较 ‖y-Φx‖² 自动选优。稀疏信道 GAMP 残差小、dense 信道 LS 残差小

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

    % V1.1 divergence guard：x_hat 范数爆炸时 break，转 LS fallback
    if any(~isfinite(x_hat)) || max(abs(x_hat)) > 1e6
        x_hat(:) = NaN;   % flag 发散
        break;
    end
end

% V1.2 双跑：始终算 LS Tikhonov 解
% λ = noise_var 是经典 ridge regression 选择
lambda_ridge = max(noise_var, 1e-6);
x_ls = (Phi' * Phi + lambda_ridge * eye(N)) \ (Phi' * y);

% V1.4 偏向 LS：GAMP 发散直接选 LS；否则要求 GAMP 残差比 LS 小至少 20% 才选 GAMP
% 理由：in-sample 残差有过拟合 bias（GAMP 拟合噪声 → 残差小但解错），加 0.8
%       系数让 GAMP 必须显著优才用，否则偏 LS（dense 信道下 LS 普遍更稳）
% 阈值 0.8 来源：经验值，留 20% margin 给过拟合现象
gamp_invalid = any(~isfinite(x_hat)) || max(abs(x_hat)) > 1e3;
if gamp_invalid
    x_hat = x_ls;
else
    res_gamp = norm(y - Phi * x_hat)^2;
    res_ls   = norm(y - Phi * x_ls)^2;
    if res_gamp > 0.8 * res_ls   % GAMP 不显著优 → 选 LS
        x_hat = x_ls;
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
