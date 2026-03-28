function [seq, poly] = gen_msequence(degree, poly, init_state)
% 功能：生成m序列（最大长度序列），基于线性反馈移位寄存器(LFSR)
% 版本：V1.0.0
% 输入：
%   degree     - 移位寄存器级数 (正整数，序列长度 = 2^degree - 1)
%   poly       - 生成多项式系数 (1x(degree+1) 二进制数组，高位在前，可选)
%                默认使用预置的本原多项式
%   init_state - 寄存器初始状态 (1xdegree 二进制数组，默认全1，不可全0)
% 输出：
%   seq  - m序列 (1x(2^degree-1) 数组，值为 0/1)
%   poly - 实际使用的生成多项式
%
% 备注：
%   - m序列为最大周期伪随机序列，周期 = 2^degree - 1
%   - 自相关性质优良：峰值=L，旁瓣=-1（L为序列长度）
%   - 预置本原多项式覆盖 degree = 2~15

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 3 || isempty(init_state)
    init_state = ones(1, degree);      % 默认全1
end
if nargin < 2 || isempty(poly)
    poly = default_primitive_poly(degree);
end

%% ========== 2. 严格参数校验 ========== %%
if degree < 2 || degree ~= floor(degree)
    error('degree必须为>=2的正整数！');
end
if all(init_state == 0)
    error('初始状态不可全0！');
end
if length(init_state) ~= degree
    error('初始状态长度(%d)必须等于degree(%d)！', length(init_state), degree);
end

%% ========== 3. LFSR生成m序列 ========== %%
L = 2^degree - 1;                      % 序列长度
seq = zeros(1, L);
state = init_state(:).';

% 反馈抽头位置（多项式中非零项，排除最高位和常数项）
taps = find(poly(2:end-1)) + 1;       % 中间项位置（对应state索引）

for n = 1:L
    seq(n) = state(end);               % 输出最后一位

    % 反馈 = state中抽头位置的异或
    feedback = state(end);
    for t = taps
        feedback = xor(feedback, state(degree - t + 1));
    end

    % 移位
    state = [feedback, state(1:end-1)];
end

end

% --------------- 辅助函数：预置本原多项式 --------------- %
function poly = default_primitive_poly(degree)
% DEFAULT_PRIMITIVE_POLY 返回常用本原多项式（高位在前）

poly_table = containers.Map('KeyType', 'int32', 'ValueType', 'any');
poly_table(2)  = [1 1 1];
poly_table(3)  = [1 0 1 1];
poly_table(4)  = [1 0 0 1 1];
poly_table(5)  = [1 0 0 1 0 1];
poly_table(6)  = [1 0 0 0 0 1 1];
poly_table(7)  = [1 0 0 0 1 0 0 1];
poly_table(8)  = [1 0 0 0 1 1 1 0 1];
poly_table(9)  = [1 0 0 0 0 1 0 0 0 1];
poly_table(10) = [1 0 0 0 0 0 0 1 0 0 1];
poly_table(11) = [1 0 0 0 0 0 0 0 0 1 0 1];
poly_table(12) = [1 0 0 0 0 0 1 0 1 0 0 1 1];
poly_table(13) = [1 0 0 0 0 0 0 0 0 1 1 0 1 1];
poly_table(14) = [1 0 0 0 0 0 0 0 0 0 1 0 1 0 1];
poly_table(15) = [1 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1];

if ~poly_table.isKey(int32(degree))
    error('degree=%d无预置本原多项式，请手动指定poly！', degree);
end
poly = poly_table(int32(degree));

end
