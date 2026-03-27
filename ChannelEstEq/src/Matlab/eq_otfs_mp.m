function [x_hat, LLR_out] = eq_otfs_mp(Y_dd, h_dd, path_info, N, M, noise_var, max_iter, constellation)
% 功能：OTFS消息传递(MP)均衡器——完整高斯近似BP
% 版本：V1.0.0
% 输入：
%   Y_dd          - 接收DD域帧 (NxM 复数)
%   h_dd          - DD域信道响应 (NxM 稀疏)
%   path_info     - 路径信息（由 ch_est_otfs_dd 生成）
%   N, M          - DD域格点尺寸
%   noise_var     - 噪声方差
%   max_iter      - BP迭代次数 (默认 10)
%   constellation - 调制星座点 (1xQ 复数，默认 QPSK)
% 输出：
%   x_hat   - DD域均衡后的符号估计 (NxM)
%   LLR_out - 软信息输出 (NxM，实数，正=1)

%% ========== 入参 ========== %%
if nargin < 8 || isempty(constellation), constellation = [1+1j, 1-1j, -1+1j, -1-1j]/sqrt(2); end
if nargin < 7 || isempty(max_iter), max_iter = 10; end
if nargin < 6 || isempty(noise_var), noise_var = 0.01; end

P = path_info.num_paths;
Q = length(constellation);

%% ========== 构建因子图连接关系 ========== %%
% 每个观测节点 y[k,l] 连接到 P 个变量节点 x[(k-k_i)_N, (l-l_i)_M]
delays = path_info.delay_idx;
dopplers = path_info.doppler_idx;
gains = path_info.gain;

%% ========== 初始化消息 ========== %%
% 变量节点的先验：均匀分布
x_mean = zeros(N, M);
x_var = ones(N, M);

x_hat = zeros(N, M);
LLR_out = zeros(N, M);

%% ========== BP迭代 ========== %%
for iter = 1:max_iter
    x_mean_new = zeros(N, M);
    x_var_new = zeros(N, M);
    count = zeros(N, M);

    % 对每个观测节点
    for k = 1:N
        for l = 1:M
            y_obs = Y_dd(k, l);

            % 计算该观测节点连接的变量节点的贡献
            % y[k,l] = sum_i h_i * x[(k-k_i)_N, (l-l_i)_M]
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

                % 排除当前变量节点的贡献
                mean_ext = mean_sum - gains(p) * x_mean(kx, lx);
                var_ext = var_sum - abs(gains(p))^2 * x_var(kx, lx);
                var_ext = max(var_ext, 1e-10);

                % 从观测到变量的消息（高斯近似）
                residual = y_obs - mean_ext;
                msg_mean = residual / gains(p);
                msg_var = var_ext / abs(gains(p))^2;

                x_mean_new(kx, lx) = x_mean_new(kx, lx) + msg_mean / msg_var;
                x_var_new(kx, lx) = x_var_new(kx, lx) + 1 / msg_var;
                count(kx, lx) = count(kx, lx) + 1;
            end
        end
    end

    % 更新变量节点信念
    for k = 1:N
        for l = 1:M
            if count(k,l) > 0
                x_var(k,l) = 1 / (x_var_new(k,l) + 1e-10);
                x_mean(k,l) = x_var(k,l) * x_mean_new(k,l);
            end
        end
    end
end

%% ========== 硬判决 ========== %%
for k = 1:N
    for l = 1:M
        dists = abs(x_mean(k,l) - constellation).^2;
        [~, idx] = min(dists);
        x_hat(k,l) = constellation(idx);
    end
end

LLR_out = real(x_mean);               % 简化LLR

end
