function [coded, params] = turbo_encode(message, num_iter_hint, interleaver_seed)
% 功能：Turbo编码器（并行级联卷积码，码率1/3）
% 版本：V1.0.0
% 输入：
%   message          - 信息比特序列 (1xN logical/数值数组)
%   num_iter_hint    - 建议译码迭代次数 (正整数，默认6，仅记录到params供译码参考)
%   interleaver_seed - 交织器随机种子 (正整数，默认0，编解码须一致)
% 输出：
%   coded            - 编码后比特序列 (1x3N 数组)
%                      排列顺序：[系统位, 校验位1, 校验位2]，各N个比特
%   params           - 编码参数结构体（供 turbo_decode 使用）
%       .msg_len          : 信息比特长度 N
%       .interleaver      : 交织索引 (1xN)
%       .deinterleaver    : 解交织索引 (1xN)
%       .num_iter         : 建议迭代次数
%       .fb_poly          : 反馈多项式（八进制）
%       .ff_poly          : 前馈多项式（八进制）
%       .constraint_len   : RSC编码器约束长度
%
% 备注：
%   - 组成编码器：RSC (Recursive Systematic Convolutional)
%   - 默认分量码：K=4, 反馈多项式=15(八进制), 前馈多项式=13(八进制)
%   - 即 g0 = 1+D+D^2+D^3 (反馈), g1 = 1+D^2+D^3 (前馈)
%   - 编码器1直接编码，编码器2对交织后的信息编码
%   - 不含尾比特截断（简化实现，可后续扩展）

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 3 || isempty(interleaver_seed)
    interleaver_seed = 0;
end
if nargin < 2 || isempty(num_iter_hint)
    num_iter_hint = 6;
end
message = double(message(:).');

N = length(message);                   % 信息比特长度
fb_poly = 15;                          % 反馈多项式（八进制）= 1101 (二进制)
ff_poly = 13;                          % 前馈多项式（八进制）= 1011 (二进制)
K = 4;                                 % RSC约束长度
mem_len = K - 1;                       % 寄存器长度

%% ========== 2. 严格参数校验 ========== %%
if isempty(message)
    error('输入信息比特不能为空！');
end
if any(message ~= 0 & message ~= 1)
    error('输入信息必须为二进制比特(0或1)！');
end
if N < 2
    error('信息比特长度至少为2！');
end

%% ========== 3. 生成交织器（调用交织模块） ========== %%
[interleaved_msg, interleaver] = random_interleave(message, interleaver_seed);

deinterleaver = zeros(1, N);
deinterleaver(interleaver) = 1:N;      % 逆映射

%% ========== 4. RSC编码器1 — 编码原始信息 ========== %%
parity1 = rsc_encode_local(message, fb_poly, ff_poly, K);

%% ========== 5. RSC编码器2 — 编码交织后信息 ========== %%
parity2 = rsc_encode_local(interleaved_msg, fb_poly, ff_poly, K);

%% ========== 6. 组装输出 ========== %%
% 码率1/3：系统位 + 校验位1 + 校验位2
coded = [message, parity1, parity2];

% 保存参数供译码使用
params.msg_len        = N;
params.interleaver    = interleaver;
params.deinterleaver  = deinterleaver;
params.num_iter       = num_iter_hint;
params.fb_poly        = fb_poly;
params.ff_poly        = ff_poly;
params.constraint_len = K;

end

% --------------- 辅助函数1：RSC（递归系统卷积）编码器 --------------- %
function parity = rsc_encode_local(data, fb_poly, ff_poly, K)
% RSC_ENCODE_LOCAL 递归系统卷积编码，输出校验比特流
% 输入参数：
%   data    - 信息比特 (1xN)
%   fb_poly - 反馈多项式（八进制）
%   ff_poly - 前馈多项式（八进制）
%   K       - 约束长度
% 输出参数：
%   parity  - 校验比特 (1xN)

mem_len = K - 1;
N = length(data);

% 八进制转二进制
fb_bin = oct2bin_local(fb_poly, K);    % 反馈多项式二进制
ff_bin = oct2bin_local(ff_poly, K);    % 前馈多项式二进制

% 编码
state = zeros(1, mem_len);            % 寄存器初始状态为全零
parity = zeros(1, N);

for t = 1:N
    % 反馈位 = 输入 XOR (状态与反馈多项式的内积)
    fb_bit = mod(data(t) + sum(state .* fb_bin(2:end)), 2);

    % 校验位 = fb_bit与前馈多项式的卷积
    reg_with_input = [fb_bit, state];
    parity(t) = mod(sum(reg_with_input .* ff_bin), 2);

    % 状态更新：右移，新位从左端进入
    state = [fb_bit, state(1:end-1)];
end

end

% --------------- 辅助函数2：八进制转二进制向量 --------------- %
function bin_vec = oct2bin_local(oct_val, K)
% OCT2BIN_LOCAL 将八进制数转为K位二进制行向量
% 输入参数：
%   oct_val - 八进制数（以十进制整数形式传入，如 15 表示八进制15）
%   K       - 输出二进制位数
% 输出参数：
%   bin_vec - 1xK 二进制行向量

oct_str = num2str(oct_val);
bin_vec = [];
for j = 1:length(oct_str)
    digit = str2double(oct_str(j));
    bin_vec = [bin_vec, de2bi(digit, 3, 'left-msb')]; %#ok<AGROW>
end

if length(bin_vec) >= K
    bin_vec = bin_vec(end-K+1:end);
else
    bin_vec = [zeros(1, K-length(bin_vec)), bin_vec];
end

end
