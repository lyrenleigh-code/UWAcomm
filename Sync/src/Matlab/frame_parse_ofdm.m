function [data_symbols, sync_info] = frame_parse_ofdm(received, info)
% 功能：OFDM帧解析——同步+CFO估计+数据提取
% 版本：V1.0.0
% 输入：
%   received - 接收信号 (1xM)
%   info     - 帧信息结构体（由 frame_assemble_ofdm 生成）
% 输出：
%   data_symbols - 提取的数据段 (1xN)
%   sync_info    - 同步信息（含CFO估计值）

%% ========== 1. 同步检测 ========== %%
[sync_pos, sync_peak, ~] = sync_detect(received, info.preamble, 0.3);

if sync_pos == 0
    data_symbols = []; sync_info = struct('sync_pos',0);
    return;
end

%% ========== 2. CFO粗估计（Schmidl-Cox） ========== %%
L_preamble = length(info.preamble);
if sync_pos + L_preamble - 1 <= length(received)
    preamble_rx = received(sync_pos : sync_pos + L_preamble - 1);
    [cfo_hz, cfo_norm] = cfo_estimate(preamble_rx, info.preamble, info.params.fs, 'schmidl');
else
    cfo_hz = 0; cfo_norm = 0;
end

%% ========== 3. 提取数据段 ========== %%
p = info.params;
data_start = sync_pos + L_preamble + p.guard_len;
data_end = min(data_start + info.data_len - 1, length(received));
data_symbols = received(data_start : data_end);

%% ========== 4. 同步信息 ========== %%
sync_info.sync_pos = sync_pos;
sync_info.sync_peak = sync_peak;
sync_info.cfo_hz = cfo_hz;
sync_info.cfo_norm = cfo_norm;
sync_info.data_start = data_start;

end
