function [output, scale_factor] = ad_convert(signal, num_bits, mode, full_scale)
% 功能：AD转换仿真——将模拟信号量化为数字信号（模拟ADC）
% 版本：V1.0.0
% 输入：
%   signal     - 输入模拟信号 (1xN 实数数组)
%   num_bits   - ADC量化比特数 (正整数，默认 16)
%   mode       - 转换模式 (字符串，默认 'quantize')
%                'quantize' : 均匀量化
%                'ideal'    : 理想ADC（直通）
%   full_scale - ADC满量程范围 (正实数，默认自动适配信号峰值)
%                信号超出 [-full_scale, +full_scale] 时截断
% 输出：
%   output       - 量化后的数字信号 (1xN 实数数组)
%   scale_factor - 满量程值（供后续处理参考）
%
% 备注：
%   - full_scale 应略大于信号峰值，留 1~3 dB 余量防止截断失真
%   - 有效位数 ENOB ≈ num_bits - 1（考虑符号位）
%   - 量化信噪比 SQNR ≈ 6.02*num_bits + 1.76 dB（满量程正弦输入）

%% ========== 1. 入参解析 ========== %%
if nargin < 4 || isempty(full_scale)
    full_scale = max(abs(signal)) * 1.1;  % 自动+10%余量
end
if nargin < 3 || isempty(mode), mode = 'quantize'; end
if nargin < 2 || isempty(num_bits), num_bits = 16; end
signal = signal(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(signal), error('输入信号不能为空！'); end
if num_bits < 1 || num_bits ~= floor(num_bits), error('量化比特数必须为正整数！'); end
if full_scale <= 0, error('满量程范围必须为正数！'); end

%% ========== 3. AD转换 ========== %%
scale_factor = full_scale;

if strcmp(mode, 'ideal')
    output = signal;
    return;
end

% 截断超出满量程的信号
clipped = max(min(signal, full_scale), -full_scale);
num_clipped = sum(abs(signal) > full_scale);
if num_clipped > 0
    warning('%d个采样点超出ADC满量程(±%.2f)，已截断！', num_clipped, full_scale);
end

% 均匀量化
L = 2^num_bits;
delta = 2 * full_scale / L;
normalized = clipped / full_scale;     % 归一化到[-1,1]
quantized = round(normalized / (2/L)) * (2/L);
quantized = max(min(quantized, 1 - 1/L), -1 + 1/L);

output = quantized * full_scale;

end
