function [R_array, channel_info] = gen_doppler_channel_array(s, fs, alpha_base, paths, snr_db, array_config, theta, time_varying)
% 功能：多通道阵列信道仿真——每个阵元独立经历信道+精确空间时延
% 版本：V1.0.0
% 输入：
%   s            - 发射基带信号 (1xN)
%   fs           - 采样率 (Hz)
%   alpha_base   - 基础多普勒因子
%   paths        - 多径参数（同gen_doppler_channel）
%   snr_db       - 信噪比 (dB)
%   array_config - 阵列配置（由gen_array_config生成）
%   theta        - 信号入射角 (弧度，相对阵列法线，默认 0)
%   time_varying - 时变参数（同gen_doppler_channel，可选）
% 输出：
%   R_array      - MxN_rx 多通道接收信号（每行一个阵元）
%   channel_info - 信道信息（含各阵元时延）
%       .tau_array     : 各阵元空间时延 (1xM 秒)
%       .alpha_true    : 时变α序列
%       .单通道信息同gen_doppler_channel

%% ========== 入参 ========== %%
if nargin < 8 || isempty(time_varying)
    time_varying = struct('enable', false);
end
if nargin < 7 || isempty(theta), theta = 0; end

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '10_DopplerProc', 'src', 'Matlab'));

M = array_config.M;
c = array_config.c;

%% ========== 计算各阵元空间时延 ========== %%
% 入射方向单位向量（假设远场平面波）
look_dir = [sin(theta), cos(theta), 0];
tau_array = zeros(1, M);
for m = 1:M
    tau_array(m) = -array_config.positions(m, :) * look_dir.' / c;
end
% 归一化：第一阵元时延为0
tau_array = tau_array - tau_array(1);

%% ========== 逐阵元生成接收信号 ========== %%
% 先用第一阵元的信号确定输出长度
paths_m1 = paths;
[r1, ch_info] = gen_doppler_channel(s, fs, alpha_base, paths_m1, snr_db, time_varying);
N_rx = length(r1);

R_array = zeros(M, N_rx);
R_array(1, :) = r1;

for m = 2:M
    % 将空间时延叠加到多径时延上
    paths_m = paths;
    paths_m.delays = paths.delays + tau_array(m);
    paths_m.delays = max(paths_m.delays, 0);  % 确保非负

    [r_m, ~] = gen_doppler_channel(s, fs, alpha_base, paths_m, snr_db, time_varying);

    % 对齐长度
    len = min(N_rx, length(r_m));
    R_array(m, 1:len) = r_m(1:len);
end

%% ========== 输出 ========== %%
channel_info = ch_info;
channel_info.tau_array = tau_array;
channel_info.array_config = array_config;
channel_info.theta = theta;

end
