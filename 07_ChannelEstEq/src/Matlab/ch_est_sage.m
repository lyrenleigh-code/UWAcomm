function [params, h_est, info] = ch_est_sage(y, x_ref, fs, K_paths, max_iter, delay_range, doppler_range)
% 功能：SAGE（空时交替广义EM）高分辨率多径参数估计
% 版本：V1.0.0
% 输入：
%   y            - 接收信号 (Nx1 或 1xN)
%   x_ref        - 已知参考信号 (Nx1 或 1xN, 训练序列)
%   fs           - 采样率/符号率 (Hz)
%   K_paths      - 估计的多径数 (默认 6)
%   max_iter     - 最大迭代次数 (默认 20)
%   delay_range  - 时延搜索范围 [min max] (采样点, 默认 [0 round(fs*0.02)])
%   doppler_range- 多普勒搜索范围 [min max] (Hz, 默认 [-10 10])
% 输出：
%   params  - K_paths×3矩阵, 每行[时延(采样点), 增益(复数), 多普勒(Hz)]
%   h_est   - 重构的信道冲激响应 (1×(max_delay+1))
%   info    - 估计信息
%       .n_iter   : 实际迭代次数
%       .cost     : 每次迭代的代价函数值
%       .converged: 是否收敛
%
% 备注：
%   SAGE是EM的高效变体——每次迭代只更新一个径的参数，其余径固定
%   相比标准EM（同时更新所有参数），SAGE收敛更快且避免局部极值
%
%   算法流程（每个径k依次执行）：
%     E步: 计算第k径的"完整数据"（去除其他径干扰后的残差）
%       z_k = y - Σ_{j≠k} ĝ_j · x(n-d̂_j) · exp(j2πf̂_j·n/fs)
%     M步: 最大化对数似然估计第k径参数
%       时延: d̂_k = argmax_d |Σ z_k(n)·x*(n-d)|
%       增益: ĝ_k = Σ z_k(n)·x*(n-d̂_k)·exp(-j2πf̂_k·n/fs) / Σ|x(n-d̂_k)|²
%       多普勒: f̂_k = argmax_f |Σ z_k(n)·x*(n-d̂_k)·exp(-j2πf·n/fs)|
%
%   适用场景：
%   - 高分辨率多径参数估计（时延/增益/多普勒联合）
%   - 稀疏信道结构（径数K远小于时延扩展区间）
%   - 慢变信道的初始信道获取

%% ========== 1. 入参解析 ========== %%
if nargin < 7 || isempty(doppler_range), doppler_range = [-10 10]; end
if nargin < 6 || isempty(delay_range), delay_range = [0 round(fs*0.02)]; end
if nargin < 5 || isempty(max_iter), max_iter = 20; end
if nargin < 4 || isempty(K_paths), K_paths = 6; end

y = y(:).';
x_ref = x_ref(:).';
N = length(y);

%% ========== 2. 参数校验 ========== %%
if isempty(y), error('接收信号不能为空！'); end
if length(x_ref) ~= N, error('参考信号长度(%d)须与接收信号(%d)一致！', length(x_ref), N); end

%% ========== 3. 搜索网格 ========== %%
delay_grid = delay_range(1):delay_range(2);
N_delay = length(delay_grid);
% 多普勒网格（分辨率0.1Hz）
fd_step = min(0.1, (doppler_range(2)-doppler_range(1))/100);
fd_grid = doppler_range(1):fd_step:doppler_range(2);
N_fd = length(fd_grid);

%% ========== 4. 初始化：粗搜索前K_paths条径 ========== %%
params = zeros(K_paths, 3);  % [delay, gain, doppler]
residual = y;
n_vec = (0:N-1);

for k = 1:K_paths
    % 粗时延搜索（互相关）
    corr_delay = zeros(1, N_delay);
    for di = 1:N_delay
        d = delay_grid(di);
        x_shifted = [zeros(1,d), x_ref(1:N-d)];
        corr_delay(di) = abs(sum(residual .* conj(x_shifted)));
    end
    [~, best_di] = max(corr_delay);
    d_est = delay_grid(best_di);

    % 粗多普勒搜索
    x_d = [zeros(1,d_est), x_ref(1:N-d_est)];
    corr_fd = zeros(1, N_fd);
    for fi = 1:N_fd
        steering = exp(-1j*2*pi*fd_grid(fi)*n_vec/fs);
        corr_fd(fi) = abs(sum(residual .* conj(x_d) .* steering));
    end
    [~, best_fi] = max(corr_fd);
    fd_est = fd_grid(best_fi);

    % 增益估计
    steering_best = exp(-1j*2*pi*fd_est*n_vec/fs);
    x_d_steer = x_d .* conj(steering_best);
    g_est = sum(residual .* conj(x_d_steer)) / max(sum(abs(x_d_steer).^2), 1e-10);

    params(k,:) = [d_est, 0, fd_est];  % gain存为复数，单独处理
    params(k,2) = real(g_est);  % 临时存幅度（后面用复数）

    % 复数增益单独存储
    gain_complex(k) = g_est;

    % 减去已估计径的贡献
    contrib = g_est * x_d .* exp(1j*2*pi*fd_est*n_vec/fs);
    residual = residual - contrib;
