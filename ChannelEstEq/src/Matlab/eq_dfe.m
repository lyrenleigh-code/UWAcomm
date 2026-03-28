function [LLR_out, x_hat, noise_var_est] = eq_dfe(y, h_est, training, num_ff, num_fb, lambda_rls, pll_params)
% 功能：RLS自适应DFE均衡器（含PLL载波相位跟踪，输出LLR软信息）
% 版本：V3.0.0 — 参考Turbo Equalization工程实现
% 输入：
%   y          - 接收信号 (1xN，可为分数间隔采样)
%   h_est      - 时域信道估计 (1xL，用于初始化，可选)
%   training   - 训练序列已知符号 (1xT，复数)
%   num_ff     - 前馈滤波器阶数 (默认 21)
%   num_fb     - 反馈滤波器阶数 (默认 10)
%   lambda_rls - RLS遗忘因子 (默认 0.998)
%   pll_params - PLL参数结构体（可选）
%       .enable  : 是否启用PLL (默认 true)
%       .Kp      : 比例增益 (默认 0.01)
%       .Ki      : 积分增益 (默认 0.005)
% 输出：
%   LLR_out      - 数据段LLR软信息 (1xM，M=数据符号数*bits_per_sym)
%   x_hat        - 均衡后的复数符号序列 (1x(T+data_len))
%   noise_var_est- 估计的均衡后噪声方差
%
% 备注：
%   - 训练阶段：用已知符号驱动RLS更新+PLL锁定
%   - 跟踪阶段：判决引导RLS+PLL跟踪
%   - PLL：二阶锁相环，鉴相器用 imag(log(pn*conj(error+pn)))
%   - LLR输出：基于均衡后信号的QPSK软信息（可扩展到其他调制）

%% ========== 入参解析 ========== %%
y = y(:).';
training = training(:).';
N = length(y);
T = length(training);

if nargin < 7 || isempty(pll_params)
    pll_params = struct('enable', true, 'Kp', 0.01, 'Ki', 0.005);
end
if nargin < 6 || isempty(lambda_rls), lambda_rls = 0.998; end
if nargin < 5 || isempty(num_fb), num_fb = 10; end
if nargin < 4 || isempty(num_ff), num_ff = 21; end

%% ========== 参数校验 ========== %%
if isempty(y), error('接收信号不能为空！'); end
if T < 10, error('训练序列至少10个符号！'); end

total_taps = num_ff + num_fb;
data_start = T + 1;
total_symbols = N;

%% ========== 初始化RLS ========== %%
delta = 0.01;
P = eye(total_taps) / delta;
w = zeros(total_taps, 1);

%% ========== 初始化PLL ========== %%
pll_enable = pll_params.enable;
Kp = pll_params.Kp;
Ki = pll_params.Ki;
nco_phase = zeros(1, total_symbols + 2);
disc_out = zeros(1, total_symbols + 2);

%% ========== 逐符号均衡 ========== %%
x_hat = zeros(1, total_symbols);
decisions = zeros(1, total_symbols);
eq_error = zeros(1, total_symbols);

for n = num_ff : total_symbols
    % 前馈输入向量（含PLL相位补偿）
    y_ff = y(n:-1:max(n-num_ff+1, 1));
    if length(y_ff) < num_ff
        y_ff = [y_ff, zeros(1, num_ff - length(y_ff))];
    end

    % PLL相位补偿
    if pll_enable && n >= 3
        y_ff = y_ff * exp(-1j * mod(nco_phase(n-1), 2*pi));
    end

    % 反馈输入向量（已判决符号）
    y_fb = zeros(1, num_fb);
    for k = 1:num_fb
        if n-k >= 1
            y_fb(k) = decisions(n-k);
        end
    end

    % 联合输入向量
    u = [y_ff(:); y_fb(:)];

    % 前馈+反馈输出
    w_ff = w(1:num_ff);
    w_fb = w(num_ff+1:end);
    pn = w_ff' * y_ff(:);              % 前馈输出
    qn = w_fb' * y_fb(:);              % 反馈输出
    x_hat(n) = pn + qn;

    % 误差计算
    if n <= T
        % 训练模式：用已知符号
        desired = training(n);
    else
        % 判决引导模式
        desired = qpsk_decision(x_hat(n));
    end
    eq_error(n) = desired - x_hat(n);
    decisions(n) = desired;

    % RLS权重更新
    Pu = P * u;
    denom = lambda_rls + u' * Pu;
    K = Pu / denom;
    w = w + K * conj(eq_error(n));
    P = (P - K * u' * P) / lambda_rls;

    % PLL更新（二阶锁相环）
    if pll_enable && n >= 3
        disc_out(n) = imag(log(pn * conj(eq_error(n) + pn) + 1e-30));
        nco_phase(n) = 2*nco_phase(n-1) - nco_phase(n-2) ...
                       + Kp * disc_out(n) - Ki * disc_out(n-1);
    end
end

%% ========== 提取数据段 + 估计噪声方差 ========== %%
data_symbols = x_hat(data_start : end);

% 最近邻判决
data_decisions = zeros(size(data_symbols));
for k = 1:length(data_symbols)
    data_decisions(k) = qpsk_decision(data_symbols(k));
end

% 估计均衡后噪声方差（从均衡输出与判决的距离）
coefficient = sum(data_symbols ./ (data_decisions + 1e-30)) / length(data_symbols);
noise_var_est = mean(abs(coefficient * data_decisions - data_symbols).^2);
noise_var_est = max(noise_var_est, 1e-10);

%% ========== 计算LLR（QPSK） ========== %%
LLR_out = zeros(1, 2 * length(data_symbols));
LLR_out(1:2:end) = sqrt(8) * real(coefficient) * real(data_symbols) / noise_var_est;
LLR_out(2:2:end) = sqrt(8) * real(coefficient) * imag(data_symbols) / noise_var_est;

end

% --------------- QPSK硬判决 --------------- %
function d = qpsk_decision(x)
% 最近QPSK星座点判决
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
[~, idx] = min(abs(x - constellation));
d = constellation(idx);
end
