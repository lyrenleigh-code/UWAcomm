function [h_tracked, P_cov, info] = ch_track_kalman(y, x_ref, delays, h_init, fd_hz, sym_rate, noise_var, opts)
% 功能：稀疏Kalman信道跟踪——AR(1)状态空间模型逐符号更新
% 版本：V1.0.0
% 输入：
%   y         - 接收信号序列 (1×N 或 Nx1)
%   x_ref     - 参考符号序列 (1×N, 已知符号或软判决x̄)
%   delays    - 各径符号级时延 (1×P, 如[0,5,15,40,60,90])
%   h_init    - 初始信道增益 (1×P 或 Px1, 各径复增益)
%   fd_hz     - 最大多普勒频率 (Hz)
%   sym_rate  - 符号率 (Hz)
%   noise_var - 观测噪声方差 σ²_v (默认 0.01)
%   opts      - 可选参数结构体
%       .alpha     : AR(1)系数 (默认 J_0(2πfd/fs), 自动计算)
%       .q_proc    : 过程噪声方差 (默认 (1-α²)·mean(|h_init|²))
%       .P_init    : 初始协方差系数 (默认 10, P₀ = q·P_init·I)
%       .conf_thresh: 参考符号置信度阈值 (默认 Inf, 不过滤)
%                    |x_ref(n)| < conf_thresh时跳过更新（纯预测）
% 输出：
%   h_tracked - 跟踪的时变信道 (P×N, 各径各时刻的估计增益)
%   P_cov     - 最终协方差矩阵 (P×P)
%   info      - 跟踪信息结构体
%       .alpha     : 实际使用的AR系数
%       .q_proc    : 过程噪声方差
%       .n_updated : 实际做了Kalman更新的符号数
%       .n_predict : 仅预测（未更新）的符号数
%       .kalman_gain_avg: 平均Kalman增益范数
%
% 备注：
%   状态方程: h(n) = α·h(n-1) + w(n), w~CN(0,Q), Q=q_proc·I
%   观测方程: y(n) = φ(n)'·h(n) + v(n), v~CN(0,σ²_v)
%   φ(n) = [x_ref(n-d₁), x_ref(n-d₂), ..., x_ref(n-dP)]'
%   Kalman增益自动在"信预测"和"信观测"之间权衡
%   AR(1)系数α=J₀(2πfd/fs)来自Jakes自相关模型
%   当x_ref为已知符号时给出跟踪上界，为软判决时受判决质量影响

%% ========== 1. 入参解析 ========== %%
if nargin < 8 || isempty(opts), opts = struct(); end
if nargin < 7 || isempty(noise_var), noise_var = 0.01; end

y = y(:).';
x_ref = x_ref(:).';
N = length(y);
P = length(delays);
h_init = h_init(:);

%% ========== 2. 参数校验 ========== %%
if isempty(y), error('接收信号不能为空！'); end
if length(x_ref) ~= N, error('x_ref长度(%d)须与y长度(%d)一致！', length(x_ref), N); end
if length(h_init) ~= P, error('h_init长度(%d)须与径数(%d)一致！', length(h_init), P); end

%% ========== 3. Kalman参数 ========== %%
% AR(1)系数
if isfield(opts, 'alpha') && ~isempty(opts.alpha)
    alpha = opts.alpha;
else
    % α设计：相干时间内衰减到0.5
    % Tc ≈ 1/(4fd), Tc_samples = sym_rate/(4fd)
    % α^Tc_samples = 0.5 → α = 0.5^(1/Tc_samples)
    fd_eff = max(fd_hz, 0.1);
    Tc_samples = sym_rate / (4*fd_eff);
    alpha = 0.5^(1/Tc_samples);
    alpha = max(alpha, 0.99);  % 不低于0.99（防过快衰减）
end

% 过程噪声方差
if isfield(opts, 'q_proc') && ~isempty(opts.q_proc)
    q_proc = opts.q_proc;
else
    % 过程噪声设计：保证Kalman增益K合理（K≈q/(q+R)≈0.01~0.1）
    % 目标：K_target ≈ 0.05（每步修正5%）
    % q = K_target · noise_var / (1 - K_target)
    K_target = min(0.05, 2*pi*max(fd_hz,0.1)/sym_rate * 10);  % fd越大跟踪越快
    q_proc = K_target * noise_var / (1 - K_target);
    q_proc = max(q_proc, 1e-10);
end

% 初始协方差
P_init_scale = 10;
if isfield(opts, 'P_init'), P_init_scale = opts.P_init; end
Pk = q_proc * P_init_scale * eye(P);

% 参考符号置信度阈值
conf_thresh = Inf;
if isfield(opts, 'conf_thresh'), conf_thresh = opts.conf_thresh; end

%% ========== 4. Kalman跟踪主循环 ========== %%
hk = h_init;
h_tracked = zeros(P, N);
Q_mat = q_proc * eye(P);
n_updated = 0;
n_predict = 0;
kg_sum = 0;

for n = 1:N
    %% 预测步
    hk_pred = alpha * hk;
    Pk_pred = alpha^2 * Pk + Q_mat;

    %% 观测向量构建: φ(p) = x_ref(n - delays(p))
    phi = zeros(P, 1);
    phi_valid = false;
    for p = 1:P
        idx = n - delays(p);
        if idx >= 1 && idx <= N
            phi(p) = x_ref(idx);
        end
    end

    %% 判断是否做更新（参考符号有效且置信度够）
    phi_power = sum(abs(phi).^2);
    if phi_power > 1e-10 && phi_power < conf_thresh^2 * P
        phi_valid = true;
    end

    if phi_valid
        %% 更新步
        innovation = y(n) - phi' * hk_pred;
        S = phi' * Pk_pred * phi + noise_var;
        K_gain = Pk_pred * phi / S;
        hk = hk_pred + K_gain * innovation;
        Pk = (eye(P) - K_gain * phi') * Pk_pred;

        % 强制协方差对称正定
        Pk = (Pk + Pk') / 2;

        n_updated = n_updated + 1;
        kg_sum = kg_sum + norm(K_gain);
    else
        %% 纯预测（无更新）
        hk = hk_pred;
        Pk = Pk_pred;
        n_predict = n_predict + 1;
    end

    h_tracked(:, n) = hk;
end

%% ========== 5. 输出信息 ========== %%
P_cov = Pk;
info.alpha = alpha;
info.q_proc = q_proc;
info.n_updated = n_updated;
info.n_predict = n_predict;
info.kalman_gain_avg = kg_sum / max(n_updated, 1);

end
