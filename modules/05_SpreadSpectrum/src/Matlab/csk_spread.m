function [spread_signal, shift_amounts] = csk_spread(bits, base_code, M)
% 功能：CSK循环移位键控扩频——用码序列的不同循环移位表示不同符号
% 版本：V1.0.0
% 输入：
%   bits      - 比特序列 (1xN 数组，N须为 log2(M) 的整数倍)
%   base_code - 基础扩频码 (1xL 数组，值为 +1/-1 或 0/1)
%   M         - 调制阶数 (2的幂，默认 2，即二进制CSK)
%              M个循环移位量均匀分配：shift_k = k * floor(L/M), k=0,...,M-1
% 输出：
%   spread_signal  - 扩频后码片序列 (1x(num_symbols*L))
%   shift_amounts  - 各符号对应的循环移位量 (1xnum_symbols)
%
% 备注：
%   - CSK将信息映射为扩频码的循环移位，利用m序列的自相关特性
%   - 不同移位的码具有低互相关，实现正交或近似正交

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(M)
    M = 2;
end
bits = double(bits(:).');
base_code = base_code(:).';
bps = log2(M);
L = length(base_code);

if all(base_code == 0 | base_code == 1)
    base_code = 2 * base_code - 1;
end

%% ========== 2. 参数校验 ========== %%
if isempty(bits), error('比特序列不能为空！'); end
if isempty(base_code), error('基础码不能为空！'); end
if mod(length(bits), bps) ~= 0
    error('比特长度(%d)必须为log2(M)=%d的整数倍！', length(bits), bps);
end

%% ========== 3. 生成移位量表 ========== %%
shift_step = floor(L / M);            % 相邻符号的移位间隔
shift_table = (0:M-1) * shift_step;   % M个移位量

%% ========== 4. 扩频 ========== %%
num_symbols = length(bits) / bps;
spread_signal = zeros(1, num_symbols * L);
shift_amounts = zeros(1, num_symbols);

for s = 1:num_symbols
    bit_group = bits((s-1)*bps+1 : s*bps);
    sym_idx = bi2de(bit_group, 'left-msb');  % 比特组→符号索引 (0~M-1)

    shift_val = shift_table(sym_idx + 1);
    shift_amounts(s) = shift_val;

    shifted_code = circshift(base_code, [0, -shift_val]);
    spread_signal((s-1)*L+1 : s*L) = shifted_code;
end

end
