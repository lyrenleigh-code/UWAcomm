function [bits, corr_matrix] = csk_despread(received, base_code, M)
% 功能：CSK循环移位键控解扩——相关检测确定移位量，恢复比特
% 版本：V1.0.0
% 输入：
%   received  - 接收码片序列 (1xN 数组，N须为码长L的整数倍)
%   base_code - 基础扩频码 (1xL，须与发端一致)
%   M         - 调制阶数 (须与发端一致，默认 2)
% 输出：
%   bits        - 解调后比特序列 (1x(num_symbols*log2(M)))
%   corr_matrix - 各符号与M个移位码的相关矩阵 (num_symbols x M)
%
% 备注：
%   - 对每个接收码片块，与M个候选移位码做相关
%   - 选择相关峰最大的移位量→解码为符号→转比特

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(M)
    M = 2;
end
received = received(:).';
base_code = base_code(:).';
bps = log2(M);
L = length(base_code);

if all(base_code == 0 | base_code == 1)
    base_code = 2 * base_code - 1;
end

%% ========== 2. 参数校验 ========== %%
if isempty(received), error('接收序列不能为空！'); end
if mod(length(received), L) ~= 0
    error('接收序列长度(%d)必须为码长(%d)的整数倍！', length(received), L);
end

%% ========== 3. 生成M个候选移位码 ========== %%
shift_step = floor(L / M);
candidates = zeros(M, L);
for k = 1:M
    candidates(k, :) = circshift(base_code, [0, -(k-1)*shift_step]);
end

%% ========== 4. 相关检测 ========== %%
num_symbols = length(received) / L;
corr_matrix = zeros(num_symbols, M);
bits = zeros(1, num_symbols * bps);

for s = 1:num_symbols
    block = received((s-1)*L+1 : s*L);

    for k = 1:M
        corr_matrix(s, k) = abs(sum(block .* candidates(k, :)));
    end

    [~, best_k] = max(corr_matrix(s, :));
    sym_idx = best_k - 1;             % 0-based符号索引
    bits((s-1)*bps+1 : s*bps) = de2bi(sym_idx, bps, 'left-msb');
end

end
