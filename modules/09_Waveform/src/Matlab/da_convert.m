function [output, scale_factor] = da_convert(signal, num_bits, mode)
% 功能：DA转换仿真——将浮点信号量化为有限精度（模拟DAC）
% 版本：V1.0.0
% 输入：
%   signal   - 输入信号 (1xN 实数数组)
%   num_bits - DAC量化比特数 (正整数，默认 16)
%   mode     - 转换模式 (字符串，默认 'quantize')
%              'quantize' : 均匀量化到 2^num_bits 级
%              'ideal'    : 理想DAC（直通，不做量化）
% 输出：
%   output       - 量化后的信号 (1xN 实数数组)
%   scale_factor - 归一化缩放因子（用于AD还原）
%
% 备注：
%   - 量化范围自动适配信号幅度 [-peak, +peak]
%   - 量化噪声功率 ≈ delta^2/12，SQNR ≈ 6.02*num_bits + 1.76 dB
%   - 复数信号需分别对实部和虚部调用

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(mode), mode = 'quantize'; end
if nargin < 2 || isempty(num_bits), num_bits = 16; end
signal = signal(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(signal), error('输入信号不能为空！'); end
if num_bits < 1 || num_bits ~= floor(num_bits), error('量化比特数必须为正整数！'); end

%% ========== 3. DA转换 ========== %%
if strcmp(mode, 'ideal')
    output = signal;
    scale_factor = 1;
    return;
end

% 归一化到 [-1, +1]
peak = max(abs(signal));
if peak == 0
    output = signal;
    scale_factor = 1;
    return;
end
scale_factor = peak;
normalized = signal / peak;

% 均匀量化
L = 2^num_bits;
delta = 2 / L;                        % 步长（[-1,1]范围）
quantized = round(normalized / delta) * delta;
quantized = max(min(quantized, 1 - delta/2), -1 + delta/2);  % 截断

output = quantized * peak;            % 恢复原始幅度

end
