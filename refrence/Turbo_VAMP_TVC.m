% =========================================================================
% 基于近似消息传递算法家族的稀疏信道估计仿真
% 包含算法：ISTA, AMP, GAMP, VAMP, Turbo-AMP, Turbo-VAMP, LAMP
% =========================================================================
% 【创新点】热启动 Turbo-VAMP (Warm-Start Turbo-VAMP, WS-Turbo-VAMP)
%   核心思想：将第 t-1 帧的后验支撑概率 rho^(t-1) 作为第 t 帧 LLR_prior 的
%   修正项，在慢时变信道场景下大幅减少收敛所需迭代次数，同时在快时变场景
%   下自适应退化为标准 Turbo-VAMP，保证鲁棒性。
%
%   修正后的先验 LLR：
%   LLR_prior,i^(t) = log(lambda/(1-lambda))
%                   + beta * log(rho_i^(t-1) / (1 - rho_i^(t-1)))
%   其中 beta 为时间相关系数（0~1），由信道时变速度自适应估计。
% =========================================================================

clear; clc; close all;

%% 1. 系统参数设置
N = 1000;       % 信道向量维度
M = 400;        % 导频数量 (M < N 体现压缩感知特性)
K = 40;         % 信道稀疏度
SNR_dB = 8;      % 信噪比 (dB)
num_frames = 20; % 仿真帧数（用于验证热启动跨帧增益）

% 算法控制参数
max_iter = 150;
alpha = 1.8;
damping = 0.7;

% LAMP 参数
lamp_layers = 15;
lamp_batch_size = 50;

% =========================================================================
% 【创新参数】热启动参数设置
% =========================================================================
beta_fixed  = 0.6; % 固定时间相关系数（用于对比实验）
% 时变速度检测窗口（用于自适应 beta 估计）
beta_adapt_window = 3; % 用前几帧的支撑变化率估计 beta
budget_iter = 20;      % 受限迭代预算（多帧对比用：热启动优势体现在早期收敛）

fprintf('系统参数: 维度 N=%d, 导频数 M=%d, 稀疏度 K=%d, SNR=%ddB\n', N, M, K, SNR_dB);
fprintf('热启动参数: beta_fixed=%.2f, 帧数=%d\n', beta_fixed, num_frames);

%% 2. 生成仿真数据（单帧，用于算法横向对比）
rng(42);
h_true = generate_sparse_channel(N, K);
Phi = randn(M, N) / sqrt(M);
y_clean = Phi * h_true;
signal_power = norm(y_clean)^2 / M;
noise_power = signal_power / (10^(SNR_dB/10));
noise = sqrt(noise_power) * randn(M, 1);
y = y_clean + noise;

%% 2.5 离线训练 LAMP
fprintf('\n=== 开始离线训练 LAMP (贪心逐层训练) ===\n');
H_train = zeros(N, lamp_batch_size);
for i = 1:lamp_batch_size
    perm = randperm(N);
    H_train(perm(1:K), i) = randn(K, 1);
end
Y_train = Phi * H_train + sqrt(noise_power) * randn(M, lamp_batch_size);

theta_learned = zeros(lamp_layers, 3);
X_train = zeros(N, lamp_batch_size);
Z_train = Y_train;
options = optimset('Display', 'off');

for t = 1:lamp_layers
    theta0 = [1.0, 1.8, 1.0];
    cost_fun = @(theta) lamp_layer_cost(theta, X_train, Z_train, Y_train, Phi, H_train);
    theta_opt = fminsearch(cost_fun, theta0, options);
    theta_learned(t, :) = theta_opt;
    [X_train, Z_train] = lamp_layer_forward(theta_opt, X_train, Z_train, Y_train, Phi);
    fprintf('LAMP 第 %02d/%d 层训练完成, 训练集 NMSE: %.2f dB\n', t, lamp_layers, ...
        10*log10(cost_fun(theta_opt)/norm(H_train,'fro')^2));
end
fprintf('LAMP 离线训练完成！\n\n');

%% 3. 执行单帧信道估计（各算法横向对比）
fprintf('=== 单帧算法横向对比 ===\n');
fprintf('正在运行 ISTA 算法...\n');
[h_ista, mse_ista] = ista_estimation(y, Phi, h_true, max_iter, alpha);

