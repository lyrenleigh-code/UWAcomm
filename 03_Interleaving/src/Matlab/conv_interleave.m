function [interleaved, num_branches, branch_delay] = conv_interleave(data, num_branches, branch_delay)
% 功能：卷积交织器——基于延迟递增的移位寄存器组，适合流式处理
% 版本：V1.0.0
% 输入：
%   data          - 待交织的数据序列 (1xN 数值数组)
%   num_branches  - 支路数 (正整数，默认 6)
%   branch_delay  - 支路延迟增量 (正整数，默认 12)
%                   第i支路延迟为 (i-1)*branch_delay 个符号，i=1,...,num_branches
% 输出：
%   interleaved   - 交织后的数据序列 (1xN 数组)
%   num_branches  - 实际使用的支路数（供解交织使用）
%   branch_delay  - 实际使用的延迟增量（供解交织使用）
%
% 备注：
%   - 输入符号按轮转分配到各支路，经不同延迟后输出
%   - 第1支路延迟为0（直通），第B支路延迟为(B-1)*M
%   - 总交织深度 = (num_branches-1) * branch_delay
%   - 初始状态寄存器填充为0，前端输出包含零值过渡

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 3 || isempty(branch_delay)
    branch_delay = 12;
end
if nargin < 2 || isempty(num_branches)
    num_branches = 6;
end
data = data(:).';
N = length(data);
B = num_branches;
M = branch_delay;

%% ========== 2. 严格参数校验 ========== %%
if isempty(data)
    error('输入数据不能为空！');
end
if B < 2 || B ~= floor(B)
    error('支路数num_branches必须为>=2的正整数！');
end
if M < 1 || M ~= floor(M)
    error('支路延迟增量branch_delay必须为正整数！');
end

%% ========== 3. 初始化移位寄存器 ========== %%
% 第i支路（i=0,...,B-1）的延迟为 i*M 个符号
registers = cell(B, 1);
for i = 1:B
    delay = (i-1) * M;
    registers{i} = zeros(1, delay);    % FIFO缓冲区，初始填0
end

%% ========== 4. 卷积交织 ========== %%
interleaved = zeros(1, N);
branch_idx = 0;                        % 当前支路（0-based，轮转）

for t = 1:N
    b = branch_idx + 1;               % 转为1-based索引
    delay = (branch_idx) * M;

    if delay == 0
        % 第1支路：直通
        interleaved(t) = data(t);
    else
        % 从FIFO尾部读出，头部写入
        interleaved(t) = registers{b}(end);
        registers{b} = [data(t), registers{b}(1:end-1)];
    end

    % 轮转到下一支路
    branch_idx = mod(branch_idx + 1, B);
end

end
