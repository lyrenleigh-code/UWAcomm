function bits = mfsk_demodulate(freq_indices, M, mapping)
% 功能：MFSK符号判决，频率索引→比特序列
% 版本：V1.0.0
% 输入：
%   freq_indices - 频率索引序列 (1xL 数组，取值 0 ~ M-1)
%   M            - 频率数 (2的幂，须与调制端一致)
%   mapping      - 映射方式 ('gray'(默认) 或 'natural')
% 输出：
%   bits - 解调后的比特序列 (1x(L*log2(M)) 数组)
%
% 备注：
%   - 输入为频率索引（整数），非FSK波形信号
%   - 实际系统中频率索引由能量检测器或相关检测器产生
%   - mapping参数须与调制端一致

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 3 || isempty(mapping)
    mapping = 'gray';
end
if nargin < 2 || isempty(M)
    M = 4;
end
freq_indices = double(freq_indices(:).');
bps = log2(M);

%% ========== 2. 严格参数校验 ========== %%
if isempty(freq_indices)
    error('频率索引不能为空！');
end
if any(freq_indices < 0) || any(freq_indices >= M)
    error('频率索引必须在 [0, %d] 范围内！', M-1);
end
if any(freq_indices ~= floor(freq_indices))
    error('频率索引必须为整数！');
end

%% ========== 3. 生成比特映射表 ========== %%
if strcmp(mapping, 'gray')
    gray_codes = bitxor(0:M-1, bitshift(0:M-1, -1));
else
    gray_codes = 0:M-1;
end

% 索引→比特查找表 (索引从0开始)
index_to_bits = zeros(M, bps);
for k = 1:M
    index_to_bits(k, :) = de2bi(gray_codes(k), bps, 'left-msb');
end

%% ========== 4. 解映射 ========== %%
num_symbols = length(freq_indices);
bits = zeros(1, num_symbols * bps);

for s = 1:num_symbols
    idx = freq_indices(s);
    bits((s-1)*bps+1 : s*bps) = index_to_bits(idx+1, :);
end

end
