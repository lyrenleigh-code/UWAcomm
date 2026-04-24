function [r, channel_info] = gen_doppler_channel(s, fs, alpha_base, paths, snr_db, time_varying, fc)
% 功能：时变多普勒水声信道模型（α随时间波动）
% 版本：V1.5.0（2026-04-22 修复：顺序改为多径 → Doppler（Option 1），
%              共同 α 下 Doppler 作用于 TOTAL 多径信号（"统一压缩/扩展"），
%              接收端 poly_resample 补偿恢复多径延迟到 nominal τ_p；
%              V1.4 的 Option 2 顺序会让延迟缩放 (1+α)τ_p 导致 BEM 失配）
% 输入：
%   s            - 发射基带信号 (1xN 复数)
%   fs           - 采样率 (Hz)
%   alpha_base   - 基础多普勒因子 α=v/c (如 0.001 对应 1.5m/s @1500m/s)
%                  α>0：接近（时间压缩，采样"更快"），输出尾部可能因信号结束为零
%                  α<0：远离（时间扩展），RX 只能捕获部分 TX 信号
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
%   fc           - 载波频率 (Hz，可选)。当 s 为基带信号时强烈建议传入
%                  → 基带相位旋转 exp(j·2π·fc·∫α(τ)dτ)（物理正确）
%                  未传入时沿用 V1.0 的 α·fs·t 近似（当 s 为基带但 fs≠fc 时不准）
% 输出：
%   r            - 接收信号 (1xM 复数)
%   channel_info - 信道信息结构体
%       .alpha_true    : 瞬时α序列 (1xM)
%       .alpha_base    : 基础α
%       .noise_var     : 噪声方差
%       .paths         : 多径参数
%       .fs            : 采样率
%       .fc            : 载波频率（若提供）
%
% 物理模型（V1.2）：
%   rx_bb[n] = s_bb((1+α)·n/fs) · exp(j·2π·fc·α·n/fs)       （constant α）
%   对应通带 rx_pb[n] = Re{s_bb((1+α)·n/fs)·exp(j·2π·fc·(1+α)·n/fs)}
%   与 gen_uwa_channel 的 doppler_rate 约定一致（α>0=压缩）
%
% 历史记录：
%   V1.0: phase_shift = 2π·α_base·fs·t_stretched （基带信号下 fs/fc 倍率偏差）
%   V1.1: phase_shift = 2π·fc·cumsum(alpha_t)/fs （物理正确积分相位，向后兼容）
%   V1.2: dt = (1+α)/fs 方向翻转（V1.0/V1.1 用 1/((1+α)·fs) baseband 方向反）

%% ========== 入参解析 ========== %%
s = s(:).';
N = length(s);

if nargin < 7 || isempty(fc), fc = []; end
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
            % 限幅防止α变号（当 α_base=0 时退化为常量 0，需调用方注意）
            if alpha_base ~= 0
                alpha_t = max(alpha_t, alpha_base * 0.5);
                alpha_t = min(alpha_t, alpha_base * 1.5);
            end

        otherwise
            alpha_t = alpha_base * ones(1, N);
    end
else
    alpha_t = alpha_base * ones(1, N);
end

%% ========== 多径叠加（先） + 多普勒时间伸缩（后） ========== %%
% V1.5：Option 1 顺序（多径先、Doppler 后）= "统一压缩/扩展"
%        所有路径共享同一 α 下，Doppler 作用在 TOTAL 信号上
%        接收端通带 poly_resample 补偿 → 多径延迟完美恢复到 nominal τ_p
% V1.4：Option 2 顺序（错）：Doppler 先、多径后 → 延迟被缩放成 (1+α)τ_p
% V1.3：α<0 输出长度扩展（V1.5 自然处理：Doppler 下 N_out 按 poly_resample 输出长度）
% V1.2：dt=(1+α)/fs 方向正确
% V1.1：phase_shift = 2π·fc·cumsum(α)/fs 物理正确

% 判定 constant α（方差极小 或 time_varying.enable=false）
alpha_const = (max(alpha_t) - min(alpha_t)) < 1e-12;

