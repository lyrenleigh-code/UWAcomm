function [phase_est, freq_est, info] = phase_track(signal, method, params)
% 功能：位同步/相位跟踪——实时估计并补偿时变信道引起的相位旋转
% 版本：V1.0.0
% 输入：
%   signal - 均衡后的符号序列 (1xN 复数数组，每个元素为一个符号采样)
%   method - 跟踪算法 (字符串，默认 'pll')
%            'pll'    : 二阶PI锁相环（慢时变首选）
%            'dfpt'   : 判决反馈相位跟踪（中速时变，高SNR）
%            'kalman' : Kalman联合跟踪相位+频偏+频偏斜率（高速时变最优）
%   params - 参数结构体
%       --- PLL 参数 ---
%       .Bn       : 环路噪声带宽(归一化，默认 0.01)
%       .zeta     : 阻尼系数 (默认 1/sqrt(2)≈0.707)
%       .mod_order: 调制阶数 (2=BPSK, 4=QPSK, 默认 4)
%       --- DFPT 参数 ---
%       .mu       : 步长 (默认 0.01)
%       .mod_order: 调制阶数 (默认 4)
%       --- Kalman 参数 ---
%       .Ts       : 符号间隔(秒，默认 1)
%       .q_phase  : 相位过程噪声方差 (默认 1e-4)
%       .q_freq   : 频偏过程噪声方差 (默认 1e-6)
%       .q_frate  : 频偏斜率过程噪声方差 (默认 1e-8)
%       .r_obs    : 观测噪声方差 (默认 0.1)
%       .mod_order: 调制阶数 (默认 4)
% 输出：
%   phase_est - 逐符号相位估计 (1xN 弧度)
%   freq_est  - 逐符号频偏估计 (1xN Hz，仅kalman方法有效，其他返回差分估计)
%   info      - 附加信息结构体
%       .phase_error : 相位误差序列 (1xN)
%       .corrected   : 相位补偿后的符号 (1xN 复数)
%
% 备注：
%   - PLL：e_phi[n] = Im{y[n]*conj(a_hat[n])*exp(-j*phi_hat[n])}
%          phi_hat[n+1] = phi_hat[n] + alpha1*e + alpha2*sum(e)
%   - DFPT：phi_hat[n] = phi_hat[n-1] + mu*Im{y[n]*conj(a_hat[n])}
%   - Kalman：状态 x=[phi, df, d(df)]^T，A=[1,Ts,Ts²/2; 0,1,Ts; 0,0,1]
%   - 三种方法均使用硬判决作为数据估计

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(params), params = struct(); end
if nargin < 2 || isempty(method), method = 'pll'; end
signal = signal(:).';
N = length(signal);

%% ========== 2. 参数校验 ========== %%
if isempty(signal), error('输入信号不能为空！'); end
if ~isfield(params, 'mod_order'), params.mod_order = 4; end

%% ========== 3. 相位跟踪 ========== %%
switch method
    case 'pll'
        [phase_est, phase_error] = pll_track(signal, N, params);

    case 'dfpt'
        [phase_est, phase_error] = dfpt_track(signal, N, params);

    case 'kalman'
        [phase_est, freq_est, phase_error] = kalman_track(signal, N, params);

    otherwise
        error('不支持的相位跟踪方法: %s！支持 pll/dfpt/kalman', method);
end

%% ========== 4. 输出整理 ========== %%
% 频偏估计：非kalman方法用差分近似
if ~strcmp(method, 'kalman')
    freq_est = [0, diff(phase_est)] / (2*pi);
end

% 相位补偿后的符号
info.phase_error = phase_error;
info.corrected = signal .* exp(-1j * phase_est);

end

% --------------- 辅助函数：硬判决（支持BPSK/QPSK/8PSK/16QAM） --------------- %
function d = hard_decision(y, mod_order)
% 最近星座点判决

switch mod_order
    case 2   % BPSK
        d = sign(real(y));
        d(d == 0) = 1;
    case 4   % QPSK
        d = (sign(real(y)) + 1j*sign(imag(y))) / sqrt(2);
        d(real(d)==0) = (1 + 1j*sign(imag(d(real(d)==0)))) / sqrt(2);
    case 8   % 8PSK
        angles = (0:7) * pi/4;
        constellation = exp(1j * angles);
        [~, idx] = min(abs(y - constellation));
        d = constellation(idx);
    otherwise % 通用：QPSK回退
        d = (sign(real(y)) + 1j*sign(imag(y))) / sqrt(2);
end

end

