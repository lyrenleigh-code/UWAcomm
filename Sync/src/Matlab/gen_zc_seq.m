function [seq, N] = gen_zc_seq(N, root)
% 功能：生成Zadoff-Chu (ZC) 序列
% 版本：V1.0.0
% 输入：
%   N    - 序列长度 (正整数，建议为奇素数以获得最佳相关性)
%   root - 根索引 (正整数，1 <= root < N，须与N互素，默认 1)
% 输出：
%   seq - ZC复数序列 (1xN 复数数组，恒模 |seq(n)|=1)
%   N   - 实际序列长度
%
% 备注：
%   - ZC序列：seq(n) = exp(-j*pi*root*n*(n+1)/N), n=0,...,N-1
%   - 理想自相关：周期自相关为冲激（旁瓣为0）
%   - 不同root的ZC序列互相关值恒定且低
%   - 广泛用于LTE/5G的同步信号和OFDM参考信号
%   - 恒模特性：PAPR = 0 dB

%% ========== 1. 入参解析 ========== %%
if nargin < 2 || isempty(root), root = 1; end

%% ========== 2. 参数校验 ========== %%
if N < 1 || N ~= floor(N), error('序列长度N必须为正整数！'); end
if root < 1 || root >= N, error('根索引root必须在[1, N-1]范围内！'); end
if gcd(root, N) ~= 1
    warning('root(%d)与N(%d)不互素，序列相关性可能下降！', root, N);
end

%% ========== 3. 生成ZC序列 ========== %%
n = 0:N-1;
seq = exp(-1j * pi * root * n .* (n + 1) / N);

end
