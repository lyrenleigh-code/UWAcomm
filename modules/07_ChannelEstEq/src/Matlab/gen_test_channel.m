function [h, H_freq, channel_info] = gen_test_channel(N, num_paths, max_delay, snr_db, channel_type)
% 功能：生成简化多径信道模型（供模块7测试使用）
% 版本：V1.0.0
% 输入：
%   N            - 信道长度/FFT点数 (正整数，默认 64)
%   num_paths    - 多径数 (正整数，默认 5)
%   max_delay    - 最大时延（抽头数，默认 15）
%   snr_db       - 信噪比 (dB，默认 20)
%   channel_type - 信道类型 ('sparse'(默认)/'dense'/'exponential')
% 输出：
%   h            - 时域信道冲激响应 (1xN)
%   H_freq       - 频域信道响应 (1xN)
%   channel_info - 信道信息结构体
%       .num_paths, .max_delay, .snr_db, .noise_var, .path_delays, .path_gains

%% ========== 入参解析 ========== %%
if nargin < 5 || isempty(channel_type), channel_type = 'sparse'; end
if nargin < 4 || isempty(snr_db), snr_db = 20; end
if nargin < 3 || isempty(max_delay), max_delay = 15; end
if nargin < 2 || isempty(num_paths), num_paths = 5; end
if nargin < 1 || isempty(N), N = 64; end

%% ========== 生成信道 ========== %%
h = zeros(1, N);

switch channel_type
    case 'sparse'
        % 稀疏信道：随机位置的脉冲
        delays = sort(randperm(max_delay, num_paths));
        gains = (randn(1, num_paths) + 1j*randn(1, num_paths)) / sqrt(2);
        % 第一径最强
        gains(1) = gains(1) * 2;
        h(delays) = gains;

    case 'dense'
        % 密集信道：连续抽头衰减
        h(1:min(num_paths, N)) = (randn(1, min(num_paths,N)) + 1j*randn(1, min(num_paths,N))) / sqrt(2);

    case 'exponential'
        % 指数衰减信道
        delays = sort(randperm(max_delay, num_paths));
        decay = exp(-(0:num_paths-1) / (num_paths/3));
        gains = decay .* (randn(1, num_paths) + 1j*randn(1, num_paths)) / sqrt(2);
        h(delays) = gains;
end

% 归一化为单位能量
h = h / sqrt(sum(abs(h).^2));

%% ========== 频域响应 ========== %%
H_freq = fft(h, N);

%% ========== 噪声方差 ========== %%
noise_var = 1 / (10^(snr_db/10));

%% ========== 输出信息 ========== %%
channel_info.num_paths = num_paths;
channel_info.max_delay = max_delay;
channel_info.snr_db = snr_db;
channel_info.noise_var = noise_var;
channel_info.path_delays = find(h ~= 0);
channel_info.path_gains = h(h ~= 0);
channel_info.channel_type = channel_type;

end
