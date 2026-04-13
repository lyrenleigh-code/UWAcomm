function [frame, info] = frame_assemble_scfde(data_symbols, params)
% 功能：SC-FDE帧组装——前导码 + [分块数据+CP] + 后导码
% 版本：V1.0.0
% 输入：
%   data_symbols - 调制后数据符号序列 (1xN)
%   params       - 帧参数结构体
%       .preamble_type : 前导类型 (默认'lfm')
%       .preamble_len  : 前导码长度 (采样点数，默认 512)
%       .fs            : 采样率 (Hz，默认 48000)
%       .fc/.bw        : 中心频率/带宽 (Hz)
%       .block_size    : 数据分块大小 (符号数，默认 256)
%       .cp_len        : CP长度 (符号数，默认 64)
%       .guard_len     : 保护间隔 (采样点数，默认 128)
%       .training_seed : 训练序列种子 (默认 0)
% 输出：
%   frame - 帧信号 (1xM)
%   info  - 帧信息结构体

%% ========== 1. 入参解析 ========== %%
if nargin < 2, params = struct(); end
if ~isfield(params, 'preamble_type'), params.preamble_type = 'lfm'; end
if ~isfield(params, 'preamble_len'), params.preamble_len = 512; end
if ~isfield(params, 'fs'), params.fs = 48000; end
if ~isfield(params, 'fc'), params.fc = 12000; end
if ~isfield(params, 'bw'), params.bw = 8000; end
if ~isfield(params, 'block_size'), params.block_size = 256; end
if ~isfield(params, 'cp_len'), params.cp_len = 64; end
if ~isfield(params, 'guard_len'), params.guard_len = 128; end
if ~isfield(params, 'training_seed'), params.training_seed = 0; end

data_symbols = data_symbols(:).';
N = length(data_symbols);
B = params.block_size;
cp = params.cp_len;

%% ========== 2. 生成前导码和后导码 ========== %%
preamble_duration = params.preamble_len / params.fs;
switch params.preamble_type
    case 'lfm'
        [preamble, ~] = gen_lfm(params.fs, preamble_duration, ...
                        params.fc - params.bw/2, params.fc + params.bw/2);
    case 'hfm'
        [preamble, ~] = gen_hfm(params.fs, preamble_duration, ...
                        params.fc - params.bw/2, params.fc + params.bw/2);
    case 'zc'
        [preamble, ~] = gen_zc_seq(params.preamble_len, 1);
    case 'barker'
        [barker_base, ~] = gen_barker(13);
        preamble = repelem(barker_base, ceil(params.preamble_len/13));
        preamble = preamble(1:params.preamble_len);
end
postamble = preamble;                  % 后导码与前导码相同（用于测速）

%% ========== 3. 数据分块 + CP插入（注：CP将在模块6处理，此处记录结构） ========== %%
% 补零对齐到整数块
num_blocks = ceil(N / B);
pad_len = num_blocks * B - N;
data_padded = [data_symbols, zeros(1, pad_len)];

% 分块（CP在模块6 MultiCarrier中插入，此处只分块）
blocks = reshape(data_padded, B, num_blocks).';  % num_blocks x B

%% ========== 4. 组装帧 ========== %%
guard = zeros(1, params.guard_len);
data_section = data_padded;            % 数据段（CP由模块6处理）

frame = [preamble, guard, data_section, guard, postamble];

%% ========== 5. 帧信息 ========== %%
info.preamble = preamble;
info.postamble = postamble;
info.num_blocks = num_blocks;
info.block_size = B;
info.cp_len = cp;
info.pad_len = pad_len;
info.data_start = length(preamble) + params.guard_len + 1;
info.data_len = N;
info.total_len = length(frame);
info.params = params;

end
