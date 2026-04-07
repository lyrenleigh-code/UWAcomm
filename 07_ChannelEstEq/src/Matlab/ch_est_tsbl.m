function [H_tv, h_snapshots, gamma_tv, info] = ch_est_tsbl(Y_multi, Phi, N, T, max_iter, tol, alpha_ar)
% 功能：T-SBL（时序稀疏贝叶斯学习）时变信道估计
% 版本：V2.0.0
% 输入：
%   Y_multi  - 多快照观测矩阵 (M×T, 每列一个时刻的观测)
%   Phi      - 测量矩阵 (M×N, 所有快照共用同一导频结构)
%   N        - 信道长度（抽头数）
%   T        - 快照数（时间采样点数）
%   max_iter - 最大EM迭代次数 (默认 50)
%   tol      - 收敛阈值 (默认 1e-5)
%   alpha_ar - 时间相关系数 (默认 0.95, AR(1)模型 h(t)=α·h(t-1)+w)
% 输出：
%   H_tv        - 时变频域信道 (N×T, 每列一个时刻的H)
%   h_snapshots - 时变时域信道 (N×T, 每列一个时刻的h)
%   gamma_tv    - 超参数 (N×1, 各抽头共享方差)
%   info        - 估计信息
%       .n_iter     : 实际迭代次数
%       .support    : 最终稀疏支撑集
%       .sigma2     : 估计噪声方差
%       .K_detected : 检测到的径数
%
% 备注：
%   V2改进：
%   1. LS warm-start初始化（用LS解初始化gamma）
%   2. gamma/sigma2数值截断（防发散）
%   3. Woodbury恒等式避免大矩阵求逆
%   4. 渐进剪枝（gamma<阈值的抽头提前置零）
%   要求：所有快照共用同一Phi（如重复导频）

%% ========== 1. 入参解析 ========== %%
if nargin < 7 || isempty(alpha_ar), alpha_ar = 0.95; end
if nargin < 6 || isempty(tol), tol = 1e-5; end
if nargin < 5 || isempty(max_iter), max_iter = 50; end
if nargin < 4 || isempty(T), T = size(Y_multi, 2); end

[M, ~] = size(Phi);

%% ========== 2. 参数校验 ========== %%
if isempty(Y_multi), error('观测矩阵不能为空！'); end
if size(Y_multi, 1) ~= M, error('Y_multi行数(%d)须与Phi行数(%d)一致！', size(Y_multi,1), M); end

%% ========== 3. LS warm-start初始化 ========== %%
% 对每个快照做LS → 平均功率作为gamma初始值
reg = max(1e-3, norm(Phi'*Phi,'fro')*1e-4);
h_ls = (Phi' * Phi + reg*eye(N)) \ (Phi' * Y_multi);  % N×T
gamma = mean(abs(h_ls).^2, 2) + 1e-8;  % N×1
% 初始剪枝：只保留功率最大的2*sqrt(N)个抽头
[~, sort_idx] = sort(gamma, 'descend');
K_init = min(round(2*sqrt(N)), N);
gamma(sort_idx(K_init+1:end)) = 1e-12;
sigma2 = 0;
for tt = 1:T
    sigma2 = sigma2 + norm(Y_multi(:,tt) - Phi*h_ls(:,tt))^2;
end
sigma2 = sigma2 / (M*T);
sigma2 = max(sigma2, 1e-8);

% 时间相关矩阵 B: B_{ij} = α^|i-j| (Toeplitz AR(1))
B = toeplitz(alpha_ar.^(0:T-1));
B_inv = inv(B + 1e-8*eye(T));

% 预计算 Phi'Phi
PhiH_Phi = Phi' * Phi;  % N×N
phi_col_power = real(diag(PhiH_Phi));  % 各列能量

%% ========== 4. EM迭代 ========== %%
h_snapshots = h_ls;  % warm-start
active = true(N, 1);  % 活跃抽头标记
Sigma_diag = zeros(N, T);

for iter = 1:max_iter
    gamma_old = gamma;

    %% E步：逐抽头更新后验（coordinate ascent）
    for i = 1:N
        if ~active(i), continue; end

        phi_i = Phi(:, i);
        pw_i = phi_col_power(i);
        if pw_i < 1e-10, active(i)=false; h_snapshots(i,:)=0; continue; end

        % 残差：去除第i抽头之外的贡献
        H_other = h_snapshots;
        H_other(i,:) = 0;
        R_i = Y_multi - Phi * H_other;  % M×T

        % 投影到phi_i: r_proj(t) = phi_i' * R_i(:,t)
        r_proj = phi_i' * R_i;  % 1×T

        % 后验精度: Λ = (pw_i/σ²)·I_T + (1/γ_i)·B⁻¹
        lambda_obs = pw_i / sigma2;
        Lambda = lambda_obs * eye(T) + (1/gamma(i)) * B_inv;

        % 后验协方差和均值（T×T系统，T通常很小）
        Sigma_i = inv(Lambda + 1e-10*eye(T));
        Sigma_i = (Sigma_i + Sigma_i') / 2;  % 强制对称
        mu_i = Sigma_i * (lambda_obs * r_proj.');

        h_snapshots(i,:) = mu_i.';
        Sigma_diag(i,:) = max(real(diag(Sigma_i)).', 0);
    end

    %% M步：更新gamma（联合稀疏）
    for i = 1:N
        if ~active(i), gamma(i)=1e-12; continue; end
        mu_i = h_snapshots(i,:).';
        % γ_i = (μ_i'·B⁻¹·μ_i + tr(Σ_i·B⁻¹)) / T
        gamma(i) = real(mu_i' * B_inv * mu_i + sum(Sigma_diag(i,:)' .* diag(B_inv))) / T;
        gamma(i) = max(gamma(i), 1e-12);
        gamma(i) = min(gamma(i), 1e4);  % 防爆炸
    end

    %% 更新sigma2
    residual = Y_multi - Phi * h_snapshots;
    res_power = sum(abs(residual(:)).^2);
    trace_term = 0;
    for i = 1:N
        if active(i)
            trace_term = trace_term + phi_col_power(i) * sum(Sigma_diag(i,:));
        end
    end
    sigma2 = (res_power + trace_term) / (M * T);
    sigma2 = max(sigma2, 1e-8);
    sigma2 = min(sigma2, norm(Y_multi(:))^2 / (M*T));  % 不超过信号总功率

    %% 渐进剪枝
    prune_thresh = max(gamma(active)) * 1e-6;
    for i = 1:N
        if active(i) && gamma(i) < prune_thresh
            active(i) = false;
            h_snapshots(i,:) = 0;
            gamma(i) = 1e-12;
        end
    end

    %% 收敛检查
    if norm(gamma - gamma_old) / (norm(gamma_old) + 1e-10) < tol
        break;
    end
end

%% ========== 5. 输出 ========== %%
threshold = max(gamma) * 1e-3;
support = find(gamma >= threshold);
h_snapshots(gamma < threshold, :) = 0;

H_tv = zeros(N, T);
for t = 1:T
    H_tv(:, t) = fft(h_snapshots(:, t), N);
end

gamma_tv = gamma;
info.n_iter = iter;
info.support = support;
info.sigma2 = sigma2;
info.K_detected = length(support);
info.gamma = gamma;

end