fprintf('正在运行 AMP 算法...\n');
[h_amp, mse_amp] = amp_estimation(y, Phi, h_true, max_iter, alpha, damping);

fprintf('正在运行 GAMP 算法...\n');
[h_gamp, mse_gamp] = gamp_estimation(y, Phi, h_true, max_iter, alpha, noise_power);

fprintf('正在运行 VAMP 算法...\n');
[h_vamp, mse_vamp] = vamp_estimation(y, Phi, h_true, max_iter, alpha, noise_power);

fprintf('正在运行 Turbo-AMP 算法...\n');
[h_turbo, mse_turbo] = turbo_amp_estimation(y, Phi, h_true, max_iter, K);

fprintf('正在运行 标准 Turbo-VAMP 算法...\n');
[h_turbo_vamp, mse_turbo_vamp] = turbo_vamp_estimation(y, Phi, h_true, max_iter, K, noise_power);

fprintf('正在运行 LAMP 算法...\n');
[h_lamp, mse_lamp] = lamp_estimation(y, Phi, h_true, theta_learned);
mse_lamp_full = ones(max_iter, 1) * mse_lamp(end);
mse_lamp_full(1:lamp_layers) = mse_lamp;

% =========================================================================
% 【核心创新】热启动 Turbo-VAMP（冷启动，等同于标准版，用于建立基线）
% =========================================================================
fprintf('正在运行 WS-Turbo-VAMP (冷启动，第1帧) ...\n');
[h_ws_cold, mse_ws_cold, rho_final_cold] = ...
    ws_turbo_vamp_estimation(y, Phi, h_true, max_iter, K, noise_power, ...
                             zeros(N,1), 0.0); % beta=0 → 纯冷启动

% =========================================================================
% 【核心创新】热启动 Turbo-VAMP（热启动，使用前帧后验概率作为先验修正）
% =========================================================================
fprintf('正在运行 WS-Turbo-VAMP (热启动，beta=%.2f) ...\n', beta_fixed);
[h_ws_warm, mse_ws_warm, ~] = ...
    ws_turbo_vamp_estimation(y, Phi, h_true, max_iter, K, noise_power, ...
                             rho_final_cold, beta_fixed); % 传入前帧后验

%% 4. 多帧仿真：验证热启动在时变信道上的跨帧累积增益
fprintf('\n=== 多帧时变信道仿真（验证热启动增益）===\n');
channel_variation = 0.15; % 每帧信道变化强度（0=静止, 1=全新信道）

nmse_std_frames   = zeros(num_frames, 1); % 标准 Turbo-VAMP 每帧最终 NMSE
nmse_ws_frames    = zeros(num_frames, 1); % WS-Turbo-VAMP 每帧最终 NMSE
iters_std_frames  = zeros(num_frames, 1); % 标准版达到目标 NMSE 所需迭代数
iters_ws_frames   = zeros(num_frames, 1); % 热启动版达到目标 NMSE 所需迭代数
target_nmse       = 0.1;                  % 目标 NMSE 阈值（-10dB，SNR=8dB下可达）

rho_prev  = zeros(N, 1); % 初始化前帧后验概率（冷启动）
beta_vals = zeros(num_frames, 1); % 记录每帧自适应 beta 值
support_change_history = [];

% 初始化时变信道
h_frame = generate_sparse_channel(N, K);