end

%% ========== 5. SAGE迭代精化 ========== %%
cost_history = zeros(1, max_iter);

for iter = 1:max_iter
    params_old = params;
    gains_old = gain_complex;

    for k = 1:K_paths
        %% E步：计算第k径的完整数据（去除其他径干扰）
        z_k = y;
        for j = 1:K_paths
            if j == k, continue; end
            d_j = params(j,1);
            fd_j = params(j,3);
            x_j = [zeros(1,d_j), x_ref(1:N-d_j)];
            z_k = z_k - gain_complex(j) * x_j .* exp(1j*2*pi*fd_j*n_vec/fs);
        end

        %% M步：更新第k径参数

        % 时延搜索（在当前多普勒下）
        fd_k = params(k,3);
        steering_k = exp(-1j*2*pi*fd_k*n_vec/fs);
        corr_d = zeros(1, N_delay);
        for di = 1:N_delay
            d = delay_grid(di);
            x_d = [zeros(1,d), x_ref(1:N-d)];
            corr_d(di) = abs(sum(z_k .* conj(x_d) .* steering_k));
        end
        [~, best_di] = max(corr_d);
        params(k,1) = delay_grid(best_di);
        d_k = params(k,1);
        x_dk = [zeros(1,d_k), x_ref(1:N-d_k)];

        % 多普勒搜索
        corr_f = zeros(1, N_fd);
        for fi = 1:N_fd
            steer = exp(-1j*2*pi*fd_grid(fi)*n_vec/fs);
            corr_f(fi) = abs(sum(z_k .* conj(x_dk) .* steer));
        end
        [~, best_fi] = max(corr_f);
        params(k,3) = fd_grid(best_fi);
        fd_k = params(k,3);

        % 增益更新
        steering_k = exp(-1j*2*pi*fd_k*n_vec/fs);
        x_dk_steer = x_dk .* conj(steering_k);
        gain_complex(k) = sum(z_k .* conj(x_dk_steer)) / max(sum(abs(x_dk_steer).^2), 1e-10);
    end

    % 代价函数（残差能量）
    recon = zeros(1, N);
    for k = 1:K_paths
        d_k = params(k,1);
        fd_k = params(k,3);
        x_dk = [zeros(1,d_k), x_ref(1:N-d_k)];
        recon = recon + gain_complex(k) * x_dk .* exp(1j*2*pi*fd_k*n_vec/fs);
    end
    cost_history(iter) = sum(abs(y - recon).^2);

    % 收敛检查
    param_change = norm([params(:,1);params(:,3)] - [params_old(:,1);params_old(:,3)]) ...
                 + norm(gain_complex(:) - gains_old(:));
    if param_change < 1e-6 * K_paths
        break;
    end
end

%% ========== 6. 输出整理 ========== %%
% 参数矩阵：[时延, 复增益, 多普勒]
params_out = zeros(K_paths, 3);
for k = 1:K_paths
    params_out(k,:) = [params(k,1), abs(gain_complex(k)), params(k,3)];
end
% 按增益排序（从强到弱）
[~, sort_idx] = sort(abs(gain_complex), 'descend');
params_out = params_out(sort_idx, :);
gain_complex = gain_complex(sort_idx);

% 重构CIR
max_delay = max(params_out(:,1));
h_est = zeros(1, max_delay+1);
for k = 1:K_paths
    d_k = params_out(k,1);
    h_est(d_k+1) = h_est(d_k+1) + gain_complex(k);
end

% 输出完整参数（含复增益）
params = [params_out(:,1), real(gain_complex(:)), imag(gain_complex(:)), params_out(:,3)];
% 格式: K×4 [delay, Re(gain), Im(gain), doppler_hz]

info.n_iter = iter;
info.cost = cost_history(1:iter);
info.converged = (param_change < 1e-6 * K_paths);
info.gains_complex = gain_complex(:);

end
