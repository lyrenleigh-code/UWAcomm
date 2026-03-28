function [LLR_ext, LLR_post] = siso_decode_conv(LLR_ch, LLR_prior, gen_polys, constraint_len)
% 功能：BCJR (MAP) SISO卷积码译码器——输出外信息，用于Turbo均衡
% 版本：V1.0.0
% 输入：
%   LLR_ch        - 信道LLR (1xM，均衡器输出的编码比特LLR)
%                   正值→bit 1，负值→bit 0
%   LLR_prior     - 先验LLR (1xN_info，信息比特的先验，首次迭代全0)
%   gen_polys     - 生成多项式 (1xn 八进制，默认 [7,5] 即K=3 rate-1/2)
%   constraint_len- 约束长度K (默认 3)
% 输出：
%   LLR_ext  - 外信息LLR (1xN_info，= LLR_post - LLR_prior - LLR_ch_sys)
%              反馈给均衡器作为下一次迭代的先验
%   LLR_post - 后验LLR (1xN_info，信息比特的后验概率)
%
% 备注：
%   - BCJR = 前向α递推 + 后向β递推 + 合并计算后验LLR
%   - 使用Max-Log-MAP近似避免数值下溢
%   - 外信息 = 后验 - 先验 - 信道系统位（Turbo均衡的核心）
%   - rate = 1/n，n由gen_polys长度决定

%% ========== 入参 ========== %%
if nargin < 4 || isempty(constraint_len), constraint_len = 3; end
if nargin < 3 || isempty(gen_polys), gen_polys = [7, 5]; end

LLR_ch = LLR_ch(:).';
n = length(gen_polys);                 % 码率 1/n
K = constraint_len;
num_states = 2^(K-1);
mem = K - 1;

% 编码比特总数应为n的整数倍
M = length(LLR_ch);
N_total = floor(M / n);               % 总时刻数（含尾比特）
N_info = N_total - mem;               % 信息比特数

if nargin < 2 || isempty(LLR_prior)
    LLR_prior = zeros(1, N_info);
end
LLR_prior = LLR_prior(:).';
if length(LLR_prior) < N_info
    LLR_prior = [LLR_prior, zeros(1, N_info - length(LLR_prior))];
end

%% ========== 构建网格 ========== %%
% 生成多项式转二进制
gen_bins = zeros(n, K);
for i = 1:n
    oct_str = num2str(gen_polys(i));
    bv = [];
    for j = 1:length(oct_str)
        bv = [bv, de2bi(str2double(oct_str(j)), 3, 'left-msb')]; %#ok<AGROW>
    end
    if length(bv) >= K
        gen_bins(i,:) = bv(end-K+1:end);
    else
        gen_bins(i,K-length(bv)+1:end) = bv;
    end
end

% 状态转移表和输出表
next_state = zeros(num_states, 2);     % 列1=输入0, 列2=输入1
output_bits = zeros(num_states, 2, n); % output_bits(state, input+1, :) = n个输出比特

for s = 0:num_states-1
    state_bits = de2bi(s, mem, 'left-msb');
    for u = 0:1
        reg = [u, state_bits];
        out = zeros(1, n);
        for i = 1:n
            out(i) = mod(sum(reg .* gen_bins(i,:)), 2);
        end
        ns = bi2de(reg(1:mem), 'left-msb');
        next_state(s+1, u+1) = ns;
        output_bits(s+1, u+1, :) = out;
    end
end

%% ========== 计算分支度量γ ========== %%
% γ(t, s, u) = exp(u*La/2 + sum_i c_i*Lc_i/2)
% La = 先验LLR，Lc = 信道LLR
INF_VAL = 1e10;

% 重组信道LLR为 N_total x n 矩阵
LLR_ch_matrix = reshape(LLR_ch(1:N_total*n), n, N_total).';

%% ========== 前向递推α（Max-Log域） ========== %%
alpha = -INF_VAL * ones(num_states, N_total+1);
alpha(1, 1) = 0;                       % 初始状态0

for t = 1:N_total
    % 先验（信息比特的先验LLR）
    if t <= N_info
        La = LLR_prior(t);
    else
        La = 0;                        % 尾比特无先验
    end

    for s = 0:num_states-1
        for u = 0:1
            ns = next_state(s+1, u+1);
            out = squeeze(output_bits(s+1, u+1, :)).';

            % 分支度量
            gamma_branch = (2*u-1) * La / 2;  % 先验贡献
            for i = 1:n
                gamma_branch = gamma_branch + (2*out(i)-1) * LLR_ch_matrix(t,i) / 2;
            end

            % Max-Log更新
            candidate = alpha(s+1, t) + gamma_branch;
            if candidate > alpha(ns+1, t+1)
                alpha(ns+1, t+1) = candidate;
            end
        end
    end

    % 归一化防溢出
    max_alpha = max(alpha(:, t+1));
    if max_alpha > -INF_VAL
        alpha(:, t+1) = alpha(:, t+1) - max_alpha;
    end
end

%% ========== 后向递推β ========== %%
beta = -INF_VAL * ones(num_states, N_total+1);
beta(1, N_total+1) = 0;               % 终止状态0（尾比特归零）

for t = N_total:-1:1
    if t <= N_info
        La = LLR_prior(t);
    else
        La = 0;
    end

    for s = 0:num_states-1
        for u = 0:1
            ns = next_state(s+1, u+1);
            out = squeeze(output_bits(s+1, u+1, :)).';

            gamma_branch = (2*u-1) * La / 2;
            for i = 1:n
                gamma_branch = gamma_branch + (2*out(i)-1) * LLR_ch_matrix(t,i) / 2;
            end

            candidate = beta(ns+1, t+1) + gamma_branch;
            if candidate > beta(s+1, t)
                beta(s+1, t) = candidate;
            end
        end
    end

    max_beta = max(beta(:, t));
    if max_beta > -INF_VAL
        beta(:, t) = beta(:, t) - max_beta;
    end
end

%% ========== 计算后验LLR ========== %%
LLR_post = zeros(1, N_info);

for t = 1:N_info
    La = LLR_prior(t);
    max_u1 = -INF_VAL;
    max_u0 = -INF_VAL;

    for s = 0:num_states-1
        for u = 0:1
            ns = next_state(s+1, u+1);
            out = squeeze(output_bits(s+1, u+1, :)).';

            gamma_branch = (2*u-1) * La / 2;
            for i = 1:n
                gamma_branch = gamma_branch + (2*out(i)-1) * LLR_ch_matrix(t,i) / 2;
            end

            metric = alpha(s+1, t) + gamma_branch + beta(ns+1, t+1);

            if u == 1
                max_u1 = max(max_u1, metric);
            else
                max_u0 = max(max_u0, metric);
            end
        end
    end

    LLR_post(t) = max_u1 - max_u0;
end

%% ========== 外信息 = 后验 - 先验 - 信道系统位 ========== %%
% 对于非系统码，信道系统位贡献已包含在γ中
% 外信息 = 后验 - 先验
LLR_ext = LLR_post - LLR_prior(1:N_info);

end
