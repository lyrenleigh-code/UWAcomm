function [x_hat, LLR_out, x_mean_out, eq_info] = eq_otfs_lmmse(Y_dd, h_dd, path_info, N, M, noise_var, max_iter, constellation, prior_mean, prior_var)
% 功能：OTFS LMMSE-IC均衡器——利用BCCB信道矩阵2D FFT对角化
% 版本：V1.1.0 — 修复：输出原始LMMSE估计(非星座解映射)，先验方差排除guard
% 输入：（与eq_otfs_mp完全兼容）
%   Y_dd          - 接收DD域帧 (NxM 复数)
%   h_dd          - DD域信道响应 (NxM 稀疏，仅用于兼容接口)
%   path_info     - 路径信息 .delay_idx, .doppler_idx, .gain, .num_paths
%   N, M          - DD域格点尺寸
%   noise_var     - 噪声方差 σ²_w
%   max_iter      - MMSE-IC迭代次数 (推荐1,由外层Turbo控制迭代)
%   constellation - 星座点 (默认 QPSK)
%   prior_mean    - 可选先验均值 (NxM, Turbo反馈)
%   prior_var     - 可选先验方差 (NxM或标量)
% 输出：
%   x_hat      - DD域硬判决 (NxM)
%   LLR_out    - 简化LLR (NxM)
%   x_mean_out - DD域LMMSE软估计 (NxM 复数, 原始高斯分布)
%   eq_info    - .nv_post(后验方差), .mu_bias(LMMSE偏置因子)
%
% 核心原理：
%   H = F^H·diag(d)·F (BCCB对角化), d = fft2(C)
%   LMMSE: x̂ = x̄ + ifft2(D*./(|D|²+λ) .* fft2(Y-H·x̄))
%   输出x̂是高斯分布: x̂ ~ N(μ·x, v_post), μ = 1-v_post
%   LLR = -2√2·Re(x̂)/v_post (精确QPSK LLR)

%% ========== 入参 ========== %%
if nargin < 10, prior_var = []; end
if nargin < 9, prior_mean = []; end
if nargin < 8 || isempty(constellation), constellation = [1+1j,1-1j,-1+1j,-1-1j]/sqrt(2); end
if nargin < 7 || isempty(max_iter), max_iter = 1; end
if nargin < 6 || isempty(noise_var), noise_var = 0.01; end
nv = max(noise_var, 1e-10);

%% ========== 1. BCCB频域特征值 ========== %%
C = zeros(N, M);
for p = 1:path_info.num_paths
    kk = mod(path_info.doppler_idx(p), N) + 1;
    ll = mod(path_info.delay_idx(p), M) + 1;
    C(kk, ll) = C(kk, ll) + path_info.gain(p);
end
D = fft2(C);
D_conj = conj(D);
mu = abs(D).^2;

%% ========== 2. 初始化先验 ========== %%
if ~isempty(prior_mean)
    x_bar = prior_mean;
else
    x_bar = zeros(N, M);
end

% v_x: 先验方差（标量，BCCB要求均匀）
% 关键：只用有效数据位置的方差，排除guard(1e-6)的污染
if ~isempty(prior_var)
    if isscalar(prior_var)
        v_x = max(prior_var, 0.01);
    else
        pv_vec = prior_var(:);
        valid = pv_vec > 0.001;  % 排除guard(=1e-6)和零值
        if any(valid)
            v_x = max(mean(pv_vec(valid)), 0.01);
        else
            v_x = 1;
        end
    end
else
    v_x = 1;
end

%% ========== 3. LMMSE-IC迭代 ========== %%
for iter = 1:max_iter
    lambda = nv / max(v_x, 1e-10);

    % 残差: E = Y - H·x̄
    Hx_bar = ifft2(D .* fft2(x_bar));
    E = Y_dd - Hx_bar;

    % LMMSE滤波: W = D*/(|D|²+λ)
    W = D_conj ./ (mu + lambda);
    x_mmse = x_bar + ifft2(W .* fft2(E));

    % 后验方差 (BCCB: 所有符号方差相同 = 精确值)
    v_post = mean(nv ./ (mu(:) + lambda));
    v_post = max(v_post, 1e-10);

    % 偏置因子: μ = 1 - v_post (LMMSE收缩)
    mu_bias = 1 - v_post;

    % IC更新：用星座解映射生成下轮先验(仅内部IC用，不输出)
    if iter < max_iter
        x_new = zeros(N, M);
        sigma_sum = 0;
        for k = 1:N
            for l = 1:M
                dist2 = abs(constellation - x_mmse(k,l)).^2;
                log_phi = -dist2 / v_post;
                log_phi = log_phi - max(log_phi);
                phi = exp(log_phi);
                phi = phi / max(sum(phi), 1e-20);
                x_new(k,l) = sum(constellation .* phi);
                sigma_sum = sigma_sum + sum(abs(constellation - x_new(k,l)).^2 .* phi);
            end
        end
        x_bar = x_new;
        v_x = max(sigma_sum / (N*M), 0.01);
    end
end

%% ========== 4. 输出：原始LMMSE估计（高斯分布） ========== %%
x_mean_out = x_mmse;  % 关键：输出原始LMMSE，非星座解映射！

% 硬判决（从LMMSE输出）
x_hat = zeros(N, M);
for k = 1:N
    for l = 1:M
        [~, idx] = min(abs(x_mmse(k,l) - constellation).^2);
        x_hat(k,l) = constellation(idx);
    end
end

LLR_out = real(x_mmse);
eq_info.nv_post = v_post;
eq_info.mu_bias = mu_bias;
eq_info.v_x = v_x;
eq_info.num_iter = max_iter;

end
