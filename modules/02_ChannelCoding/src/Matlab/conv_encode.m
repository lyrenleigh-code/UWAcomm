function [coded, trellis] = conv_encode(message, gen_polys, constraint_len)
% 功能：卷积编码器，支持任意码率1/n和约束长度
% 版本：V1.0.0
% 输入：
%   message        - 信息比特序列 (1xN logical/数值数组)
%   gen_polys      - 生成多项式 (1xn 数组，八进制表示)
%                    默认 [171, 133]（标准NASA码，码率1/2，K=7）
%   constraint_len - 约束长度K (正整数，默认 7)
% 输出：
%   coded          - 编码后比特序列 (1x(N+K-1)*n 数组)
%                    包含 K-1 个尾比特使编码器归零
%   trellis        - 网格结构体，供Viterbi译码使用，包含：
%       .numStates    : 状态总数 (2^(K-1))
%       .n            : 每个输入比特对应的输出比特数
%       .K            : 约束长度
%       .nextState    : 状态转移表 (numStates x 2)，列1=输入0，列2=输入1
%       .output       : 输出表 (numStates x 2)，每个元素为n位输出的十进制值
%
% 备注：
%   - 码率 R = 1/n，n由gen_polys长度决定
%   - 编码器末尾追加 K-1 个零比特（尾比特截断），使状态归零
%   - 生成多项式八进制示例：[7,5](K=3,R=1/2), [171,133](K=7,R=1/2)

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 3 || isempty(constraint_len)
    constraint_len = 7;
end
if nargin < 2 || isempty(gen_polys)
    gen_polys = [171, 133];            % 标准(2,1,7)卷积码
end
message = double(message(:).');

K = constraint_len;                    % 约束长度
n = length(gen_polys);                 % 输出比特数/输入比特
num_states = 2^(K-1);                 % 编码器状态数
mem_len = K - 1;                       % 移位寄存器长度

%% ========== 2. 严格参数校验 ========== %%
if isempty(message)
    error('输入信息比特不能为空！');
end
if any(message ~= 0 & message ~= 1)
    error('输入信息必须为二进制比特(0或1)！');
end
if K < 2 || K ~= floor(K)
    error('约束长度K必须为>=2的正整数！');
end
if any(gen_polys <= 0)
    error('生成多项式必须为正整数（八进制表示）！');
end

%% ========== 3. 将生成多项式转为二进制 ========== %%
gen_bins = zeros(n, K);                % n个多项式，每个K位
for i = 1:n
    oct_str = num2str(gen_polys(i));
    bin_vec = [];
    for j = 1:length(oct_str)
        digit = str2double(oct_str(j));
        bin_vec = [bin_vec, de2bi(digit, 3, 'left-msb')]; %#ok<AGROW>
    end
    % 取最后K位（高位可能有多余的前导零）
    if length(bin_vec) >= K
        gen_bins(i, :) = bin_vec(end-K+1:end);
    else
        gen_bins(i, K-length(bin_vec)+1:end) = bin_vec;
    end
end

%% ========== 4. 构建网格(Trellis)结构 ========== %%
next_state = zeros(num_states, 2);     % 列1:输入0, 列2:输入1
output_table = zeros(num_states, 2);   % 对应输出（n位打包为十进制）

for state = 0:num_states-1
    state_bits = de2bi(state, mem_len, 'left-msb');  % 当前寄存器状态

    for input_bit = 0:1
        % 寄存器内容：[input_bit, state_bits]
        reg = [input_bit, state_bits];

        % 计算各输出比特
        out_bits = zeros(1, n);
        for i = 1:n
            out_bits(i) = mod(sum(reg .* gen_bins(i, :)), 2);
        end

        % 下一状态 = 寄存器右移（丢弃最后一位，输入在最前）
        next_st_bits = reg(1:mem_len);
        next_st = bi2de(next_st_bits, 'left-msb');

        next_state(state+1, input_bit+1) = next_st;
        output_table(state+1, input_bit+1) = bi2de(out_bits, 'left-msb');
    end
end

trellis.numStates = num_states;
trellis.n = n;
trellis.K = K;
trellis.nextState = next_state;
trellis.output = output_table;

%% ========== 5. 卷积编码 ========== %%
% 追加尾比特使编码器归零
msg_with_tail = [message, zeros(1, mem_len)];
total_len = length(msg_with_tail);

coded = zeros(1, total_len * n);
state = 0;                            % 初始状态为全零

for t = 1:total_len
    input_bit = msg_with_tail(t);
    out_val = output_table(state+1, input_bit+1);
    out_bits = de2bi(out_val, n, 'left-msb');

    coded((t-1)*n+1 : t*n) = out_bits;
    state = next_state(state+1, input_bit+1);
end

end