% --------------- 辅助函数1：二阶PI锁相环 --------------- %
function [phase_est, phase_error] = pll_track(signal, N, params)
% PLL相位跟踪
%   e_phi[n] = Im{y[n] * conj(a_hat[n]) * exp(-j*phi_hat[n])}
%   phi_hat[n+1] = phi_hat[n] + alpha1*e + alpha2*sum(e)

if ~isfield(params, 'Bn'), params.Bn = 0.01; end
if ~isfield(params, 'zeta'), params.zeta = 1/sqrt(2); end

% 二阶PI环路滤波器系数（从Bn和zeta推导）
theta_n = params.Bn / (params.zeta + 1/(4*params.zeta));
alpha1 = 4 * params.zeta * theta_n / (1 + 2*params.zeta*theta_n + theta_n^2);
alpha2 = 4 * theta_n^2 / (1 + 2*params.zeta*theta_n + theta_n^2);

phase_est = zeros(1, N);
phase_error = zeros(1, N);
integrator = 0;

for n = 1:N
    % 相位补偿
    y_comp = signal(n) * exp(-1j * phase_est(n));

    % 硬判决
    d = hard_decision(y_comp, params.mod_order);

    % 相位误差检测
    phase_error(n) = imag(y_comp * conj(d));

    % PI环路滤波器更新
    integrator = integrator + phase_error(n);
    if n < N
        phase_est(n+1) = phase_est(n) + alpha1 * phase_error(n) + alpha2 * integrator;
    end
end

end

% --------------- 辅助函数2：判决反馈相位跟踪 --------------- %
function [phase_est, phase_error] = dfpt_track(signal, N, params)
% DFPT相位跟踪
%   phi_hat[n] = phi_hat[n-1] + mu * Im{y[n] * conj(a_hat[n])}

if ~isfield(params, 'mu'), params.mu = 0.01; end

phase_est = zeros(1, N);
phase_error = zeros(1, N);

for n = 1:N
    % 相位补偿
    y_comp = signal(n) * exp(-1j * phase_est(n));

    % 硬判决
    d = hard_decision(y_comp, params.mod_order);

    % 相位误差
    phase_error(n) = imag(y_comp * conj(d));

    % 一阶更新
    if n < N
        phase_est(n+1) = phase_est(n) + params.mu * phase_error(n);
    end
end

end

% --------------- 辅助函数3：Kalman联合相位/频偏/频偏斜率跟踪 --------------- %
function [phase_est, freq_est, phase_error] = kalman_track(signal, N, params)
% Kalman联合跟踪
%   状态 x = [phi, delta_f, delta_delta_f]^T
%   A = [1, Ts, Ts^2/2; 0, 1, Ts; 0, 0, 1]
%   C = [1, 0, 0]

if ~isfield(params, 'Ts'), params.Ts = 1; end
if ~isfield(params, 'q_phase'), params.q_phase = 1e-4; end
if ~isfield(params, 'q_freq'), params.q_freq = 1e-6; end
if ~isfield(params, 'q_frate'), params.q_frate = 1e-8; end
if ~isfield(params, 'r_obs'), params.r_obs = 0.1; end

Ts = params.Ts;

% 状态转移矩阵
A = [1, 2*pi*Ts, 2*pi*Ts^2/2;
     0, 1,       Ts;
     0, 0,       1];

% 观测矩阵
C = [1, 0, 0];

% 过程噪声协方差
Q = diag([params.q_phase, params.q_freq, params.q_frate]);

% 观测噪声方差
R = params.r_obs;

% 初始状态
x = [0; 0; 0];              % [相位; 频偏Hz; 频偏斜率Hz/s]
P = diag([0.1, 1, 0.1]);    % 初始协方差

phase_est = zeros(1, N);
freq_est = zeros(1, N);
phase_error = zeros(1, N);

for n = 1:N
    % ---------- 预测 ---------- %
    x_pred = A * x;
    P_pred = A * P * A' + Q;

    % ---------- 观测 ---------- %
    % 用预测相位补偿，做硬判决后提取相位误差
    y_comp = signal(n) * exp(-1j * x_pred(1));
    d = hard_decision(y_comp, params.mod_order);
    z = angle(signal(n) * conj(d));   % 观测相位

    % ---------- 更新 ---------- %
    innovation = z - C * x_pred;
    % 相位回卷到 [-pi, pi]
    innovation = mod(innovation + pi, 2*pi) - pi;

    S = C * P_pred * C' + R;
    K = P_pred * C' / S;

    x = x_pred + K * innovation;
    P = (eye(3) - K * C) * P_pred;

    % ---------- 记录 ---------- %
    phase_est(n) = x(1);
    freq_est(n) = x(2);
    phase_error(n) = innovation;
end

end
