function [data_symbols, sync_info] = frame_parse_otfs(received, info)
% 功能：OTFS帧解析——同步检测 + 数据段提取
% 版本：V1.0.0
% 输入：
%   received - 接收信号 (1xM)
%   info     - 帧信息结构体（由 frame_assemble_otfs 生成）
% 输出：
%   data_symbols - 提取的数据段 (1xN)
%   sync_info    - 同步信息

%% ========== 1. 同步检测 ========== %%
[sync_pos, sync_peak, ~] = sync_detect(received, info.preamble, 0.3);

if sync_pos == 0
    data_symbols = []; sync_info = struct('sync_pos',0);
    return;
end

%% ========== 2. 提取数据段 ========== %%
p = info.params;
data_start = sync_pos + length(info.preamble) + p.guard_len;
data_end = min(data_start + info.data_len - 1, length(received));
data_symbols = received(data_start : data_end);

%% ========== 3. 同步信息 ========== %%
sync_info.sync_pos = sync_pos;
sync_info.sync_peak = sync_peak;
sync_info.data_start = data_start;

end