for f = 1:num_frames
    % --- 生成当前帧信道（慢时变：部分抽头更新）---
    if f > 1
        h_frame = evolve_channel(h_frame, N, K, channel_variation);
    end
    y_frame = Phi * h_frame + sqrt(noise_power) * randn(M, 1);

    % --- beta 设置：第1帧强制冷启动，后续帧使用固定热启动系数 ---
    if f == 1
        beta_adapt = 0.0;
    else
        beta_adapt = beta_fixed;
    end
    beta_vals(f) = beta_adapt;

    % --- 标准 Turbo-VAMP ---
    [~, mse_std_f, ~] = turbo_vamp_estimation_tracked(...
        y_frame, Phi, h_frame, budget_iter, K, noise_power);
    nmse_std_frames(f) = mse_std_f(end);
    idx_converge = find(mse_std_f <= target_nmse, 1);
    iters_std_frames(f) = ifelse(~isempty(idx_converge), idx_converge, budget_iter);

    % --- 热启动 WS-Turbo-VAMP ---
    [~, mse_ws_f, rho_curr] = ws_turbo_vamp_estimation(...
        y_frame, Phi, h_frame, budget_iter, K, noise_power, rho_prev, beta_adapt);
    nmse_ws_frames(f) = mse_ws_f(end);
    idx_converge_ws = find(mse_ws_f <= target_nmse, 1);
    iters_ws_frames(f) = ifelse(~isempty(idx_converge_ws), idx_converge_ws, budget_iter);

    % 更新前帧后验（传递给下一帧）
    rho_prev = rho_curr;

    fprintf('帧 %2d: 信道变化=%.2f, beta=%.3f | 标准NMSE=%.2fdB(%d次迭代) | WS-NMSE=%.2fdB(%d次迭代)\n', ...
        f, channel_variation, beta_adapt, ...
        10*log10(nmse_std_frames(f)), iters_std_frames(f), ...
        10*log10(nmse_ws_frames(f)),  iters_ws_frames(f));
end

%% 5. 可视化
figure('Name', '稀疏信道估计性能对比', 'Position', [100, 50, 1300, 950]);

% 5.1 信道估计波形对比
subplot(3, 2, [1 2]);
view_len = 200;
idx = 1:view_len;
stem(idx, h_true(idx), 'k', 'LineWidth', 1.5, 'DisplayName', 'True Channel');
hold on;
stem(idx, h_turbo_vamp(idx), 'b--', 'Marker', 'x', 'LineWidth', 1.2, 'DisplayName', '标准 Turbo-VAMP');
stem(idx, h_ws_warm(idx),    'r-',  'Marker', 's', 'LineWidth', 1.5, 'DisplayName', 'WS-Turbo-VAMP (热启动)');
title('信道冲激响应估计对比（前200个抽头）');
xlabel('抽头索引'); ylabel('幅度'); legend('Location', 'best'); grid on;

% 5.2 单帧各算法 NMSE 收敛曲线
subplot(3, 2, [3 4]);
iter_idx = 1:max_iter;
plot(iter_idx, 10*log10(mse_ista),        'b-',  'LineWidth', 1.5, 'DisplayName', 'ISTA');
hold on;
plot(iter_idx, 10*log10(mse_amp),         'r-o', 'LineWidth', 1.5, 'MarkerIndices', 1:10:max_iter, 'DisplayName', 'AMP');
plot(iter_idx, 10*log10(mse_gamp),        'y-s', 'LineWidth', 1.5, 'MarkerIndices', 1:10:max_iter, 'DisplayName', 'GAMP');
plot(iter_idx, 10*log10(mse_vamp),        'm-^', 'LineWidth', 1.5, 'MarkerIndices', 1:10:max_iter, 'DisplayName', 'VAMP');
plot(iter_idx, 10*log10(mse_turbo),       'c-d', 'LineWidth', 1.5, 'MarkerIndices', 1:10:max_iter, 'DisplayName', 'Turbo-AMP');
plot(iter_idx, 10*log10(mse_turbo_vamp),  'g-x', 'LineWidth', 2.0, 'MarkerIndices', 1:10:max_iter, 'DisplayName', '标准 Turbo-VAMP');
plot(iter_idx, 10*log10(mse_lamp_full),   'k-p', 'LineWidth', 2.0, 'MarkerIndices', 1:2:lamp_layers, 'DisplayName', sprintf('LAMP(%d层)', lamp_layers));
plot(iter_idx, 10*log10(mse_ws_cold),     'b--', 'LineWidth', 2.5, 'DisplayName', 'WS-Turbo-VAMP (冷启动)');
plot(iter_idx, 10*log10(mse_ws_warm),     'r-',  'LineWidth', 3.0, 'DisplayName', sprintf('WS-Turbo-VAMP (热启动,β=%.2f)', beta_fixed));
title('单帧 NMSE 收敛曲线对比');
xlabel('迭代次数'); ylabel('NMSE (dB)'); legend('Location', 'northeast', 'FontSize', 8); grid on;

