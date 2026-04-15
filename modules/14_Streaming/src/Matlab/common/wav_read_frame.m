function [frame_pb, fs] = wav_read_frame(session_subdir, frame_idx, wait_timeout)
% 功能：等待 .ready 就绪后读 NNNN.wav，并反归一化为原始幅度
% 版本：V1.0.0
% 输入：
%   session_subdir - 例如 fullfile(session, 'raw_frames') 或 'channel_frames'
%   frame_idx      - 帧序号 (>=1)
%   wait_timeout   - 等待 .ready 超时 (秒，默认 10)
% 输出：
%   frame_pb - passband 实信号 (1×N double, 已反归一化)
%   fs       - 采样率

if nargin < 3, wait_timeout = 10; end

wav_name   = sprintf('%04d.wav', frame_idx);
ready_name = sprintf('%04d.ready', frame_idx);
scale_name = sprintf('%04d.scale.mat', frame_idx);

wav_path   = fullfile(session_subdir, wav_name);
ready_path = fullfile(session_subdir, ready_name);
scale_path = fullfile(session_subdir, scale_name);

% 等 .ready 出现（每 0.1s 轮询）
t_start = tic;
while ~exist(ready_path, 'file')
    if toc(t_start) > wait_timeout
        error('wav_read_frame: 等待 %s 超时 (%.1fs)', ready_path, wait_timeout);
    end
    pause(0.1);
end

% 读 wav
[frame_pb, fs] = audioread(wav_path);
frame_pb = frame_pb(:).';  % 行向量

% 反归一化（若 .scale.mat 存在）
if exist(scale_path, 'file')
    s = load(scale_path);
    if isfield(s, 'scale_factor') && s.scale_factor ~= 0
        frame_pb = frame_pb / s.scale_factor;
    end
else
    warning('wav_read_frame: 未找到 %s，信号保持归一化状态', scale_path);
end

end
