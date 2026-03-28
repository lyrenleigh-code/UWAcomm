function [decoded, min_metric] = viterbi_decode(received, trellis, decision_type)
% 功能：Viterbi译码器，支持硬判决和软判决
% 版本：V1.0.0
% 输入：
%   received      - 接收比特/软值序列
%                   硬判决：1xM 二进制数组 (M = 编码输出总比特数)
%                   软判决：1xM 实数数组 (正值倾向于1，负值倾向于0)
%   trellis       - 网格结构体（由 conv_encode 生成）
%       .numStates    : 状态总数
%       .n            : 每输入比特对应的输出比特数
%       .K            : 约束长度
%       .nextState    : 状态转移表 (numStates x 2)
%       .output       : 输出表 (numStates x 2)
%   decision_type - 判决类型 (字符串，默认 'hard')
%                   'hard' : 汉明距离度量
%                   'soft' : 欧氏距离度量（输入为软值）
% 输出：
%   decoded       - 译码后的信息比特序列 (1xN 数组，N = M/n - K + 1)
%   min_metric    - 最优路径的累计度量值
%
% 备注：
%   - 假设编码器以尾比特归零，最终状态为0
%   - 软判决输入约定：+1对应比特1，-1对应比特0

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 3 || isempty(decision_type)
    decision_type = 'hard';
end
received = double(received(:).');

n = trellis.n;                         % 每时刻输出比特数
K = trellis.K;                         % 约束长度
num_states = trellis.numStates;        % 状态总数
next_state = trellis.nextState;        % 状态转移表
output_table = trellis.output;         % 输出表

%% ========== 2. 严格参数校验 ========== %%
if isempty(received)
    error('接收序列不能为空！');
end
if mod(length(received), n) ~= 0
    error('接收序列长度(%d)必须为n=%d的整数倍！', length(received), n);
end

total_steps = length(received) / n;    % 总时间步数
msg_len = total_steps - (K - 1);       % 原始信息比特长度（去除尾比特）

if msg_len < 1
    error('接收序列过短，无法译码！至少需要 %d 个比特。', n * K);
end

%% ========== 3. 初始化路径度量 ========== %%
INF_METRIC = 1e10;
path_metric = ones(1, num_states) * INF_METRIC;
path_metric(1) = 0;                   % 初始状态为0

% 存储幸存路径（每个状态在每个时刻的前驱状态和输入比特）
survivor_state = zeros(num_states, total_steps);
survivor_input = zeros(num_states, total_steps);

%% ========== 4. 前向递推（加-比-选） ========== %%
for t = 1:total_steps
    rx_block = received((t-1)*n+1 : t*n);  % 当前时刻接收的n个值

    new_metric = ones(1, num_states) * INF_METRIC;
    new_surv_state = zeros(1, num_states);
    new_surv_input = zeros(1, num_states);

    for state = 0:num_states-1
        if path_metric(state+1) >= INF_METRIC
            continue;                  % 不可达状态，跳过
        end

        for input_bit = 0:1
            % 该转移对应的输出
            out_val = output_table(state+1, input_bit+1);
            out_bits = de2bi(out_val, n, 'left-msb');

            % 计算分支度量
            if strcmp(decision_type, 'hard')
                branch_metric = sum(out_bits ~= rx_block);  % 汉明距离
            else
                % 软判决：将比特映射到+1/-1，计算欧氏距离
                expected = 2 * out_bits - 1;       % 0→-1, 1→+1
                branch_metric = sum((rx_block - expected).^2);
            end

            % 累计度量
            total_metric = path_metric(state+1) + branch_metric;

            % 下一状态
            ns = next_state(state+1, input_bit+1);

            % 比较-选择
            if total_metric < new_metric(ns+1)
                new_metric(ns+1) = total_metric;
                new_surv_state(ns+1) = state;
                new_surv_input(ns+1) = input_bit;
            end
        end
    end

    path_metric = new_metric;
    survivor_state(:, t) = new_surv_state.';
    survivor_input(:, t) = new_surv_input.';
end

%% ========== 5. 回溯（从状态0开始） ========== %%
min_metric = path_metric(1);           % 终止状态为0（尾比特归零）
state = 0;

trace_input = zeros(1, total_steps);
for t = total_steps:-1:1
    trace_input(t) = survivor_input(state+1, t);
    state = survivor_state(state+1, t);
end

%% ========== 6. 提取信息比特（去除尾比特） ========== %%
decoded = trace_input(1:msg_len);

end
