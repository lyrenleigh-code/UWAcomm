function [frame, info] = frame_assemble_sctde(data_symbols, params)
% 功能：SC-TDE帧组装——前导 + 训练序列 + 数据 + 保护间隔
% 版本：V1.0.0
% 输入：
%   data_symbols - 调制后数据符号序列 (1xN 复数/实数)
%   params       - 帧参数结构体
%       .preamble_type : 前导类型 ('lfm'/'hfm'/'zc'/'barker'，默认'lfm')
%       .preamble_len  : 前导码长度 (采样点数，默认 512)
%       .fs            : 采样率 (Hz，默认 48000)
%       .fc            : 中心频率 (Hz，默认 12000，LFM/HFM用)
%       .bw            : 带宽 (Hz，默认 8000，LFM/HFM用)
%       .training_len  : 训练序列长度 (符号数，默认 64)
%       .guard_len     : 保护间隔长度 (采样点数，默认 128)
%       .training_seed : 训练序列随机种子 (默认 0)
% 输出：
%   frame - 组装后的完整帧 (1xM 数组)
%   info  - 帧信息结构体（供帧解析使用）
%       .preamble       : 前导码波形
%       .training       : 训练序列
%       .data_start     : 数据段起始索引
%       .data_len       : 数据符号数
%       .total_len      : 帧总长度
%       .params         : 原始参数

%% ========== 1. 入参解析与默认值 ========== %%
if nargin < 2, params = struct(); end
if ~isfield(params, 'preamble_type'), params.preamble_type = 'lfm'; end
if ~isfield(params, 'preamble_len'), params.preamble_len = 512; end
if ~isfield(params, 'fs'), params.fs = 48000; end
if ~isfield(params, 'fc'), params.fc = 12000; end
if ~isfield(params, 'bw'), params.bw = 8000; end
if ~isfield(params, 'training_len'), params.training_len = 64; end
if ~isfield(params, 'guard_len'), params.guard_len = 128; end
if ~isfield(params, 'training_seed'), params.training_seed = 0; end

data_symbols = data_symbols(:).';

%% ========== 2. 生成前导码 ========== %%
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
        % 过采样到目标长度
        reps = ceil(params.preamble_len / 13);
        preamble = repelem(barker_base, reps);
        preamble = preamble(1:params.preamble_len);
    otherwise
        error('不支持的前导类型: %s', params.preamble_type);
end

%% ========== 3. 生成训练序列（已知的BPSK符号） ========== %%
rng_state = rng;
rng(params.training_seed);
training = 2*randi([0 1], 1, params.training_len) - 1;  % ±1 BPSK
rng(rng_state);

%% ========== 4. 组装帧结构 ========== %%
guard = zeros(1, params.guard_len);

frame = [preamble, guard, training, data_symbols, guard];

%% ========== 5. 输出帧信息 ========== %%
info.preamble = preamble;
info.training = training;
info.data_start = length(preamble) + params.guard_len + params.training_len + 1;
info.data_len = length(data_symbols);
info.total_len = length(frame);
info.params = params;

end
