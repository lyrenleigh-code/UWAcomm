function [rx_pb, ch_info] = gen_uwa_channel_pb(tx_pb, ch_params, fc)
% 功能：passband 原生水声信道（方案 A）—多径卷积 + 多普勒伸缩 + Jakes 时变 + passband AWGN
% 版本：V1.1.0（加 Jakes 时变衰落支持）
% 输入：
%   tx_pb     - 发射 passband 实信号 (1×N)
%   ch_params - 结构体：
%       .fs           采样率 (Hz)
%       .delays_s     各路径时延 (1×P, 秒)
%       .gains        各路径基带复增益 (1×P, 复数) — static 下直接使用；slow/fast 下作初始值
%       .doppler_rate 宽带多普勒伸缩率 α（无量位；正=靠近/压缩）
%       .fading_type  'static' | 'slow' | 'fast'
%       .fading_fd_hz 最大多普勒频移 (Hz，仅 slow/fast 使用，Jakes 谱带宽)
%       .snr_db       信噪比 (dB)；Inf 不加噪
%       .seed         随机种子
%   fc        - 载波频率 (Hz)
% 输出：
%   rx_pb     - 接收 passband 实信号 (1×N)
%   ch_info   - struct
%       .delays_samp   各径时延（采样点）
%       .gains_pb_mean 各径 passband 实增益平均值（参考）
%       .h_time        时变 passband 实抽头矩阵 (P×N) — static 下每列相同，时变下每列变化
%       .t_axis        时间轴 (1×N, 秒)
%       .noise_var     加噪方差
%       .mode          'passband'
%       .fading_type   实际使用的衰落类型
%
% 设计：
%   - 物理信道 h_pb(t, τ) = Re{ g_bb(t) * exp(j·2π·fc·τ) } 其中 g_bb(t) 为基带复增益包络
%   - static: g_bb 恒定 = ch_params.gains
%   - slow/fast: g_bb(t) = gains * Jakes_envelope(t, fd)  用 N 路正弦和法合成 Jakes 谱
%   - Doppler 伸缩：最后对 rx_pb 做 spline resample，与 Jakes 独立

fs = ch_params.fs;
delays_s = ch_params.delays_s(:).';
gains_bb = ch_params.gains(:).';
P = length(delays_s);

tx_pb = tx_pb(:).';
N_tx = length(tx_pb);

if isfield(ch_params, 'seed')
    rng(ch_params.seed);
end

delays_samp = round(delays_s * fs);
max_d = max(delays_samp);

%% ---- 时变包络 g_bb(p, n)：static 恒定；slow/fast Jakes ----
fading_type = lower(ch_params.fading_type);
switch fading_type
    case 'static'
        % 恒定：每径 g_bb(n) = gains_bb(p)，不随时间变
        h_time = compute_passband_taps_static(gains_bb, delays_s, fc);  % P×1
        h_time = repmat(h_time, 1, N_tx);                                % P×N_tx
    case {'slow', 'fast'}
        fd = ch_params.fading_fd_hz;
        if fd <= 0
            % 退化为 static
            h_time = compute_passband_taps_static(gains_bb, delays_s, fc);
            h_time = repmat(h_time, 1, N_tx);
        else
            % Jakes 包络（Clarke 模型：N 路正弦和）
            N_sines = 16;
            t_axis = (0:N_tx-1) / fs;
            h_time = zeros(P, N_tx);
            for p = 1:P
                % 每径独立相位
                theta_k = 2*pi*(1:N_sines)/N_sines + 2*pi*rand()/N_sines;
                phi_k   = 2*pi*rand(1, N_sines);
                g_p = zeros(1, N_tx);
                for k = 1:N_sines
                    g_p = g_p + exp(1j * (2*pi*fd*cos(theta_k(k))*t_axis + phi_k(k)));
                end
                g_p = g_p / sqrt(N_sines);                 % 归一化为单位平均功率
                g_p = g_p * gains_bb(p);                    % 加上 tap 初始幅度+相位
                % 转 passband 实抽头：h_pb = Re{ g_bb * exp(j 2π fc τ) }
                h_time(p, :) = real(g_p * exp(1j * 2*pi * fc * delays_s(p)));
            end
        end
    otherwise
        error('gen_uwa_channel_pb: 不支持的 fading_type=%s', fading_type);
end

%% ---- 多径卷积（逐样本时变抽头） ----
if strcmpi(fading_type, 'static')
    % 静态：使用标量 tap 加速
    gains_pb = h_time(:, 1).';   % 1×P
    rx_pb = zeros(1, N_tx + max_d);
    for p = 1:P
        d = delays_samp(p);
        rx_pb(d+1 : d+N_tx) = rx_pb(d+1 : d+N_tx) + gains_pb(p) * tx_pb;
    end
    rx_pb = rx_pb(1:N_tx);
else
    % 时变：每样本的每条路径乘时变 tap（逐径相加）
    rx_pb = zeros(1, N_tx + max_d);
    for p = 1:P
        d = delays_samp(p);
        tap_t = h_time(p, :);   % 1×N_tx 时变实抽头
        rx_pb(d+1 : d+N_tx) = rx_pb(d+1 : d+N_tx) + tap_t .* tx_pb;
    end
    rx_pb = rx_pb(1:N_tx);
end

%% ---- 宽带多普勒（spline 重采样） ----
if isfield(ch_params, 'doppler_rate') && abs(ch_params.doppler_rate) > 1e-10
    alpha = ch_params.doppler_rate;
    t_orig = (0:N_tx-1) / fs;
    t_new  = t_orig * (1 + alpha);
    rx_pb = interp1(t_orig, rx_pb, t_new, 'spline', 0);
end

%% ---- passband AWGN ----
if isfinite(ch_params.snr_db)
    sig_pwr = mean(rx_pb.^2);
    noise_var = sig_pwr * 10^(-ch_params.snr_db / 10);
    rx_pb = rx_pb + sqrt(noise_var) * randn(size(rx_pb));
else
    noise_var = 0;
end

%% ---- ch_info ----
ch_info = struct();
ch_info.delays_samp   = delays_samp;
ch_info.gains_pb_mean = mean(h_time, 2).';
ch_info.h_time        = h_time;
ch_info.t_axis        = (0:N_tx-1) / fs;
ch_info.noise_var     = noise_var;
ch_info.mode          = 'passband';
ch_info.fading_type   = fading_type;
ch_info.fs            = fs;
ch_info.delays_s      = delays_s;
ch_info.doppler_rate  = getfield_def(ch_params, 'doppler_rate', 0);
ch_info.fading_fd_hz  = getfield_def(ch_params, 'fading_fd_hz', 0);

end

% ================================================================
function gains_pb = compute_passband_taps_static(gains_bb, delays_s, fc)
% 静态：h_pb(τ_i) = Re{ gains_bb(i) * exp(j 2π fc τ_i) }
gains_pb = real(gains_bb(:) .* exp(1j * 2*pi * fc * delays_s(:)));
end

function v = getfield_def(s, fname, default)
if isfield(s, fname), v = s.(fname); else, v = default; end
end
