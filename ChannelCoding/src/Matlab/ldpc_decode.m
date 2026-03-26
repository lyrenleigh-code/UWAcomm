function [decoded, LLR_out, num_iter_done] = ldpc_decode(received, H, k, snr_db, max_iter)
% 功能：LDPC码置信传播(Belief Propagation, BP)迭代译码
% 版本：V1.0.0
% 输入：
%   received    - 接收软值序列 (1xM 实数数组，M须为n的整数倍)
%                 正值倾向于比特1，负值倾向于比特0（BPSK: +1/-1 + 噪声）
%   H           - 校验矩阵 ((n-k) x n 二进制矩阵，由 ldpc_encode 生成)
%   k           - 信息位长度 (正整数，用于提取系统位)
%   snr_db      - 信噪比 (dB)，用于计算初始LLR
%   max_iter    - 最大迭代次数 (正整数，默认 50)
% 输出：
%   decoded     - 译码后的信息比特序列 (1xN 数组)
%   LLR_out     - 最终全码字LLR (1xn*num_blocks 数组)
%   num_iter_done - 各码块实际迭代次数 (1xnum_blocks 数组)
%
% 备注：
%   - 采用对数域置信传播(Log-BP / Sum-Product)算法
%   - 使用 min-sum 近似简化校验节点更新，降低计算复杂度
%   - 当所有校验方程满足时提前终止迭代
%   - 编码时使用的列顺序须与H一致

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 5 || isempty(max_iter)
    max_iter = 50;
end
received = double(received(:).');

[m, n] = size(H);                     % m=校验方程数, n=码字长度

%% ========== 2. 严格参数校验 ========== %%
if isempty(received)
    error('接收序列不能为空！');
end
if mod(length(received), n) ~= 0
    error('接收序列长度(%d)必须为码长n=%d的整数倍！', length(received), n);
end
if k < 1 || k >= n
    error('信息位长度k=%d无效，须在(0, n=%d)之间！', k, n);
end
if max_iter < 1
    error('最大迭代次数必须为正整数！');
end

%% ========== 3. 预计算H矩阵的稀疏连接关系 ========== %%
% 校验节点c连接的变量节点集合
check_to_var = cell(m, 1);
for c = 1:m
    check_to_var{c} = find(H(c, :));
end

% 变量节点v连接的校验节点集合
var_to_check = cell(n, 1);
for v = 1:n
    var_to_check{v} = find(H(:, v));
end

%% ========== 4. 信道LLR初始化 ========== %%
% BPSK调制下信道LLR: L_ch = 2*y*Lc, 其中 Lc = 2/sigma^2
rate = k / n;
snr_lin = 10^(snr_db / 10);
sigma2 = 1 / (2 * rate * snr_lin);    % 噪声方差
Lc = 2 / sigma2;                       % 信道可靠度

%% ========== 5. 分块译码 ========== %%
num_blocks = length(received) / n;
decoded = zeros(1, num_blocks * k);
LLR_out = zeros(1, num_blocks * n);
num_iter_done = zeros(1, num_blocks);

for b = 1:num_blocks
    idx = (b-1)*n + 1 : b*n;
    rx_block = received(idx);

    % 信道LLR: BP约定 LLR=log(P(0)/P(1))，正值→bit 0
    % 输入约定：正值→bit 1，故取反对齐
    L_ch = -Lc * rx_block;

    % 执行BP译码
    [hard_bits, llr_final, iters] = bp_decode_block(L_ch, H, m, n, ...
                                        check_to_var, var_to_check, max_iter);

    num_iter_done(b) = iters;
    LLR_out(idx) = llr_final;

    % 提取信息位（取前k位，对应系统码）
    idx_out = (b-1)*k + 1 : b*k;
    decoded(idx_out) = hard_bits(1:k);
end

end

% --------------- 辅助函数1：单码块BP译码 --------------- %
function [hard_bits, LLR, num_iter] = bp_decode_block(L_ch, H, m, n, ...
                                        check_to_var, var_to_check, max_iter)
% BP_DECODE_BLOCK 对单个码块执行Min-Sum BP译码
% 输入参数：
%   L_ch         - 信道LLR (1xn)
%   H            - 校验矩阵 (m x n)
%   m, n         - 校验方程数和码字长度
%   check_to_var - 校验节点到变量节点的连接 (mx1 cell)
%   var_to_check - 变量节点到校验节点的连接 (nx1 cell)
%   max_iter     - 最大迭代次数
% 输出参数：
%   hard_bits    - 硬判决结果 (1xn)
%   LLR          - 最终LLR (1xn)
%   num_iter     - 实际迭代次数

% 初始化变量节点到校验节点的消息
% msg_v2c(c, v) 存储变量v发送给校验c的消息
msg_v2c = zeros(m, n);
for v = 1:n
    checks = var_to_check{v};
    msg_v2c(checks, v) = L_ch(v);
end

% 校验节点到变量节点的消息
msg_c2v = zeros(m, n);

alpha = 0.75;                          % Min-Sum缩放因子（提升性能）

for iter = 1:max_iter
    %% 校验节点更新 (Min-Sum近似)
    for c = 1:m
        vars = check_to_var{c};
        num_v = length(vars);

        for j = 1:num_v
            v = vars(j);
            % 排除当前变量节点v，对其余消息计算
            other_idx = vars(vars ~= v);

            % Min-Sum: sign的乘积 * 最小绝对值
            signs = sign(msg_v2c(c, other_idx));
            magnitudes = abs(msg_v2c(c, other_idx));

            total_sign = prod(signs);
            min_mag = min(magnitudes);

            msg_c2v(c, v) = alpha * total_sign * min_mag;
        end
    end

    %% 变量节点更新
    LLR = L_ch;                        % 初始化为信道LLR
    for v = 1:n
        checks = var_to_check{v};

        % 总LLR = 信道LLR + 所有校验节点发来的消息之和
        LLR(v) = L_ch(v) + sum(msg_c2v(checks, v));

        % 更新发给各校验节点的消息（排除该校验节点的贡献）
        for j = 1:length(checks)
            c = checks(j);
            msg_v2c(c, v) = LLR(v) - msg_c2v(c, v);
        end
    end

    %% 硬判决并检查校验方程
    hard_bits = double(LLR < 0);       % LLR<0 → 比特1, LLR>0 → 比特0

    % 注意：BPSK映射中 +1 对应比特0, -1 对应比特1
    % LLR > 0 倾向于比特0, LLR < 0 倾向于比特1
    syndrome = mod(H * hard_bits.', 2);
    if all(syndrome == 0)
        num_iter = iter;
        return;                        % 所有校验通过，提前终止
    end
end

num_iter = max_iter;

end
