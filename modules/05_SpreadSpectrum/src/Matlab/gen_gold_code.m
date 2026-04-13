function [code, seq1, seq2] = gen_gold_code(degree, shift, poly1, poly2)
% 功能：生成Gold码（两条m序列异或）
% 版本：V1.0.0
% 输入：
%   degree - m序列级数 (正整数)
%   shift  - 第二条m序列的循环移位量 (0 ~ 2^degree-2，默认 0)
%   poly1  - 第一条m序列生成多项式 (可选，默认使用预置优选对)
%   poly2  - 第二条m序列生成多项式 (可选)
% 输出：
%   code - Gold码 (1x(2^degree-1) 数组，值为 0/1)
%   seq1 - 第一条m序列
%   seq2 - 第二条m序列（移位后）
%
% 备注：
%   - Gold码族共有 2^degree+1 个码字，由不同shift值产生
%   - 互相关值限定在 {-1, -t(n), t(n)-2}，t(n) = 2^((n+1)/2)+1 (奇数n)
%   - 预置优选对覆盖 degree = 5/6/7/9/10/11

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 4 || isempty(poly2)
    [poly1, poly2] = default_preferred_pair(degree);
elseif nargin < 3 || isempty(poly1)
    [poly1, poly2] = default_preferred_pair(degree);
end
if nargin < 2 || isempty(shift)
    shift = 0;
end

%% ========== 2. 严格参数校验 ========== %%
L = 2^degree - 1;
if shift < 0 || shift >= L
    error('shift必须在 [0, %d] 范围内！', L-1);
end

%% ========== 3. 生成两条m序列 ========== %%
seq1 = gen_msequence(degree, poly1);
seq2_raw = gen_msequence(degree, poly2);

% 循环移位第二条序列
seq2 = circshift(seq2_raw, [0, -shift]);

%% ========== 4. 异或生成Gold码 ========== %%
code = xor(seq1, seq2);

end

% --------------- 辅助函数：预置优选对 --------------- %
function [poly1, poly2] = default_preferred_pair(degree)
% DEFAULT_PREFERRED_PAIR 返回Gold码优选m序列对

pairs = containers.Map('KeyType', 'int32', 'ValueType', 'any');
pairs(5)  = {[1 0 0 1 0 1], [1 0 1 1 1 1]};
pairs(6)  = {[1 0 0 0 0 1 1], [1 1 0 0 1 1 1]};
pairs(7)  = {[1 0 0 0 1 0 0 1], [1 0 1 1 1 0 0 1]};
pairs(9)  = {[1 0 0 0 0 1 0 0 0 1], [1 0 0 0 1 0 1 0 0 1]};
pairs(10) = {[1 0 0 0 0 0 0 1 0 0 1], [1 0 0 1 0 0 0 0 1 0 1]};
pairs(11) = {[1 0 0 0 0 0 0 0 0 1 0 1], [1 0 1 0 0 0 0 0 0 0 0 1]};

if ~pairs.isKey(int32(degree))
    error('degree=%d无预置优选对，请手动指定poly1和poly2！', degree);
end
p = pairs(int32(degree));
poly1 = p{1};
poly2 = p{2};

end
