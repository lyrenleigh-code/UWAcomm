function [frame, info] = frame_assemble_otfs(data_symbols, params)
% 功能：OTFS帧组装——前导码 + 数据（整帧CP由模块6处理）
% 版本：V1.0.0
% 输入：
%   data_symbols - DD域数据符号 (1xN，待ISFFT+Heisenberg处理)
%   params       - 帧参数结构体
%       .preamble_type : 前导类型 (默认'hfm'，Doppler不变)
%       .preamble_len  : 前导码长度 (采样点数，默认 512)
%       .fs            : 采样率 (Hz，默认 48000)
%       .fc/.bw        : 中心频率/带宽 (Hz)
%       .guard_len     : 保护间隔 (默认 128)
% 输出：
%   frame - 帧信号 (1xM)
%   info  - 帧信息

%% ========== 1. 入参解析 ========== %%
if nargin < 2, params = struct(); end
if ~isfield(params, 'preamble_type'), params.preamble_type = 'hfm'; end
if ~isfield(params, 'preamble_len'), params.preamble_len = 512; end
if ~isfield(params, 'fs'), params.fs = 48000; end
if ~isfield(params, 'fc'), params.fc = 12000; end
if ~isfield(params, 'bw'), params.bw = 8000; end
if ~isfield(params, 'guard_len'), params.guard_len = 128; end

data_symbols = data_symbols(:).';

%% ========== 2. 生成前导码（推荐HFM，Doppler不变） ========== %%
preamble_duration = params.preamble_len / params.fs;
switch params.preamble_type
    case 'hfm'
        [preamble, ~] = gen_hfm(params.fs, preamble_duration, ...
                        params.fc - params.bw/2, params.fc + params.bw/2);
    case 'lfm'
        [preamble, ~] = gen_lfm(params.fs, preamble_duration, ...
                        params.fc - params.bw/2, params.fc + params.bw/2);
    case 'zc'
        [preamble, ~] = gen_zc_seq(params.preamble_len, 1);
    otherwise
        [preamble, ~] = gen_hfm(params.fs, preamble_duration, ...
                        params.fc - params.bw/2, params.fc + params.bw/2);
end

%% ========== 3. 组装帧（整帧CP在模块6 OTFS变换后添加） ========== %%
guard = zeros(1, params.guard_len);
frame = [preamble, guard, data_symbols];

%% ========== 4. 帧信息 ========== %%
info.preamble = preamble;
info.data_start = length(preamble) + params.guard_len + 1;
info.data_len = length(data_symbols);
info.total_len = length(frame);
info.params = params;

end
