function [frame, info] = frame_assemble_ofdm(data_symbols, params)
% 功能：OFDM帧组装——前导码(双重复结构,供Schmidl-Cox) + 数据符号
% 版本：V1.0.0
% 输入：
%   data_symbols - 频域数据符号 (1xN，待IFFT处理，此处仅组装帧结构)
%   params       - 帧参数结构体
%       .preamble_type : 前导类型 (默认'zc')
%       .preamble_len  : 前导码长度 (默认 256)
%       .fs            : 采样率 (Hz，默认 48000)
%       .guard_len     : 前导后保护间隔 (默认 64)
%       .num_subcarriers: 子载波数 (默认 256，OFDM符号长度)
%       .num_ofdm_symbols: OFDM符号数 (自动计算)
% 输出：
%   frame - 帧信号 (1xM)
%   info  - 帧信息

%% ========== 1. 入参解析 ========== %%
if nargin < 2, params = struct(); end
if ~isfield(params, 'preamble_type'), params.preamble_type = 'zc'; end
if ~isfield(params, 'preamble_len'), params.preamble_len = 256; end
if ~isfield(params, 'fs'), params.fs = 48000; end
if ~isfield(params, 'guard_len'), params.guard_len = 64; end
if ~isfield(params, 'num_subcarriers'), params.num_subcarriers = 256; end

data_symbols = data_symbols(:).';

%% ========== 2. 生成前导码（双重复结构，供Schmidl-Cox CFO估计） ========== %%
half_len = floor(params.preamble_len / 2);
switch params.preamble_type
    case 'zc'
        [half_seq, ~] = gen_zc_seq(half_len, 1);
    case 'lfm'
        [half_seq, ~] = gen_lfm(params.fs, half_len/params.fs, ...
                        8000, 16000);
    otherwise
        [half_seq, ~] = gen_zc_seq(half_len, 1);
end
preamble = [half_seq, half_seq];       % 重复结构 [A, A]

%% ========== 3. 组装帧 ========== %%
guard = zeros(1, params.guard_len);
frame = [preamble, guard, data_symbols];

%% ========== 4. 帧信息 ========== %%
info.preamble = preamble;
info.preamble_half = half_seq;
info.data_start = length(preamble) + params.guard_len + 1;
info.data_len = length(data_symbols);
info.total_len = length(frame);
info.params = params;

end
