function [x_hat, LLR_out, x_mean_out] = eq_otfs_mp(Y_dd, h_dd, path_info, N, M, noise_var, max_iter, constellation, prior_mean, prior_var)
% 功能：OTFS消息传递(MP)均衡器——高斯近似BP
% 版本：V3.0.0
% 输入：
%   Y_dd          - 接收DD域帧 (NxM 复数)
%   h_dd          - DD域信道响应 (NxM 稀疏)
%   path_info     - 路径信息结构体
%       .num_paths, .delay_idx, .doppler_idx, .gain
%   N, M          - DD域格点尺寸
%   noise_var     - 噪声方差
%   max_iter      - BP迭代次数 (默认 10)
%   constellation - 调制星座点 (默认 QPSK)
%   prior_mean    - 可选先验均值 (NxM，Turbo迭代时由译码器提供)
%   prior_var     - 可选先验方差 (NxM 或标量)
% 输出：
%   x_hat      - DD域硬判决符号估计 (NxM)
%   LLR_out    - 简化LLR (NxM, real(x_mean))
%   x_mean_out - DD域软估计均值 (NxM 复数, v3新增)
%
% 备注：
%   V3修复：
%   1. BP信念更新加入先验项（var_prior, mean_prior）
%   2. 新增第3输出x_mean_out（软估计，供Turbo反馈）
%   3. 阻尼防振荡：x_mean = β·x_mean_new + (1-β)·x_mean_old

%% ========== 入参 ========== %%
if nargin < 8 || isempty(constellation), constellation = [1+1j, 1-1j, -1+1j, -1-1j]/sqrt(2); end
if nargin < 7 || isempty(max_iter), max_iter = 10; end
if nargin < 6 || isempty(noise_var), noise_var = 0.01; end

P = path_info.num_paths;
delays = path_info.delay_idx;
dopplers = path_info.doppler_idx;
gains = path_info.gain;

%% ========== 初始化先验 ========== %%
if nargin >= 9 && ~isempty(prior_mean)
    x_mean = prior_mean;
else
    x_mean = zeros(N, M);
end
if nargin >= 10 && ~isempty(prior_var)
    if isscalar(prior_var)
        x_var = prior_var * ones(N, M);
    else
        x_var = prior_var;
    end
else
    x_var = ones(N, M);
end

% 保存先验（BP每次迭代需要）
prior_mean_mat = x_mean;
prior_var_mat = x_var;

damping = 0.5;  % BP阻尼因子

%% ========== BP迭代 ========== %%
for bp_iter = 1:max_iter
    x_mean_new = zeros(N, M);
    x_var_new = zeros(N, M);

    % 先验贡献（关键修复：每次BP迭代都从先验开始累加）
    for k = 1:N
        for l = 1:M
            pv = max(prior_var_mat(k,l), 1e-10);
            x_var_new(k,l) = 1 / pv;
            x_mean_new(k,l) = prior_mean_mat(k,l) / pv;
        end
    end

    % 对每个观测节点传递消息
    for k = 1:N
        for l = 1:M
            y_obs = Y_dd(k, l);

            % 计算该观测节点连接的所有变量节点贡献
            mean_sum = 0;
            var_sum = noise_var;
            for p = 1:P
                kx = mod(k - 1 - dopplers(p), N) + 1;
                lx = mod(l - 1 - delays(p), M) + 1;
                mean_sum = mean_sum + gains(p) * x_mean(kx, lx);
                var_sum = var_sum + abs(gains(p))^2 * x_var(kx, lx);
            end

            % 对每个连接的变量节点传递消息
            for p = 1:P
                kx = mod(k - 1 - dopplers(p), N) + 1;
                lx = mod(l - 1 - delays(p), M) + 1;

                % 排除当前变量节点的贡献（外信息）
                mean_ext = mean_sum - gains(p) * x_mean(kx, lx);
                var_ext = var_sum - abs(gains(p))^2 * x_var(kx, lx);
                var_ext = max(var_ext, 1e-10);

                % 从观测到变量的消息（高斯近似）
                residual = y_obs - mean_ext;
                msg_mean = residual / gains(p);
                msg_var = var_ext / abs(gains(p))^2;
                msg_var = max(msg_var, 1e-10);

                % 累加到变量节点（信息形式）
                x_mean_new(kx, lx) = x_mean_new(kx, lx) + msg_mean / msg_var;
                x_var_new(kx, lx) = x_var_new(kx, lx) + 1 / msg_var;
            end
        end
    end

    % 更新变量节点信念（含阻尼）
    for k = 1:N
        for l = 1:M
            new_var = 1 / max(x_var_new(k,l), 1e-10);
            new_mean = new_var * x_mean_new(k,l);
            x_var(k,l) = new_var;
            x_mean(k,l) = damping * new_mean + (1 - damping) * x_mean(k,l);
        end
    end
end

%% ========== 输出 ========== %%
% 软估计
x_mean_out = x_mean;

% 硬判决
x_hat = zeros(N, M);
for k = 1:N
    for l = 1:M
        dists = abs(x_mean(k,l) - constellation).^2;
        [~, idx] = min(dists);
        x_hat(k,l) = constellation(idx);
    end
end

LLR_out = real(x_mean);

end
