function [freq_indices, M, bit_map] = mfsk_modulate(bits, M, mapping)
% 功能：MFSK符号映射，比特序列→频率索引
% 版本：V1.0.0
% 输入：
%   bits    - 比特序列 (1xN 数组，N须为 log2(M) 的整数倍)
%   M       - 频率数 (2的幂，如 2/4/8/16，默认 4)
%   mapping - 映射方式 ('gray'(默认) 或 'natural')
% 输出：
%   freq_indices - 频率索引序列 (1x(N/log2(M)) 数组，取值 0 ~ M-1)
%   M            - 实际使用的频率数
%   bit_map      - 比特到索引映射表 (Mx(log2(M)) 矩阵)
%
% 备注：
%   - 仅完成比特→频率索引映射，FSK波形生成在上变频模块实现
%   - Gray映射保证相邻频率索引仅差1比特
%   - 频率索引从0开始，对应M个频率 f0, f1, ..., f_{M-1}

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 3 || isempty(mapping)
    mapping = 'gray';
end
if nargin < 2 || isempty(M)
    M = 4;
end
bits = double(bits(:).');
bps = log2(M);

%% ========== 2. 严格参数校验 ========== %%
if isempty(bits)
    error('输入比特不能为空！');
end
if M < 2 || mod(log2(M), 1) ~= 0
    error('M必须为2的幂(2/4/8/16/...)！');
end
if any(bits ~= 0 & bits ~= 1)
    error('输入必须为二进制比特(0或1)！');
end
if mod(length(bits), bps) ~= 0
    error('比特长度(%d)必须为 log2(M)=%d 的整数倍！', length(bits), bps);
end

%% ========== 3. 生成比特映射表 ========== %%
if strcmp(mapping, 'gray')
    gray_codes = bitxor(0:M-1, bitshift(0:M-1, -1));
else
    gray_codes = 0:M-1;
end

bit_map = zeros(M, bps);
for k = 1:M
    bit_map(k, :) = de2bi(gray_codes(k), bps, 'left-msb');
end

% 构建比特模式→索引查找表
lookup = containers.Map();
for k = 1:M
    key = num2str(bit_map(k, :));
    lookup(key) = k - 1;               % 频率索引从0开始
end

%% ========== 4. 映射 ========== %%
num_symbols = length(bits) / bps;
freq_indices = zeros(1, num_symbols);

for s = 1:num_symbols
    bit_group = bits((s-1)*bps+1 : s*bps);
    key = num2str(bit_group);
    freq_indices(s) = lookup(key);
end

end
