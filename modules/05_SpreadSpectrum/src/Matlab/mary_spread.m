function spread_signal = mary_spread(bits, code_set)
% 功能：M-ary扩频——每log2(M)个比特选择一个码字发送
% 版本：V1.0.0
% 输入：
%   bits     - 比特序列 (1xN 数组，N须为 log2(M) 的整数倍)
%   code_set - 码字集合 (MxL 矩阵，M个码字各长L，值为 +1/-1 或 0/1)
% 输出：
%   spread_signal - 扩频后码片序列 (1x(num_symbols*L))
%
% 备注：
%   - 传输速率 = log2(M)/L (bit/chip)
%   - 相比DSSS的1/L，M-ary通过码字选择提高速率
%   - 通常使用Walsh-Hadamard码保证码字正交

%% ========== 1. 入参解析 ========== %%
bits = double(bits(:).');

% 0/1码转±1
if all(code_set(:) == 0 | code_set(:) == 1)
    code_set = 2 * code_set - 1;
end

[M, L] = size(code_set);
bps = log2(M);

%% ========== 2. 参数校验 ========== %%
if isempty(bits), error('比特序列不能为空！'); end
if mod(log2(M), 1) ~= 0, error('码字数M必须为2的幂！'); end
if mod(length(bits), bps) ~= 0
    error('比特长度(%d)必须为log2(M)=%d的整数倍！', length(bits), bps);
end

%% ========== 3. 扩频 ========== %%
num_symbols = length(bits) / bps;
spread_signal = zeros(1, num_symbols * L);

for s = 1:num_symbols
    bit_group = bits((s-1)*bps+1 : s*bps);
    sym_idx = bi2de(bit_group, 'left-msb') + 1;  % 1-based索引
    spread_signal((s-1)*L+1 : s*L) = code_set(sym_idx, :);
end

end
