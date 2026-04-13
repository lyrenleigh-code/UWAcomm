function [data_symbols, training_rx, sync_info] = frame_parse_sctde(received, info)
% 功能：SC-TDE帧解析——同步检测 + 提取训练序列和数据
% 版本：V1.0.0
% 输入：
%   received - 接收信号 (1xM 数组，可能含同步偏移和噪声)
%   info     - 帧信息结构体（由 frame_assemble_sctde 生成）
% 输出：
%   data_symbols - 提取的数据符号 (1xN 数组)
%   training_rx  - 提取的训练序列 (1xL 数组)
%   sync_info    - 同步信息结构体
%       .sync_pos      : 检测到的帧起始位置
%       .sync_peak     : 同步相关峰值
%       .training_start: 训练序列起始位置
%       .data_start    : 数据起始位置

%% ========== 1. 同步检测 ========== %%
[sync_pos, sync_peak, ~] = sync_detect(received, info.preamble, 0.3);

if sync_pos == 0
    warning('帧同步失败！返回空数据');
    data_symbols = [];
    training_rx = [];
    sync_info = struct('sync_pos', 0, 'sync_peak', 0);
    return;
end

%% ========== 2. 计算各段位置 ========== %%
p = info.params;
training_start = sync_pos + length(info.preamble) + p.guard_len;
data_start = training_start + p.training_len;
data_end = data_start + info.data_len - 1;

%% ========== 3. 提取各段 ========== %%
if data_end > length(received)
    warning('接收信号长度不足，截断数据段！');
    data_end = length(received);
end

training_end = min(training_start + p.training_len - 1, length(received));
training_rx = received(training_start : training_end);
data_symbols = received(data_start : data_end);

%% ========== 4. 同步信息 ========== %%
sync_info.sync_pos = sync_pos;
sync_info.sync_peak = sync_peak;
sync_info.training_start = training_start;
sync_info.data_start = data_start;

end