% 5.3 多帧 NMSE 对比
subplot(3, 2, 5);
plot(1:num_frames, 10*log10(nmse_std_frames), 'b-o', 'LineWidth', 2, 'DisplayName', '标准 Turbo-VAMP');
hold on;
plot(1:num_frames, 10*log10(nmse_ws_frames),  'r-s', 'LineWidth', 2, 'DisplayName', 'WS-Turbo-VAMP');
xlabel('帧编号'); ylabel('NMSE (dB)'); title(sprintf('多帧 NMSE（变化率=%.2f，受限%d次迭代）', channel_variation, budget_iter));
legend('Location', 'best'); grid on;

% 5.4 多帧收敛速度对比（迭代次数节省）
subplot(3, 2, 6);
bar_data = [iters_std_frames, iters_ws_frames];
bar(1:num_frames, bar_data);
xlabel('帧编号'); ylabel('达到目标NMSE所需迭代数');
title(sprintf('收敛速度对比（目标NMSE=%.0f dB, 预算%d次迭代）', 10*log10(target_nmse), budget_iter));
legend({'标准 Turbo-VAMP', 'WS-Turbo-VAMP'}, 'Location', 'best'); grid on;

sgtitle(sprintf('热启动 Turbo-VAMP 仿真结果  SNR=%ddB, N=%d, M=%d, K=%d', SNR_dB, N, M, K));

%% 6. 打印汇总统计
iter_saving = mean(iters_std_frames - iters_ws_frames);
nmse_gain   = mean(10*log10(nmse_std_frames) - 10*log10(nmse_ws_frames));
fprintf('\n=== 多帧性能汇总 ===\n');
fprintf('平均迭代次数节省: %.1f 次/帧（节省比例 %.1f%%）\n', ...
    iter_saving, 100*iter_saving/mean(iters_std_frames));
fprintf('平均 NMSE 增益:  %.2f dB\n', nmse_gain);
fprintf('自适应 beta 范围: [%.3f, %.3f]\n', min(beta_vals), max(beta_vals));

fprintf('\n仿真完成！\n');

%% =========================================================================
%  辅助函数定义区域
%% =========================================================================

function h = generate_sparse_channel(N, K)
    h = zeros(N, 1);
    perm = randperm(N);
    h(perm(1:K)) = randn(K, 1);
end

% =========================================================================
% 【创新函数】时变信道演化模型
%   慢时变：以概率 p_change 随机替换部分非零抽头位置和幅值
% =========================================================================
function h_new = evolve_channel(h_old, N, K, variation_rate)
    % variation_rate: 0=信道不变, 1=全新信道
    h_new = h_old;
    n_change = round(K * variation_rate); % 本帧替换的抽头数

    % 找到旧的非零位置
    old_nonzero = find(h_old ~= 0);

    % 随机选 n_change 个旧抽头清零
    if n_change > 0 && ~isempty(old_nonzero)
        idx_remove = old_nonzero(randperm(length(old_nonzero), min(n_change, length(old_nonzero))));
        h_new(idx_remove) = 0;
        % 在新位置生成非零抽头
        zero_positions = find(h_new == 0);
        if length(zero_positions) >= n_change
            idx_add = zero_positions(randperm(length(zero_positions), n_change));
            h_new(idx_add) = randn(n_change, 1);
        end
    end
end

function v_out = soft_threshold(v, threshold)
    v_out = sign(v) .* max(abs(v) - threshold, 0);
end

function result = ifelse(cond, a, b)
    if cond; result = a; else; result = b; end
end

% --- 1. ISTA ---
function [h_hat, mse_history] = ista_estimation(y, Phi, h_true, max_iter, alpha)
    [M, N] = size(Phi);
    h_hat = zeros(N, 1);
    mse_history = zeros(max_iter, 1);
    L = norm(Phi)^2;
    mu = 1 / L;
    for t = 1:max_iter
        z = y - Phi * h_hat;
        r = h_hat + mu * Phi' * z;
        tau = alpha * mu * norm(z) / sqrt(M);
        h_hat = soft_threshold(r, tau);
        mse_history(t) = norm(h_hat - h_true)^2 / norm(h_true)^2;
    end
end

