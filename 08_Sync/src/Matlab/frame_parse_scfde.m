function [data_symbols, sync_info] = frame_parse_scfde(received, info)
% 功能：SC-FDE帧解析——前后导码同步 + 数据段提取
% 版本：V1.0.0
% 输入：
%   received - 接收信号 (1xM)
%   info     - 帧信息结构体（由 frame_assemble_scfde 生成）
% 输出：
%   data_symbols - 提取的数据符号 (1xN，不含补零)
%   sync_info    - 同步信息

%% ========== 1. 前导同步 ========== %%
[sync_pos, sync_peak, ~] = sync_detect(received, info.preamble, 0.3);

if sync_pos == 0
    data_symbols = []; sync_info = struct('sync_pos',0);
    return;
end

%% ========== 2. 提取数据段 ========== %%
p = info.params;
data_start = sync_pos + length(info.preamble) + p.guard_len;
data_end = data_start + info.num_blocks * info.block_size - 1;
data_end = min(data_end, length(received));

data_padded = received(data_start : data_end);

% 去除补零
data_symbols = data_padded(1 : min(info.data_len, length(data_padded)));

%% ========== 3. 同步信息 ========== %%
sync_info.sync_pos = sync_pos;
sync_info.sync_peak = sync_peak;
sync_info.data_start = data_start;

end
