function [R_array, channel_info] = gen_uwa_channel_array(s, fs, alpha_base, paths, snr_db, time_varying, array)
% 功能：阵列水声信道仿真——M阵元ULA，各阵元独立经历信道但具有精确空间时延
% 版本：V1.0.0
% 输入：
%   s            - 发射基带信号 (1xN 复数)
%   fs           - 采样率 (Hz)
%   alpha_base   - 基础多普勒因子 α=v/c
%   paths        - 多径参数结构体（同gen_doppler_channel）
%   snr_db       - 信噪比 (dB)
%   time_varying - 时变参数（同gen_doppler_channel）
%   array        - 阵列参数结构体
%       .M     : 阵元数 (默认 4)
%       .d     : 阵元间距 (米，默认 lambda/2)
%       .theta : 信号入射角 (弧度，默认 0，即正入射)
%       .c     : 声速 (m/s，默认 1500)
%       .fc    : 载频 (Hz，默认 12000)
% 输出：
%   R_array      - 各阵元接收信号 (MxN_rx 复数矩阵，每行为一个阵元)
%   channel_info - 信道信息结构体
%       .alpha_true     : 瞬时α序列
%       .array          : 阵列参数
%       .tau_spatial     : 各阵元空间时延 (1xM 秒)
%       .per_element     : 各阵元的gen_doppler_channel输出信息 (cell)
%
% 备注：
%   - 每阵元空间时延: tau_m = (m-1)*d*cos(theta)/c
%   - tau_m叠加到各径时延上后独立调用gen_doppler_channel
%   - 保持浮点精度，不四舍五入为整数样点

%% ========== 1. 入参解析 ========== %%
if nargin < 7 || isempty(array), array = struct(); end
if nargin < 6 || isempty(time_varying), time_varying = struct('enable', false); end
if nargin < 5 || isempty(snr_db), snr_db = 20; end
if nargin < 4 || isempty(paths), paths = []; end

if ~isfield(array, 'c'), array.c = 1500; end
if ~isfield(array, 'fc'), array.fc = 12000; end
if ~isfield(array, 'M'), array.M = 4; end
if ~isfield(array, 'd')
    lambda = array.c / array.fc;
    array.d = lambda / 2;
end
if ~isfield(array, 'theta'), array.theta = 0; end

s = s(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(s), error('发射信号不能为空！'); end
if array.M < 1, error('阵元数必须>=1！'); end

%% ========== 3. 计算各阵元空间时延 ========== %%
M = array.M;
tau_spatial = (0:M-1) * array.d * cos(array.theta) / array.c;  % 精确浮点时延(秒)

%% ========== 4. 逐阵元生成接收信号 ========== %%
% 先调用一次获取输出长度
if isempty(paths)
    paths_m0 = [];
else
    paths_m0 = paths;
end
[r0, info0] = gen_doppler_channel(s, fs, alpha_base, paths_m0, snr_db, time_varying);
N_rx = length(r0);

per_element = cell(1, M);
per_element{1} = info0;

% 收集所有阵元信号（长度可能略有差异，统一截断到最短）
raw_signals = cell(1, M);
raw_signals{1} = r0;

for m = 2:M
    % 将空间时延叠加到各径时延上
    if isempty(paths)
        paths_m = struct('delays', [0, 2e-3, 5e-3] + tau_spatial(m), ...
                         'gains', [1, 0.5*exp(1j*0.3), 0.2*exp(1j*1.1)]);
    else
        paths_m = paths;
        paths_m.delays = paths.delays + tau_spatial(m);
    end

    [raw_signals{m}, per_element{m}] = gen_doppler_channel(s, fs, alpha_base, paths_m, snr_db, time_varying);
end

% 统一长度（截断到最短阵元输出）
min_len = min(cellfun(@length, raw_signals));
R_array = zeros(M, min_len);
for m = 1:M
    R_array(m, :) = raw_signals{m}(1:min_len);
end
N_rx = min_len;

%% ========== 5. 输出信道信息 ========== %%
channel_info.alpha_true = info0.alpha_true;
channel_info.alpha_base = alpha_base;
channel_info.array = array;
channel_info.tau_spatial = tau_spatial;
channel_info.per_element = per_element;
channel_info.fs = fs;
channel_info.snr_db = snr_db;

end
