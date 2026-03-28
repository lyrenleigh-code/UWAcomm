function [bits, corr_matrix] = mary_despread(received, code_set)
% 功能：M-ary解扩——与所有码字相关，选最大相关值解码
% 版本：V1.0.0
% 输入：
%   received - 接收码片序列 (1xN 数组，N须为码长L的整数倍)
%   code_set - 码字集合 (MxL 矩阵，须与发端一致)
% 输出：
%   bits        - 解调后比特序列 (1x(num_symbols*log2(M)))
%   corr_matrix - 各符号与M个码字的相关矩阵 (num_symbols x M)

%% ========== 1. 入参解析 ========== %%
received = received(:).';

if all(code_set(:) == 0 | code_set(:) == 1)
    code_set = 2 * code_set - 1;
end

[M, L] = size(code_set);
bps = log2(M);

%% ========== 2. 参数校验 ========== %%
if isempty(received), error('接收序列不能为空！'); end
if mod(length(received), L) ~= 0
    error('接收序列长度(%d)必须为码长(%d)的整数倍！', length(received), L);
end

%% ========== 3. 相关检测 ========== %%
num_symbols = length(received) / L;
corr_matrix = zeros(num_symbols, M);
bits = zeros(1, num_symbols * bps);

for s = 1:num_symbols
    block = received((s-1)*L+1 : s*L);

    for k = 1:M
        corr_matrix(s, k) = sum(block .* code_set(k, :)) / L;
    end

    [~, best_k] = max(abs(corr_matrix(s, :)));
    sym_idx = best_k - 1;             % 0-based
    bits((s-1)*bps+1 : s*bps) = de2bi(sym_idx, bps, 'left-msb');
end

end