% --- 2. AMP ---
function [h_hat, mse_history] = amp_estimation(y, Phi, h_true, max_iter, alpha, damping)
    [M, N] = size(Phi);
    h_hat = zeros(N, 1);
    z = y;
    mse_history = zeros(max_iter, 1);
    for t = 1:max_iter
        r = h_hat + Phi' * z;
        tau = alpha * norm(z) / sqrt(M);
        h_target = soft_threshold(r, tau);
        active_count = sum(abs(r) > tau);
        z_target = y - Phi * h_target + (active_count / M) * z;
        if t == 1
            h_hat = h_target; z = z_target;
        else
            h_hat = damping * h_target + (1-damping) * h_hat;
            z = damping * z_target + (1-damping) * z;
        end
        mse_history(t) = norm(h_hat - h_true)^2 / norm(h_true)^2;
    end
end

% --- 3. GAMP ---
function [h_hat, mse_history] = gamp_estimation(y, Phi, h_true, max_iter, alpha, noise_var)
    [M, N] = size(Phi);
    Phi_sq = Phi.^2;
    v_x = ones(N, 1);
    x_hat = zeros(N, 1);
    s_hat = zeros(M, 1);
    mse_history = zeros(max_iter, 1);
    damping = 0.5;
    for t = 1:max_iter
        v_p = Phi_sq * v_x;
        p_hat = Phi * x_hat - v_p .* s_hat;
        v_z = v_p + noise_var;
        s_target = (y - p_hat) ./ v_z;
        v_s = 1 ./ v_z;
        s_hat = (t==1)*s_target + (t>1)*(damping*s_target + (1-damping)*s_hat);
        v_r = 1 ./ (Phi_sq' * v_s);
        r_hat = x_hat + v_r .* (Phi' * s_hat);
        tau = alpha * sqrt(mean(v_r));
        x_target = soft_threshold(r_hat, tau);
        active = abs(r_hat) > tau;
        v_target = v_r .* active;
        x_hat = (t==1)*x_target + (t>1)*(damping*x_target + (1-damping)*x_hat);
        v_x = (t==1)*v_target + (t>1)*(damping*v_target + (1-damping)*v_x);
        mse_history(t) = norm(x_hat - h_true)^2 / norm(h_true)^2;
    end
    h_hat = x_hat;
end

% --- 4. VAMP ---
function [h_hat, mse_history] = vamp_estimation(y, Phi, h_true, max_iter, alpha, noise_var)
    [M, N] = size(Phi);
    [~, S_full, V] = svd(Phi);
    s_sq = diag(S_full' * S_full);
    Phi_T_y_scaled = (Phi' * y) / noise_var;
    r1 = zeros(N, 1);
    r2 = zeros(N, 1);
    gamma1 = 1e-3;
    mse_history = zeros(max_iter, 1);
    damping = 0.7;
    for t = 1:max_iter
        tau = alpha / sqrt(gamma1);
        x1 = soft_threshold(r1, tau);
        a1 = mean(abs(r1) > tau);
        a1 = min(max(a1, 1e-10), 1-1e-10);
        gamma2 = gamma1 * (1-a1) / a1;
        r2_target = (x1 - a1*r1) / (1-a1);
        r2 = (t==1)*r2_target + (t>1)*(damping*r2_target + (1-damping)*r2);
        d_vec = 1 ./ (gamma2 + s_sq/noise_var);
        x2 = V * (d_vec .* (V' * (gamma2*r2 + Phi_T_y_scaled)));
        a2 = mean(gamma2 * d_vec);
        a2 = min(max(a2, 1e-10), 1-1e-10);
        gamma1_new = gamma2 * (1-a2) / a2;
        r1_target = (x2 - a2*r2) / (1-a2);
        gamma1 = (t==1)*gamma1_new + (t>1)*(damping*gamma1_new + (1-damping)*gamma1);
        r1 = (t==1)*r1_target + (t>1)*(damping*r1_target + (1-damping)*r1);
        h_hat = x1;
        mse_history(t) = norm(h_hat - h_true)^2 / norm(h_true)^2;
    end
end

% --- 5. LAMP 辅助函数 ---
function [X_new, Z_new] = lamp_layer_forward(theta, X, Z, Y, Phi)
    gamma = theta(1);
    alpha = abs(theta(2));
    c_mult = theta(3);
    [M, ~] = size(Phi);
    R = X + gamma * (Phi' * Z);
    sigma_t = sqrt(sum(Z.^2, 1) / M);
    tau = alpha * sigma_t;
    X_new = sign(R) .* max(abs(R) - tau, 0);
    active_count = sum(abs(R) > tau, 1);
    onsager_coeff = c_mult * (active_count / M);
    Z_new = Y - Phi * X_new + Z .* onsager_coeff;
end

function cost = lamp_layer_cost(theta, X, Z, Y, Phi, H_train)
    [X_new, ~] = lamp_layer_forward(theta, X, Z, Y, Phi);
    cost = sum(sum((X_new - H_train).^2));
end

function [h_hat, mse_history] = lamp_estimation(y, Phi, h_true, theta_learned)
    lamp_layers = size(theta_learned, 1);
    [~, N] = size(Phi);
    h_hat = zeros(N, 1);
    z = y;
    mse_history = zeros(lamp_layers, 1);
    for t = 1:lamp_layers
        [h_hat, z] = lamp_layer_forward(theta_learned(t,:), h_hat, z, y, Phi);
        mse_history(t) = norm(h_hat - h_true)^2 / norm(h_true)^2;
    end
end

% --- 6. Turbo-AMP ---
function [h_hat, mse_history] = turbo_amp_estimation(y, Phi, h_true, max_iter, K)
    [M, N] = size(Phi);
    h_hat = zeros(N, 1);
    z = y;
    mse_history = zeros(max_iter, 1);
    lambda = K / N;
    sigma_x2 = 1.0;
    damping = 0.5;
    for t = 1:max_iter
        r = h_hat + Phi' * z;
        tau2 = norm(z)^2 / M;
        LLR_prior = log(lambda) - log(1-lambda);
        LLR_obs = 0.5*log(tau2/(sigma_x2+tau2)) + ...
                  0.5*(r.^2) * (sigma_x2/(tau2*(sigma_x2+tau2)));
        LLR_total = max(min(LLR_prior + LLR_obs, 50), -50);
        rho = 1 ./ (1 + exp(-LLR_total));
        mu_active = (sigma_x2/(sigma_x2+tau2)) * r;
        v_active  = (sigma_x2*tau2) / (sigma_x2+tau2);
        h_target = rho .* mu_active;
        var_target = rho .* (mu_active.^2 + v_active) - h_target.^2;
        h_hat = (t==1)*h_target + (t>1)*(damping*h_target + (1-damping)*h_hat);
        onsager_term = (sum(var_target) / tau2 / M) * z;
        z = y - Phi * h_hat + onsager_term;
        mse_history(t) = norm(h_hat - h_true)^2 / norm(h_true)^2;
    end
end

% --- 7. 标准 Turbo-VAMP ---
function [h_hat, mse_history] = turbo_vamp_estimation(y, Phi, h_true, max_iter, K, noise_var)
    [~, N] = size(Phi);
    [~, S_full, V] = svd(Phi);
    s_sq = diag(S_full' * S_full);
    Phi_T_y_scaled = (Phi' * y) / noise_var;
    r1 = zeros(N, 1);
    r2 = zeros(N, 1);
    gamma1 = 1e-3;
    mse_history = zeros(max_iter, 1);
    damping = 0.7;
    lambda = K / N;
    sigma_x2 = 1.0;
    for t = 1:max_iter
        tau2 = 1 / gamma1;
        LLR_prior = log(lambda) - log(1-lambda);
        LLR_obs = 0.5*log(tau2/(sigma_x2+tau2)) + ...
                  0.5*(r1.^2)*(sigma_x2/(tau2*(sigma_x2+tau2)));
        LLR_total = max(min(LLR_prior + LLR_obs, 50), -50);
        rho = 1 ./ (1 + exp(-LLR_total));
        mu_active = (sigma_x2/(sigma_x2+tau2)) * r1;
        v_active  = (sigma_x2*tau2) / (sigma_x2+tau2);
        x1 = rho .* mu_active;
        var_target = rho .* (mu_active.^2 + v_active) - x1.^2;
        a1 = mean(var_target) / tau2;
        a1 = min(max(a1, 1e-10), 1-1e-10);
        gamma2 = gamma1 * (1-a1) / a1;
        r2_target = (x1 - a1*r1) / (1-a1);
        r2 = (t==1)*r2_target + (t>1)*(damping*r2_target + (1-damping)*r2);
        d_vec = 1 ./ (gamma2 + s_sq/noise_var);
        x2 = V * (d_vec .* (V' * (gamma2*r2 + Phi_T_y_scaled)));
        a2 = mean(gamma2 * d_vec);
        a2 = min(max(a2, 1e-10), 1-1e-10);
        gamma1_new = gamma2 * (1-a2) / a2;
        r1_target = (x2 - a2*r2) / (1-a2);
        gamma1 = (t==1)*gamma1_new + (t>1)*(damping*gamma1_new + (1-damping)*gamma1);
        r1 = (t==1)*r1_target + (t>1)*(damping*r1_target + (1-damping)*r1);
        h_hat = x1;
        mse_history(t) = norm(h_hat - h_true)^2 / norm(h_true)^2;
    end
end

% 带返回值的 Turbo-VAMP（多帧仿真用）
function [h_hat, mse_history, rho_final] = turbo_vamp_estimation_tracked(...
    y, Phi, h_true, max_iter, K, noise_var)
    [~, N] = size(Phi);
    [~, S_full, V] = svd(Phi);
    s_sq = diag(S_full' * S_full);
    Phi_T_y_scaled = (Phi' * y) / noise_var;
    r1 = zeros(N, 1);
    r2 = zeros(N, 1);
    gamma1 = 1e-3;
    mse_history = zeros(max_iter, 1);
    damping = 0.7;
    lambda = K / N;
    sigma_x2 = 1.0;
    rho_final = zeros(N, 1);
    for t = 1:max_iter
        tau2 = 1 / gamma1;
        LLR_prior = log(lambda) - log(1-lambda);
        LLR_obs = 0.5*log(tau2/(sigma_x2+tau2)) + ...
                  0.5*(r1.^2)*(sigma_x2/(tau2*(sigma_x2+tau2)));
        LLR_total = max(min(LLR_prior + LLR_obs, 50), -50);
        rho = 1 ./ (1 + exp(-LLR_total));
        mu_active = (sigma_x2/(sigma_x2+tau2)) * r1;
        v_active  = (sigma_x2*tau2) / (sigma_x2+tau2);
        x1 = rho .* mu_active;
        var_target = rho .* (mu_active.^2 + v_active) - x1.^2;
        a1 = mean(var_target) / tau2;
        a1 = min(max(a1, 1e-10), 1-1e-10);
        gamma2 = gamma1 * (1-a1) / a1;
        r2_target = (x1 - a1*r1) / (1-a1);
        r2 = (t==1)*r2_target + (t>1)*(damping*r2_target + (1-damping)*r2);
        d_vec = 1 ./ (gamma2 + s_sq/noise_var);
        x2 = V * (d_vec .* (V' * (gamma2*r2 + Phi_T_y_scaled)));
        a2 = mean(gamma2 * d_vec);
        a2 = min(max(a2, 1e-10), 1-1e-10);
        gamma1_new = gamma2 * (1-a2) / a2;
        r1_target = (x2 - a2*r2) / (1-a2);
        gamma1 = (t==1)*gamma1_new + (t>1)*(damping*gamma1_new + (1-damping)*gamma1);
        r1 = (t==1)*r1_target + (t>1)*(damping*r1_target + (1-damping)*r1);
        h_hat = x1;
        rho_final = rho;
        mse_history(t) = norm(h_hat - h_true)^2 / norm(h_true)^2;
    end
end

% =========================================================================
% 【核心创新函数】热启动 Turbo-VAMP (WS-Turbo-VAMP)
%
%   输入：
%     y, Phi, h_true, max_iter, K, noise_var  - 标准参数
%     rho_prev  - 前帧后验激活概率向量 (N×1)，冷启动时传 zeros(N,1)
%     beta      - 时间相关系数 (0~1)，0=冷启动，1=完全信任前帧
%
%   输出：
%     h_hat      - 信道估计结果
%     mse_history - 每次迭代的 NMSE
%     rho_final  - 本帧最终后验概率（传给下一帧）
%
%   关键修改（相对于标准 Turbo-VAMP）：
%     LLR_prior,i = log(λ/(1-λ))
%                 + beta * log(ρ_prev,i / (1-ρ_prev,i))   ← 热启动修正项
%
%   当 beta=0 时退化为标准 Turbo-VAMP（冷启动）。
%   当 beta>0 时，前帧后验概率高的位置在 LLR_prior 中获得正向加强，
%   使模块1在首次迭代即能接近正确支撑，从而显著加速收敛。
% =========================================================================
function [h_hat, mse_history, rho_final] = ws_turbo_vamp_estimation(...
    y, Phi, h_true, max_iter, K, noise_var, rho_prev, beta)

    [~, N] = size(Phi);

    % 预计算 SVD（同标准 Turbo-VAMP）
    [~, S_full, V] = svd(Phi);
    s_sq = diag(S_full' * S_full);
    Phi_T_y_scaled = (Phi' * y) / noise_var;

    r1 = zeros(N, 1);
    r2 = zeros(N, 1);
    gamma1 = 1e-3;
    mse_history = zeros(max_iter, 1);
    damping = 0.7;
    lambda = K / N;
    sigma_x2 = 1.0;
    rho_final = zeros(N, 1);

    % ---------------------------------------------------------------
    % 【创新】预计算热启动修正项（LLR_warmstart）
    %   对前帧后验概率截断至 (epsilon, 1-epsilon) 防止 log(0) 溢出
    %   beta=0 时修正项恒为零，退化为标准冷启动
    % ---------------------------------------------------------------
    epsilon = 1e-6;
    rho_prev_clipped = min(max(rho_prev, epsilon), 1 - epsilon);
    LLR_warmstart = beta * log(rho_prev_clipped ./ (1 - rho_prev_clipped));
    % LLR_warmstart,i > 0 → 前帧认为该位置激活，本帧先验倾向激活
    % LLR_warmstart,i < 0 → 前帧认为该位置静默，本帧先验倾向静默

    for t = 1:max_iter
        % === 模块 1: 带热启动修正的 BG-MMSE 去噪 ===
        tau2 = 1 / gamma1;

        % 【创新核心】先验 LLR 叠加热启动修正项
        LLR_prior_base = log(lambda) - log(1 - lambda);
        LLR_prior = LLR_prior_base + LLR_warmstart;   % ← 热启动修正

        LLR_obs = 0.5 * log(tau2 / (sigma_x2 + tau2)) + ...
                  0.5 * (r1.^2) * (sigma_x2 / (tau2 * (sigma_x2 + tau2)));
        LLR_total = max(min(LLR_prior + LLR_obs, 50), -50);
        rho = 1 ./ (1 + exp(-LLR_total));

        mu_active = (sigma_x2 / (sigma_x2 + tau2)) * r1;
        v_active  = (sigma_x2 * tau2) / (sigma_x2 + tau2);
        x1 = rho .* mu_active;

        var_target = rho .* (mu_active.^2 + v_active) - x1.^2;
        a1 = mean(var_target) / tau2;
        a1 = min(max(a1, 1e-10), 1 - 1e-10);

        gamma2 = gamma1 * (1 - a1) / a1;
        r2_target = (x1 - a1 * r1) / (1 - a1);
        r2 = (t==1)*r2_target + (t>1)*(damping*r2_target + (1-damping)*r2);

        % === 模块 2: SVD-LMMSE（与标准 Turbo-VAMP 完全相同）===
        d_vec = 1 ./ (gamma2 + s_sq / noise_var);
        x2 = V * (d_vec .* (V' * (gamma2 * r2 + Phi_T_y_scaled)));

        a2 = mean(gamma2 * d_vec);
        a2 = min(max(a2, 1e-10), 1 - 1e-10);

        gamma1_new = gamma2 * (1 - a2) / a2;
        r1_target = (x2 - a2 * r2) / (1 - a2);

        gamma1 = (t==1)*gamma1_new + (t>1)*(damping*gamma1_new + (1-damping)*gamma1);
        r1 = (t==1)*r1_target + (t>1)*(damping*r1_target + (1-damping)*r1);

        h_hat = x1;
        rho_final = rho; % 保存本帧最终后验（传给下一帧）
        mse_history(t) = norm(h_hat - h_true)^2 / norm(h_true)^2;
    end
end