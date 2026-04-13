function [x_hat, LLR_out, x_mean_out, eq_info] = eq_otfs_uamp(Y_dd, h_dd, path_info, N, M, noise_var, max_iter, constellation, prior_mean, prior_var)
% 功能：OTFS UAMP均衡器——Unitary AMP + Onsager修正 + EM噪声估计
% 版本：V1.0.0
% 输入：（与eq_otfs_lmmse完全兼容）
%   Y_dd          - 接收DD域帧 (NxM 复数)
%   h_dd          - DD域信道响应 (NxM, 兼容接口)
%   path_info     - 路径信息 .delay_idx, .doppler_idx, .gain, .num_paths
%   N, M          - DD域格点尺寸
%   noise_var     - 噪声方差 σ²_w (初始估计, EM会自动更新)
%   max_iter      - UAMP内部迭代次数 (默认5, 推荐5~10)
%   constellation - 星座点 (默认 QPSK)
%   prior_mean    - 可选先验均值 (NxM, Turbo反馈)
%   prior_var     - 可选先验方差 (NxM或标量)
% 输出：
%   x_hat      - DD域硬判决 (NxM)
%   LLR_out    - 简化LLR (NxM)
%   x_mean_out - 解噪器输入r (NxM, 高斯分布, 供LLR计算)
%   eq_info    - .nv_post, .mu_bias, .v_x, .nv_est, .num_iter, .converged
%
% 核心原理：
%   H = F^H·D·F (BCCB), D = fft2(C), F = 2D-DFT
%   UAMP交替执行：
%     Module A (频域线性估计):
%       τ_p = E[|d|²]·τ_x
%       p = D·F·x̂ - (τ_p/τ_p_prev)·s   ← Onsager修正项
%       s = (z-p)/(τ_p+σ²),  z = F·y
%       τ_r = 1/(E[|d|²]·τ_s)
%       r = x̂ + τ_r·F^H·(D*·s)
%     Module B (DD域MMSE解噪):
%       x̂_i = E[x|r_i, τ_r] (星座约束MMSE)
%       τ_x = E[var(x|r,τ_r)]
%     EM: σ² ← E[|z-D·Fx̂|²] - E[|d|²]·τ_x
%
%   vs LMMSE-IC的关键优势：
%     1. Onsager修正防SIC发散 → 多轮内部迭代安全
%     2. 非线性MMSE解噪 → 星座约束更精确
%     3. EM噪声自适应 → 不依赖外部nv精度
%
% 参考：Yuan et al. 2022, "Iterative Detection for OTFS with UAMP"

%% ========== 入参 ========== %%
if nargin < 10, prior_var = []; end
if nargin < 9, prior_mean = []; end
if nargin < 8 || isempty(constellation), constellation = [1+1j,1-1j,-1+1j,-1-1j]/sqrt(2); end
if nargin < 7 || isempty(max_iter), max_iter = 5; end
if nargin < 6 || isempty(noise_var), noise_var = 0.01; end
nv = max(noise_var, 1e-10);
NM = N * M;
n_const = length(constellation);

%% ========== 1. BCCB频域特征值 ========== %%
C = zeros(N, M);
for p = 1:path_info.num_paths
    kk = mod(path_info.doppler_idx(p), N) + 1;
    ll = mod(path_info.delay_idx(p), M) + 1;
    C(kk, ll) = C(kk, ll) + path_info.gain(p);
end
D = fft2(C);
d_abs2 = abs(D).^2;
d_conj = conj(D);
mean_d2 = mean(d_abs2(:));

%% ========== 2. 频域观测 ========== %%
z = fft2(Y_dd);

%% ========== 3. 初始化 ========== %%
% 架构：热启动SIC + 平坦解噪器
%   - x_est = prior_mean: 热启动减少ISI（SIC更准确）
%   - tau_x = prior_var: 匹配SIC置信度
%   - 解噪器始终用平坦星座先验（不用Turbo先验，防锁死）
%   - Turbo增益来自：更好的SIC → 更干净的信道LLR → 更好的编码增益
if ~isempty(prior_mean)
    x_est = prior_mean;
    if ~isempty(prior_var)
        if isscalar(prior_var)
            tau_x = max(prior_var, 0.01);
        else
            pv_vec = prior_var(:);
            valid = pv_vec > 0.001;
            if any(valid)
                tau_x = max(mean(pv_vec(valid)), 0.01);
            else
                tau_x = 1;
            end
        end
    else
        tau_x = 0.5;
    end
else
    x_est = zeros(N, M);
    tau_x = mean(abs(constellation).^2);
end

s = zeros(N, M);
tau_p_prev = Inf;
nv_init = nv;

%% ========== 4. UAMP迭代 ========== %%
for iter = 1:max_iter
    %% ---- Module A: 频域线性估计 ----
    x_tilde = fft2(x_est);
    tau_p = mean_d2 * tau_x;

    % Onsager修正预测
    if isinf(tau_p_prev)
        p = D .* x_tilde;
    else
        onsager = tau_p / max(tau_p_prev, 1e-20);
        p = D .* x_tilde - onsager * s;
    end

    % 频域残差
    tau_s = 1 / (tau_p + nv);
    s = tau_s * (z - p);

    % 解噪器有效方差
    tau_r = 1 / max(mean_d2 * tau_s, 1e-20);

    % 解噪器输入 (DD域)
    r = x_est + tau_r * ifft2(d_conj .* s);

    tau_p_prev = tau_p;

    %% ---- Module B: 非线性MMSE解噪器（平坦星座先验） ----
    % 关键：始终用平坦先验，Turbo先验不进入解噪器
    % 这防止非线性解噪器锁死在错误星座点（Turbo发散的根因）
    x_new = zeros(N, M);
    tau_sum = 0;

    for k = 1:N
        for l = 1:M
            % 观测似然: r(k,l) ~ CN(x, τ_r)
            dist2 = abs(constellation - r(k,l)).^2;
            log_lik = -dist2 / max(tau_r, 1e-10);

            % 后验 (纯观测, 平坦先验)
            log_lik = log_lik - max(log_lik);
            post = exp(log_lik);
            post = post / max(sum(post), 1e-20);

            % MMSE估计
            x_new(k,l) = sum(constellation .* post);
            tau_sum = tau_sum + sum(abs(constellation - x_new(k,l)).^2 .* post);
        end
    end

    tau_x = max(tau_sum / NM, 1e-10);
    x_est = x_new;

    %% ---- EM噪声方差更新 ----
    x_tilde_new = fft2(x_est);
    res = z - D .* x_tilde_new;
    nv_em = mean(abs(res(:)).^2) - mean_d2 * tau_x;
    nv_em = max(nv_em, nv_init * 0.1);    % 下界: 初始估计10%
    nv_em = min(nv_em, nv_init * 10);      % 上界: 初始估计10x
    nv = 0.5 * nv + 0.5 * nv_em;
end

%% ========== 5. 输出 ========== %%
x_mean_out = r;  % 解噪器输入(高斯), 供外部LLR计算

% 硬判决
x_hat = zeros(N, M);
for k = 1:N
    for l = 1:M
        [~, idx] = min(abs(r(k,l) - constellation).^2);
        x_hat(k,l) = constellation(idx);
    end
end

LLR_out = real(r);

eq_info.nv_post = tau_r;
eq_info.mu_bias = 1 - tau_r;
eq_info.v_x = tau_x;
eq_info.nv_est = nv;
eq_info.nv_init = nv_init;
eq_info.num_iter = max_iter;

end
