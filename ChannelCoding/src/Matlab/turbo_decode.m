function [decoded, LLR_out] = turbo_decode(received, params, snr_db, num_iter)
% 功能：Turbo迭代译码器（基于Log-MAP/BCJR算法）
% 版本：V1.0.0
% 输入：
%   received    - 接收软值序列 (1x3N 实数数组)
%                 排列顺序与编码一致：[系统位, 校验位1, 校验位2]
%                 正值倾向于比特1，负值倾向于比特0
%   params      - 编码参数结构体（由 turbo_encode 生成）
%   snr_db      - 信噪比 (dB)，用于计算信道可靠度 Lc
%   num_iter    - 迭代次数 (正整数，默认使用 params.num_iter)
% 输出：
%   decoded     - 硬判决译码结果 (1xN 二进制数组)
%   LLR_out     - 最终对数似然比 (1xN 实数数组，正=1，负=0)
%
% 备注：
%   - 采用Max-Log-MAP近似简化BCJR计算
%   - 两个分量译码器交替迭代，交换外信息(extrinsic information)
%   - 信道可靠度 Lc = 4 * R * Eb/N0，其中 R=1/3 为码率

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 4 || isempty(num_iter)
    num_iter = params.num_iter;
end
received = double(received(:).');

N = params.msg_len;                    % 信息比特长度
interleaver = params.interleaver;
deinterleaver = params.deinterleaver;
fb_poly = params.fb_poly;
ff_poly = params.ff_poly;
K = params.constraint_len;
mem_len = K - 1;
num_states = 2^mem_len;

%% ========== 2. 严格参数校验 ========== %%
if isempty(received)
    error('接收序列不能为空！');
end
if length(received) ~= 3 * N
    error('接收序列长度(%d)应为 3*N=%d！', length(received), 3*N);
end
if num_iter < 1
    error('迭代次数必须为正整数！');
end

%% ========== 3. 分离系统位和校验位 ========== %%
sys  = received(1:N);                  % 系统位软值
par1 = received(N+1:2*N);             % 校验位1软值
par2 = received(2*N+1:3*N);           % 校验位2软值

% 信道可靠度
R = 1/3;                              % 码率
snr_lin = 10^(snr_db/10);
Lc = 4 * R * snr_lin;                 % 信道可靠度系数

%% ========== 4. 构建RSC网格 ========== %%
[next_state_table, output_table] = build_rsc_trellis(fb_poly, ff_poly, K);

%% ========== 5. 迭代译码 ========== %%
Le1 = zeros(1, N);                     % 译码器1输出的外信息
Le2 = zeros(1, N);                     % 译码器2输出的外信息

for iter = 1:num_iter
    % --- 译码器1：使用原始顺序 ---
    La1 = Le2(deinterleaver);          % 译码器2的外信息经解交织作为先验
    L_sys1 = Lc * sys;
    L_par1 = Lc * par1;
    [L_post1, Le1] = bcjr_decode_local(L_sys1, L_par1, La1, ...
                                        next_state_table, output_table, num_states, N);

    % --- 译码器2：使用交织顺序 ---
    La2 = Le1(interleaver);            % 译码器1的外信息经交织作为先验
    L_sys2 = Lc * sys(interleaver);
    L_par2 = Lc * par2;
    [L_post2, Le2] = bcjr_decode_local(L_sys2, L_par2, La2, ...
                                        next_state_table, output_table, num_states, N);
end

%% ========== 6. 最终判决 ========== %%
% 将译码器2的后验LLR解交织回原始顺序
LLR_out = L_post2(deinterleaver);
decoded = double(LLR_out > 0);

end

% --------------- 辅助函数1：Max-Log-MAP (BCJR) 分量译码器 --------------- %
function [L_post, L_ext] = bcjr_decode_local(L_sys, L_par, L_apriori, ...
                                              next_state, output_table, num_states, N)
% BCJR_DECODE_LOCAL Max-Log-MAP分量译码器
% 输入参数：
%   L_sys       - 系统位信道LLR (1xN)
%   L_par       - 校验位信道LLR (1xN)
%   L_apriori   - 先验LLR (1xN)
%   next_state  - 状态转移表 (numStates x 2)
%   output_table- 输出表 (numStates x 2)，校验位值 0/1
%   num_states  - 状态总数
%   N           - 序列长度
% 输出参数：
%   L_post      - 后验LLR (1xN)
%   L_ext       - 外信息LLR (1xN)

INF_VAL = 1e10;

% 前向度量 alpha: (num_states x N+1)
alpha = -INF_VAL * ones(num_states, N+1);
alpha(1, 1) = 0;                       % 初始状态0的概率为1

% 后向度量 beta: (num_states x N+1)
beta = -INF_VAL * ones(num_states, N+1);
beta(1, N+1) = 0;                     % 终止状态0（假设尾比特归零或近似）

% --- 计算分支度量 gamma 并前向递推 alpha ---
% gamma(state, input, t) 存储为两个矩阵
gamma0 = zeros(num_states, N);        % 输入=0的分支度量
gamma1 = zeros(num_states, N);        % 输入=1的分支度量

for t = 1:N
    for s = 0:num_states-1
        for u = 0:1
            % 系统位贡献
            Ls = (2*u - 1) * (L_sys(t) + L_apriori(t)) / 2;

            % 校验位贡献
            p = output_table(s+1, u+1);  % 校验位 0或1
            Lp = (2*p - 1) * L_par(t) / 2;

            gamma_val = Ls + Lp;

            if u == 0
                gamma0(s+1, t) = gamma_val;
            else
                gamma1(s+1, t) = gamma_val;
            end
        end
    end
end

% 前向递推 alpha
for t = 1:N
    for s = 0:num_states-1
        % 找所有能转移到状态s的前驱
        candidates = -INF_VAL * ones(1, num_states * 2);
        idx = 0;
        for prev_s = 0:num_states-1
            for u = 0:1
                if next_state(prev_s+1, u+1) == s
                    if u == 0
                        g = gamma0(prev_s+1, t);
                    else
                        g = gamma1(prev_s+1, t);
                    end
                    idx = idx + 1;
                    candidates(idx) = alpha(prev_s+1, t) + g;
                end
            end
        end
        if idx > 0
            alpha(s+1, t+1) = max(candidates(1:idx));  % Max-Log近似
        end
    end

    % 归一化防止数值溢出
    max_alpha = max(alpha(:, t+1));
    if max_alpha > -INF_VAL
        alpha(:, t+1) = alpha(:, t+1) - max_alpha;
    end
end

% 后向递推 beta
for t = N:-1:1
    for s = 0:num_states-1
        for u = 0:1
            ns = next_state(s+1, u+1);
            if u == 0
                g = gamma0(s+1, t);
            else
                g = gamma1(s+1, t);
            end
            beta(s+1, t) = max(beta(s+1, t), beta(ns+1, t+1) + g);
        end
    end

    % 归一化
    max_beta = max(beta(:, t));
    if max_beta > -INF_VAL
        beta(:, t) = beta(:, t) - max_beta;
    end
end

% --- 计算后验LLR ---
L_post = zeros(1, N);
for t = 1:N
    max_u1 = -INF_VAL;                % 输入=1的最大度量
    max_u0 = -INF_VAL;                % 输入=0的最大度量

    for s = 0:num_states-1
        % 输入=1
        ns1 = next_state(s+1, 2);
        metric1 = alpha(s+1, t) + gamma1(s+1, t) + beta(ns1+1, t+1);
        max_u1 = max(max_u1, metric1);

        % 输入=0
        ns0 = next_state(s+1, 1);
        metric0 = alpha(s+1, t) + gamma0(s+1, t) + beta(ns0+1, t+1);
        max_u0 = max(max_u0, metric0);
    end

    L_post(t) = max_u1 - max_u0;
end

% 外信息 = 后验 - 信道系统 - 先验
L_ext = L_post - L_sys - L_apriori;

end

% --------------- 辅助函数2：构建RSC网格结构 --------------- %
function [next_state, output_table] = build_rsc_trellis(fb_poly, ff_poly, K)
% BUILD_RSC_TRELLIS 构建RSC编码器的状态转移表和输出表
% 输入参数：
%   fb_poly - 反馈多项式（八进制）
%   ff_poly - 前馈多项式（八进制）
%   K       - 约束长度
% 输出参数：
%   next_state  - 状态转移表 (numStates x 2)
%   output_table- 校验位输出表 (numStates x 2)，值为0或1

mem_len = K - 1;
num_states = 2^mem_len;

fb_bin = oct2bin_rsc(fb_poly, K);
ff_bin = oct2bin_rsc(ff_poly, K);

next_state = zeros(num_states, 2);
output_table = zeros(num_states, 2);

for s = 0:num_states-1
    state_bits = de2bi(s, mem_len, 'left-msb');

    for u = 0:1
        % 反馈
        fb_bit = mod(u + sum(state_bits .* fb_bin(2:end)), 2);

        % 校验位输出
        reg = [fb_bit, state_bits];
        parity = mod(sum(reg .* ff_bin), 2);

        % 下一状态
        new_state_bits = [fb_bit, state_bits(1:end-1)];
        ns = bi2de(new_state_bits, 'left-msb');

        next_state(s+1, u+1) = ns;
        output_table(s+1, u+1) = parity;
    end
end

end

% --------------- 辅助函数3：八进制转二进制 --------------- %
function bin_vec = oct2bin_rsc(oct_val, K)
% OCT2BIN_RSC 八进制数转为K位二进制行向量

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
