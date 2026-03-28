function [symbols, corr_values] = dsss_despread(received, code)
% 功能：DSSS直接序列解扩——相关解扩恢复符号
% 版本：V1.0.0
% 输入：
%   received - 接收码片序列 (1xM 数组，M须为码长L的整数倍)
%   code     - 扩频码 (1xL 数组，值为 +1/-1 或 0/1)
% 输出：
%   symbols     - 解扩后的符号序列 (1x(M/L) 数组)
%   corr_values - 各符号的相关值 (1x(M/L) 复数数组，供DCD/DED检测器使用)
%
% 备注：
%   - 标准相关解扩：symbols(n) = (1/L) * sum(received_block .* code)
%   - 解扩增益 = L（码长），提高信噪比

%% ========== 1. 入参解析 ========== %%
received = received(:).';
code = code(:).';

if all(code == 0 | code == 1)
    code = 2 * code - 1;
end

%% ========== 2. 参数校验 ========== %%
if isempty(received), error('接收序列不能为空！'); end
L = length(code);
if mod(length(received), L) ~= 0
    error('接收序列长度(%d)必须为码长(%d)的整数倍！', length(received), L);
end

%% ========== 3. 相关解扩 ========== %%
num_symbols = length(received) / L;
corr_values = zeros(1, num_symbols);

for n = 1:num_symbols
    block = received((n-1)*L+1 : n*L);
    corr_values(n) = sum(block .* code) / L;
end

symbols = corr_values;

end