%% Step 1：多径叠加（nominal 延迟，未加 Doppler）
max_delay_samp = ceil(max(paths.delays) * fs) + 10;
y_mpath = zeros(1, N + max_delay_samp);
for p = 1:P
    delay_samp = round(paths.delays(p) * fs);
    idx_start = 1 + delay_samp;
    idx_end = min(idx_start + N - 1, length(y_mpath));
    y_mpath(idx_start:idx_end) = y_mpath(idx_start:idx_end) + ...
                                  paths.gains(p) * s(1:idx_end-idx_start+1);
end

%% Step 2：对整个多径信号应用 Doppler
if alpha_const && ~isempty(fc) && abs(alpha_base) > 1e-10
    %% Constant α：poly_resample（与 RX 补偿形成完美匹配对）
    [p_num, q_den] = rat(1 + alpha_base, 1e-7);
    y_dop = poly_resample(y_mpath, q_den, p_num);   % 时间压缩 1/(1+α)
    N_out_bb = length(y_dop);
    % 基带 CFO：exp(j·2π·fc·α·n/fs)
    phase_shift = 2 * pi * fc * alpha_base * (0:N_out_bb-1) / fs;
    r = y_dop .* exp(1j * phase_shift);
elseif alpha_const && abs(alpha_base) < 1e-10
    %% α=0 直通
    r = y_mpath;
    N_out_bb = length(r);
elseif alpha_const && isempty(fc)
    %% constant α 无 fc：fallback 到 V1.0 公式
    [p_num, q_den] = rat(1 + alpha_base, 1e-7);
    y_dop = poly_resample(y_mpath, q_den, p_num);
    N_out_bb = length(y_dop);
    warning('gen_doppler_channel:NoFc', '未传入 fc，使用 V1.0 α·fs·t 相位近似');
    phase_shift = 2 * pi * alpha_base * fs * (0:N_out_bb-1) / fs;
    r = y_dop .* exp(1j * phase_shift);
else
    %% Time-varying α：interp1 spline（polyphase 不支持动态比率）
    % 将 alpha_t 扩展/截断到 y_mpath 长度
    N_mpath = length(y_mpath);
    if length(alpha_t) < N_mpath
        alpha_t = [alpha_t, alpha_t(end) * ones(1, N_mpath - length(alpha_t))];
    elseif length(alpha_t) > N_mpath
        alpha_t = alpha_t(1:N_mpath);
    end
    alpha_worst = min(alpha_t);
    if alpha_worst < 0
        N_out_bb = ceil(N_mpath / (1 + alpha_worst));
        alpha_t = [alpha_t, alpha_t(end) * ones(1, N_out_bb - N_mpath)];
    else
        N_out_bb = N_mpath;
    end
    dt = (1 + alpha_t) / fs;
    t_stretched = [0, cumsum(dt(1:end-1))];
    t_orig = (0:N_mpath-1) / fs;
    if ~isempty(fc)
        phase_shift = 2 * pi * fc * cumsum(alpha_t) / fs;
    else
        warning('gen_doppler_channel:NoFc', '未传入 fc，使用 V1.0 α·fs·t 相位近似');
        phase_shift = 2 * pi * alpha_base * fs * t_stretched;
    end
    y_dop = interp1(t_orig, y_mpath, t_stretched, 'spline', 0);
    r = y_dop .* exp(1j * phase_shift);
end

%% ========== 加噪 ========== %%
sig_power = mean(abs(r).^2);
if isinf(snr_db)
    noise_var = 0;
else
    noise_var = sig_power / 10^(snr_db/10);
end
if noise_var > 0
    noise = sqrt(noise_var/2) * (randn(size(r)) + 1j*randn(size(r)));
    r = r + noise;
end

%% ========== 输出信息 ========== %%
channel_info.alpha_true = alpha_t;
channel_info.alpha_base = alpha_base;
channel_info.noise_var = noise_var;
channel_info.paths = paths;
channel_info.fs = fs;
channel_info.fc = fc;
channel_info.snr_db = snr_db;
channel_info.time_varying = time_varying;

end
