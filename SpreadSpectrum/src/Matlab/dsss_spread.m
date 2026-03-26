function spread_signal = dsss_spread(symbols, code)
% 功能：DSSS直接序列扩频——每个符号乘以扩频码
% 版本：V1.0.0
% 输入：
%   symbols - 调制后符号序列 (1xN，实数或复数，通常为±1)
%   code    - 扩频码 (1xL 数组，值为 +1/-1 或 0/1)
%             若为0/1则自动转为±1（0→-1, 1→+1）
% 输出：
%   spread_signal - 扩频后的码片序列 (1x(N*L) 数组)
%
% 备注：
%   - 扩频增益 = L（码长），即 10*log10(L) dB
%   - 输出带宽扩展L倍，每个符号展开为L个码片

%% ========== 1. 入参解析 ========== %%
symbols = symbols(:).';
code = code(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(symbols), error('符号序列不能为空！'); end
if isempty(code), error('扩频码不能为空！'); end

% 0/1码转为±1
if all(code == 0 | code == 1)
    code = 2 * code - 1;
end

%% ========== 3. 扩频 ========== %%
L = length(code);
N = length(symbols);
spread_signal = zeros(1, N * L);

for n = 1:N
    spread_signal((n-1)*L+1 : n*L) = symbols(n) * code;
end

end
