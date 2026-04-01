function [rx, ch_info] = gen_uwa_channel(tx, ch_params)
% 功能：简化水声信道仿真——多径时变+宽带多普勒伸缩+AWGN
% 版本：V1.0.0
% 输入：
%   tx        - 发射基带信号 (1×N_tx 复数)
%   ch_params - 信道参数结构体
%       .fs           : 采样率 (Hz，默认 48000)
%       .num_paths    : 路径数 (默认 5)
%       .max_delay_ms : 最大时延 (ms，默认 10)
%       .delay_profile: 时延功率谱类型 ('exponential'(默认)/'uniform'/'custom')
%       .delays_s     : 自定义时延向量 (s，仅delay_profile='custom'时使用)
%       .gains        : 自定义复增益向量 (仅delay_profile='custom'时使用)
%       .doppler_rate : 多普勒伸缩率 α (无量位，默认 0，正=靠近/压缩)
%       .fading_type  : 衰落类型 ('static'(默认)/'slow'/'fast')
%       .fading_fd_hz : 最大多普勒频移 (Hz，仅slow/fast，默认 2)
%       .snr_db       : 信噪比 (dB，默认 15。设Inf则不加噪)
%       .seed         : 随机种子 (默认 0)
% 输出：
%   rx        - 接收基带信号 (1×N_rx 复数，N_rx可能因多普勒伸缩与tx长度不同)
%   ch_info   - 信道信息结构体
%       .h_time     : 时变信道矩阵 (num_paths × N_tx，每列为一个时刻的抽头)
%       .delays_s   : 各路径时延 (s)
%       .delays_samp: 各路径时延 (采样点)
%       .gains_init : 初始复增益
%       .doppler_rate: 实际多普勒伸缩率
%       .noise_var  : 噪声方差
%
% 备注：
%   时变模型：每条路径的复增益在时间轴上按Jakes模型（slow/fast）或保持不变（static）
%   宽带多普勒：对整个信号做重采样（时间压缩/扩展），模拟收发相对运动
%   简化假设：各路径独立衰落，无海面/海底反射几何建模

%% ========== 1. 入参解析 ========== %%
if nargin < 2, ch_params = struct(); end
fs            = getfield_def(ch_params, 'fs', 48000);
num_paths     = getfield_def(ch_params, 'num_paths', 5);
max_delay_ms  = getfield_def(ch_params, 'max_delay_ms', 10);
delay_profile = getfield_def(ch_params, 'delay_profile', 'exponential');
doppler_rate  = getfield_def(ch_params, 'doppler_rate', 0);
fading_type   = getfield_def(ch_params, 'fading_type', 'static');
fading_fd_hz  = getfield_def(ch_params, 'fading_fd_hz', 2);
snr_db        = getfield_def(ch_params, 'snr_db', 15);
seed          = getfield_def(ch_params, 'seed', 0);

tx = tx(:).';
N_tx = length(tx);
rng(seed);

%% ========== 2. 生成多径时延和初始增益 ========== %%
max_delay_s = max_delay_ms / 1000;
max_delay_samp = round(max_delay_s * fs);

switch delay_profile
    case 'custom'
        delays_s = ch_params.delays_s(:).';
        gains_init = ch_params.gains(:).';
        num_paths = length(delays_s);
    case 'uniform'
        delays_s = linspace(0, max_delay_s, num_paths);
        gains_init = (randn(1,num_paths) + 1j*randn(1,num_paths)) / sqrt(2*num_paths);
    otherwise % 'exponential'
        delays_s = sort(rand(1,num_paths)) * max_delay_s;
        delays_s(1) = 0;  % 直达径
        % 指数衰减功率谱
        decay = exp(-3 * delays_s / max_delay_s);
        phases = exp(2j*pi*rand(1,num_paths));
        gains_init = sqrt(decay) .* phases;
end

% 归一化总功率为1
gains_init = gains_init / sqrt(sum(abs(gains_init).^2));
delays_samp = round(delays_s * fs);

%% ========== 3. 时变衰落（Jakes模型） ========== %%
h_time = zeros(num_paths, N_tx);

switch fading_type
    case 'static'
        for p = 1:num_paths
            h_time(p,:) = gains_init(p) * ones(1, N_tx);
        end
    case {'slow', 'fast'}
        % Jakes模型：每条路径独立衰落
        if strcmpi(fading_type, 'slow')
            fd = fading_fd_hz;     % 慢衰落
        else
            fd = fading_fd_hz * 5; % 快衰落（5倍多普勒频移）
        end
        t = (0:N_tx-1) / fs;
        N_osc = 8;  % Jakes振荡器个数
        for p = 1:num_paths
            % 用多个正弦叠加近似Jakes谱
            fading_coeff = zeros(1, N_tx);
            for n_osc = 1:N_osc
                theta = 2*pi*rand;
                beta = pi*n_osc / N_osc;
                fading_coeff = fading_coeff + exp(1j*(2*pi*fd*cos(beta)*t + theta));
            end
            fading_coeff = fading_coeff / sqrt(N_osc);
            h_time(p,:) = gains_init(p) * fading_coeff;
        end
    otherwise
        error('不支持的衰落类型: %s', fading_type);
end

%% ========== 4. 多径卷积（时变） ========== %%
N_rx_base = N_tx + max_delay_samp;
rx_multipath = zeros(1, N_rx_base);

for p = 1:num_paths
    d = delays_samp(p);
    for n = 1:N_tx
        if n+d <= N_rx_base
            rx_multipath(n+d) = rx_multipath(n+d) + h_time(p,n) * tx(n);
        end
    end
end

%% ========== 5. 宽带多普勒伸缩（重采样） ========== %%
if abs(doppler_rate) > 1e-10
    % 多普勒伸缩：接收信号时间轴压缩/扩展
    % α>0（靠近）：时间压缩，采样率等效升高
    % α<0（远离）：时间扩展
    N_rx_orig = length(rx_multipath);
    scale = 1 / (1 + doppler_rate);  % 时间缩放因子
    N_rx_new = round(N_rx_orig * scale);
    t_orig = (0:N_rx_orig-1) / fs;
    t_new = linspace(0, t_orig(end), N_rx_new);
    rx_doppler = interp1(t_orig, rx_multipath, t_new, 'spline', 0);
else
    rx_doppler = rx_multipath;
end

%% ========== 6. 加性高斯白噪声 ========== %%
if isinf(snr_db)
    noise_var = 0;
    rx = rx_doppler;
else
    sig_power = mean(abs(rx_doppler).^2);
    noise_var = sig_power * 10^(-snr_db/10);
    if isreal(rx_doppler)
        % 通带实信号：实数噪声
        noise = sqrt(noise_var) * randn(size(rx_doppler));
    else
        % 复基带信号：复数噪声
        noise = sqrt(noise_var/2) * (randn(size(rx_doppler)) + 1j*randn(size(rx_doppler)));
    end
    rx = rx_doppler + noise;
end

%% ========== 7. 输出信道信息 ========== %%
ch_info.h_time = h_time;
ch_info.delays_s = delays_s;
ch_info.delays_samp = delays_samp;
ch_info.gains_init = gains_init;
ch_info.doppler_rate = doppler_rate;
ch_info.noise_var = noise_var;
ch_info.fs = fs;
ch_info.num_paths = num_paths;
ch_info.fading_type = fading_type;

end

% --------------- 辅助函数：带默认值的字段读取 --------------- %
function val = getfield_def(s, field, default)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default;
    end
end
