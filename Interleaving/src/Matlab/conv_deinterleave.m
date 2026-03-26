function deinterleaved = conv_deinterleave(data, num_branches, branch_delay)
% 功能：卷积解交织器——卷积交织的逆操作，延迟互补
% 版本：V1.0.0
% 输入：
%   data          - 待解交织的数据序列 (1xN 数值数组)
%   num_branches  - 支路数 (正整数，须与交织时一致)
%   branch_delay  - 支路延迟增量 (正整数，须与交织时一致)
% 输出：
%   deinterleaved - 解交织后的数据序列 (1xN 数组)
%
% 备注：
%   - 解交织器的第i支路延迟为 (B-i)*M，与交织器互补
%   - 交织器第i支路延迟 (i-1)*M + 解交织器第i支路延迟 (B-i)*M = (B-1)*M = 常数
%   - 交织+解交织引入固定总延迟 (B-1)*M，输出序列前(B-1)*M个值为零过渡

%% ========== 1. 入参解析与初始化 ========== %%
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

%% ========== 3. 初始化互补延迟移位寄存器 ========== %%
% 解交织器第i支路（i=0,...,B-1）延迟为 (B-1-i)*M
registers = cell(B, 1);
for i = 1:B
    delay = (B - i) * M;
    registers{i} = zeros(1, delay);
end

%% ========== 4. 卷积解交织 ========== %%
deinterleaved = zeros(1, N);
branch_idx = 0;

for t = 1:N
    b = branch_idx + 1;
    delay = (B - 1 - branch_idx) * M;

    if delay == 0
        deinterleaved(t) = data(t);
    else
        deinterleaved(t) = registers{b}(end);
        registers{b} = [data(t), registers{b}(1:end-1)];
    end

    branch_idx = mod(branch_idx + 1, B);
end

end
