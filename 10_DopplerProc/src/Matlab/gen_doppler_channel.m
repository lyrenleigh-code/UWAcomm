function [r, channel_info] = gen_doppler_channel(s, fs, alpha_base, paths, snr_db, time_varying)
% 功能：时变多普勒水声信道模型（α随时间波动）
% 版本：V1.0.0
% 输入：
%   s            - 发射基带信号 (1xN 复数)
%   fs           - 采样率 (Hz)
%   alpha_base   - 基础多普勒因子 α=v/c (如 0.001 对应 1.5m/s @1500m/s)
%   paths        - 多径参数结构体（可选）
%       .delays  : 各径时延 (1xP 秒)
%       .gains   : 各径复增益 (1xP)
%       默认：3径，delays=[0, 2e-3, 5e-3]，gains=[1, 0.5*exp(j0.3), 0.2*exp(j1.1)]
%   snr_db       - 信噪比 (dB，默认 20)
%   time_varying - 时变参数（可选）
%       .enable     : 是否启用时变 (默认 true)
%       .drift_rate : α漂移速率 (每秒变化量，默认 alpha_base*0.1)
%       .jitter_std : α抖动标准差 (默认 alpha_base*0.02)
%       .model      : 时变模型 ('linear_drift'/'sinusoidal'/'random_walk')
% 输出：
%   r            - 接收信号 (1xM 复数)
%   channel_info - 信道信息结构体
%       .alpha_true    : 瞬时α序列 (1xM)
%       .alpha_base    : 基础α
%       .noise_var     : 噪声方差
%       .paths         : 多径参数
%       .fs            : 采样率

%% ========== 入参解析 ========== %%
s = s(:).';
N = length(s);

if nargin < 6 || isempty(time_varying)
    time_varying = struct('enable', true, 'drift_rate', alpha_base*0.1, ...
                          'jitter_std', alpha_base*0.02, 'model', 'random_walk');
end
if nargin < 5 || isempty(snr_db), snr_db = 20; end
if nargin < 4 || isempty(paths)
    paths.delays = [0, 2e-3, 5e-3];
    paths.gains = [1, 0.5*exp(1j*0.3), 0.2*exp(1j*1.1)];
end
if nargin < 3 || isempty(alpha_base), alpha_base = 0.001; end

P = length(paths.delays);

%% ========== 参数校验 ========== %%
if isempty(s), error('发射信号不能为空！'); end
if fs <= 0, error('采样率必须为正数！'); end

%% ========== 生成时变多普勒序列 ========== %%
t = (0:N-1) / fs;
T_total = N / fs;

if time_varying.enable
    switch time_varying.model
        case 'linear_drift'
            % 线性漂移：α(t) = α_base + drift_rate * t
            alpha_t = alpha_base + time_varying.drift_rate * t;

        case 'sinusoidal'
            % 正弦波动：α(t) = α_base + A*sin(2π*f_osc*t)
            f_osc = 0.5;              % 振荡频率0.5Hz
            A = time_varying.jitter_std * 3;
            alpha_t = alpha_base + A * sin(2*pi*f_osc*t);

        case 'random_walk'
            % 随机游走：α(t) = α_base + cumsum(噪声)
            jitter = time_varying.jitter_std * randn(1, N) / sqrt(fs);
            alpha_t = alpha_base + cumsum(jitter);
            % 限幅防止α变号
            alpha_t = max(alpha_t, alpha_base * 0.5);
            alpha_t = min(alpha_t, alpha_base * 1.5);

        otherwise
            alpha_t = alpha_base * ones(1, N);
    end
else
    alpha_t = alpha_base * ones(1, N);
end

%% ========== 多普勒时间伸缩 + 多径叠加 ========== %%
% 计算伸缩后的采样时刻
t_stretched = cumsum(1 ./ (1 + alpha_t)) / fs;
t_orig = (0:N-1) / fs;

% 对每条路径做伸缩+叠加
max_delay_samp = ceil(max(paths.delays) * fs) + 10;
r = zeros(1, N + max_delay_samp);

for p = 1:P
    delay_samp = round(paths.delays(p) * fs);

    % 多普勒伸缩：在新时间轴上插值
    s_doppler = interp1(t_orig, s, t_stretched, 'spline', 0);

    % 相位旋转（载波多普勒效应的简化模型）
    phase_shift = 2 * pi * alpha_base * fs * t_stretched;
    s_shifted = s_doppler .* exp(1j * phase_shift);

    % 时延+叠加
    idx_start = 1 + delay_samp;
    idx_end = min(idx_start + N - 1, length(r));
    r(idx_start:idx_end) = r(idx_start:idx_end) + paths.gains(p) * s_shifted(1:idx_end-idx_start+1);
end

% 截取到合理长度
r = r(1:N+max_delay_samp);

%% ========== 加噪 ========== %%
sig_power = mean(abs(r).^2);
noise_var = sig_power / 10^(snr_db/10);
noise = sqrt(noise_var/2) * (randn(size(r)) + 1j*randn(size(r)));
r = r + noise;

%% ========== 输出信息 ========== %%
channel_info.alpha_true = alpha_t;
channel_info.alpha_base = alpha_base;
channel_info.noise_var = noise_var;
channel_info.paths = paths;
channel_info.fs = fs;
channel_info.snr_db = snr_db;
channel_info.time_varying = time_varying;

end
