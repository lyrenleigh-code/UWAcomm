function [LLR_ext, LLR_post, LLR_post_coded] = sova_decode_conv(LLR_ch, LLR_prior, gen_polys, constraint_len)
% 功能：SOVA（软输出Viterbi）卷积码译码器——用于Turbo均衡对比
% 版本：V1.0.0
% 输入：
%   LLR_ch        - 信道LLR (1xM，编码比特)，正值→bit 1
%   LLR_prior     - 先验LLR (1xN_info，信息比特先验，首次=0)
%   gen_polys     - 生成多项式 (默认 [7,5])
%   constraint_len- 约束长度K (默认 3)
% 输出：
%   LLR_ext       - 信息比特外信息 (1xN_info)
%   LLR_post      - 信息比特后验LLR (1xN_info)
%   LLR_post_coded- 编码比特后验LLR (1xM)
%
% 备注：
%   SOVA = Viterbi + 路径度量差 → 软可靠度
%   比BCJR简单（单向递推），但软输出精度较低
%   复杂度 O(N·S)，S=状态数，与Max-Log-MAP相同但常数更小

%% ========== 入参 ========== %%
if nargin < 4 || isempty(constraint_len), constraint_len = 3; end
if nargin < 3 || isempty(gen_polys), gen_polys = [7, 5]; end

LLR_ch = LLR_ch(:).';
n = length(gen_polys);
K = constraint_len;
num_states = 2^(K-1);
mem = K - 1;

M = length(LLR_ch);
N_total = floor(M / n);
N_info = N_total - mem;

if nargin < 2 || isempty(LLR_prior), LLR_prior = zeros(1, N_info); end
LLR_prior = LLR_prior(:).';
if length(LLR_prior) < N_info
    LLR_prior = [LLR_prior, zeros(1, N_info - length(LLR_prior))];
end

%% ========== 构建网格 ========== %%
gen_bins = zeros(n, K);
for i = 1:n
    oct_str = num2str(gen_polys(i));
    bv = [];
    for j = 1:length(oct_str)
        bv = [bv, de2bi(str2double(oct_str(j)), 3, 'left-msb')]; %#ok<AGROW>
    end
    if length(bv) >= K, gen_bins(i,:) = bv(end-K+1:end);
    else, gen_bins(i,K-length(bv)+1:end) = bv; end
end

next_state = zeros(num_states, 2);
output_bits = zeros(num_states, 2, n);
for s = 0:num_states-1
    state_bits = de2bi(s, mem, 'left-msb');
    for u = 0:1
        reg = [u, state_bits];
        out = zeros(1, n);
        for i = 1:n, out(i) = mod(sum(reg .* gen_bins(i,:)), 2); end
        ns = bi2de(reg(1:mem), 'left-msb');
        next_state(s+1, u+1) = ns;
        output_bits(s+1, u+1, :) = out;
    end
end

LLR_ch_matrix = reshape(LLR_ch(1:N_total*n), n, N_total).';
INF_VAL = 1e10;

%% ========== Viterbi前向 + 路径存储 ========== %%
path_metric = -INF_VAL * ones(num_states, 1);
path_metric(1) = 0;

% 存储幸存路径的决策历史和度量差
surv_decision = zeros(num_states, N_total);   % 每状态每时刻的输入决策
surv_prev_state = zeros(num_states, N_total); % 前驱状态
metric_delta = zeros(num_states, N_total);    % ACS时的度量差（可靠度）

for t = 1:N_total
    if t <= N_info, La = LLR_prior(t); else, La = 0; end

    new_metric = -INF_VAL * ones(num_states, 1);
    new_decision = zeros(num_states, 1);
    new_prev = zeros(num_states, 1);
    new_delta = zeros(num_states, 1);

    for s = 0:num_states-1
        for u = 0:1
            ns = next_state(s+1, u+1);
            out = squeeze(output_bits(s+1, u+1, :)).';
            gamma = (2*u-1) * La / 2;
            for i = 1:n
                gamma = gamma + (2*out(i)-1) * LLR_ch_matrix(t,i) / 2;
            end
            candidate = path_metric(s+1) + gamma;

            if candidate > new_metric(ns+1)
                % 新的胜者——记录度量差
                if new_metric(ns+1) > -INF_VAL
                    new_delta(ns+1) = candidate - new_metric(ns+1);
                else
                    new_delta(ns+1) = INF_VAL;  % 无竞争者
                end
                new_metric(ns+1) = candidate;
                new_decision(ns+1) = u;
                new_prev(ns+1) = s;
            else
                % 更新竞争度量差（取更小值）
                diff = new_metric(ns+1) - candidate;
                if diff < new_delta(ns+1)
                    new_delta(ns+1) = diff;
                end
            end
        end
    end

    path_metric = new_metric;
    surv_decision(:, t) = new_decision;
    surv_prev_state(:, t) = new_prev;
    metric_delta(:, t) = new_delta;
end

%% ========== 回溯 ========== %%
% 终止状态=0（尾比特归零）
final_state = 0;
decoded_bits = zeros(1, N_total);
decoded_coded = zeros(N_total, n);
state_path = zeros(1, N_total + 1);
state_path(N_total + 1) = final_state;

cur_state = final_state;
for t = N_total:-1:1
    decoded_bits(t) = surv_decision(cur_state+1, t);
    decoded_coded(t,:) = squeeze(output_bits(surv_prev_state(cur_state+1,t)+1, decoded_bits(t)+1, :)).';
    state_path(t) = surv_prev_state(cur_state+1, t);
    cur_state = surv_prev_state(cur_state+1, t);
end

%% ========== 软输出：基于度量差的可靠度 ========== %%
% 信息比特软输出
reliability_info = zeros(1, N_info);
for t = 1:N_info
    % 沿ML路径在时刻t的度量差
    s_at_t = state_path(t+1);  % 回溯后在t+1时刻的状态
    rel = metric_delta(s_at_t+1, t);
    reliability_info(t) = min(rel, 30);  % 截断防溢出
end

LLR_post = (2*decoded_bits(1:N_info) - 1) .* reliability_info;
LLR_ext = LLR_post - LLR_prior(1:N_info);

%% ========== 编码比特软输出 ========== %%
if nargout >= 3
    LLR_post_coded = zeros(1, N_total * n);
    for t = 1:N_total
        s_at_t = state_path(t+1);
        rel = min(metric_delta(s_at_t+1, t), 30);
        for i = 1:n
            LLR_post_coded((t-1)*n + i) = (2*decoded_coded(t,i) - 1) * rel;
        end
    end
end

end
