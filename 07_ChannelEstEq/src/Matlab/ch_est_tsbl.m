function [H_tv, h_snapshots, gamma_tv, info] = ch_est_tsbl(Y_multi, Phi, N, T, max_iter, tol, alpha_ar)
% 功能：T-SBL（时序稀疏贝叶斯学习）时变信道估计
% 版本：V1.0.0
% 输入：
%   Y_multi  - 多快照观测矩阵 (M×T, 每列一个时刻的观测)
%   Phi      - 测量矩阵 (M×N, 所有快照共用)
%   N        - 信道长度（抽头数）
%   T        - 快照数（时间采样点数）
%   max_iter - 最大EM迭代次数 (默认 50)
%   tol      - 收敛阈值 (默认 1e-6)
%   alpha_ar - 时间相关系数 (默认 0.99, AR(1)模型 h(t)=α·h(t-1)+w)
% 输出：
%   H_tv        - 时变频域信道 (N×T, 每列一个时刻的H)
%   h_snapshots - 时变时域信道 (N×T, 每列一个时刻的h)
%   gamma_tv    - 时变超参数 (N×T, 各抽头各时刻的方差)
%   info        - 估计信息
%       .n_iter     : 实际迭代次数
%       .support    : 最终稀疏支撑集（活跃抽头索引）
%       .sigma2     : 估计噪声方差
%
% 备注：
%   T-SBL扩展SBL到多快照时变场景：
%   - 联合稀疏：所有时刻共享相同的稀疏支撑集（组稀疏）
%   - 时间相关：相邻时刻的信道增益满足AR(1)模型
%   - EM框架：E步计算后验均值/协方差, M步更新超参数
%   - 对比SBL：SBL是T-SBL在T=1时的特例
%   - 对比M-SBL：M-SBL假设时间独立, T-SBL建模时间相关
%   复杂度：O(iter × T × N² × M)

%% ========== 1. 入参解析 ========== %%
if nargin < 7 || isempty(alpha_ar), alpha_ar = 0.99; end
if nargin < 6 || isempty(tol), tol = 1e-6; end
if nargin < 5 || isempty(max_iter), max_iter = 50; end
if nargin < 4 || isempty(T), T = size(Y_multi, 2); end

[M, ~] = size(Phi);

%% ========== 2. 参数校验 ========== %%
if isempty(Y_multi), error('观测矩阵不能为空！'); end
if size(Y_multi, 1) ~= M, error('Y_multi行数(%d)须与Phi行数(%d)一致！', size(Y_multi,1), M); end
if size(Y_multi, 2) ~= T, error('Y_multi列数(%d)须与T(%d)一致！', size(Y_multi,2), T); end

%% ========== 3. 初始化 ========== %%
% 超参数（各抽头方差，联合稀疏→所有时刻共享）
gamma = ones(N, 1);
% 噪声方差初始估计
sigma2 = norm(Y_multi(:))^2 / (10 * M * T);
% 时间相关矩阵: B_{ij} = α^|i-j| (Toeplitz)
B = zeros(T, T);
for i = 1:T
    for j = 1:T
        B(i,j) = alpha_ar^abs(i-j);
    end
end
B_inv = inv(B + 1e-10*eye(T));

%% ========== 4. EM迭代 ========== %%
h_snapshots = zeros(N, T);
Sigma_diag = zeros(N, T);  % 后验方差对角元

for iter = 1:max_iter
    gamma_old = gamma;

    %% E步：逐抽头计算后验（利用组稀疏+时间相关结构）
    for i = 1:N
        if gamma(i) < 1e-12
            % 抽头已被置零
            h_snapshots(i,:) = 0;
            Sigma_diag(i,:) = 0;
            continue;
        end

        % 第i个抽头的跨时刻后验
        % 观测模型: Y_multi = Phi * H + noise
        % 第i个抽头贡献: Y_i = phi_i * h_i' + (其余径贡献)
        phi_i = Phi(:, i);  % M×1
        phi_power = real(phi_i' * phi_i);

        % 残差（去除第i个抽头外的所有径贡献）
        H_other = h_snapshots;
        H_other(i,:) = 0;
        R_i = Y_multi - Phi * H_other;  % M×T

        % 第i个抽头的T个时刻联合后验
        % 先验协方差: gamma(i) * B (T×T)
        % 观测: r_i(t) = phi_i * h_i(t) + noise, t=1..T
        % 等效: r_vec = (phi_power) * h_i_vec + noise_vec
        r_proj = phi_i' * R_i;  % 1×T (投影到phi_i方向)

        % 后验精度矩阵: Λ = phi_power/σ² · I_T + 1/(γ_i) · B⁻¹
        Lambda = (phi_power / sigma2) * eye(T) + (1/gamma(i)) * B_inv;
        Sigma_i = inv(Lambda);  % T×T 后验协方差

        % 后验均值: μ_i = Σ_i · (phi_power/σ²) · r_proj'
        mu_i = Sigma_i * (phi_power / sigma2) * r_proj.';  % T×1

        h_snapshots(i,:) = mu_i.';
        Sigma_diag(i,:) = real(diag(Sigma_i)).';
    end

    %% M步：更新超参数（联合稀疏）
    for i = 1:N
        % γ_i = (1/T) · tr(μ_i·μ_i' · B⁻¹ + Σ_i · B⁻¹) / T
        mu_i = h_snapshots(i,:).';  % T×1
        % 简化：使用经验方差+后验方差的平均
        gamma(i) = (mu_i' * B_inv * mu_i + trace(diag(Sigma_diag(i,:)) * B_inv)) / T;
        gamma(i) = max(real(gamma(i)), 1e-12);
    end

    %% 更新噪声方差
    residual = Y_multi - Phi * h_snapshots;
    res_power = sum(abs(residual(:)).^2);
    % 考虑后验不确定性
    trace_term = 0;
    for i = 1:N
        trace_term = trace_term + real(Phi(:,i)' * Phi(:,i)) * sum(Sigma_diag(i,:));
    end
    sigma2 = (res_power + trace_term) / (M * T);
    sigma2 = max(sigma2, 1e-10);

    %% 收敛检查
    if norm(gamma - gamma_old) / (norm(gamma_old) + 1e-10) < tol
        break;
    end
end

%% ========== 5. 稀疏支撑提取 ========== %%
threshold = max(gamma) * 1e-4;
support = find(gamma >= threshold);
% 置零非活跃抽头
inactive = gamma < threshold;
h_snapshots(inactive, :) = 0;

%% ========== 6. 频域输出 ========== %%
H_tv = zeros(N, T);
for t = 1:T
    H_tv(:, t) = fft(h_snapshots(:, t), N);
end

%% ========== 7. 输出信息 ========== %%
gamma_tv = repmat(gamma, 1, T);  % 联合稀疏→各时刻共享
info.n_iter = iter;
info.support = support;
info.sigma2 = sigma2;
info.K_detected = length(support);

end
