function [LLR_out, x_hat, noise_var_est] = eq_bidirectional_dfe(y, h_est, training, num_ff, num_fb, lambda_rls, pll_params)
% 功能：双向DFE——前向+后向DFE联合判决，抑制错误传播
% 版本：V3.0.0 — 基于RLS自适应DFE v3.0
% 输入：（同eq_dfe）
% 输出：
%   LLR_out       - 联合判决后的LLR软信息
%   x_hat         - 联合判决后的软符号
%   noise_var_est - 估计噪声方差
%
% 备注：
%   - 前向DFE：标准方向均衡
%   - 后向DFE：信号和训练序列反转后均衡
%   - 联合：取LLR绝对值更大方向的结果

%% ========== 入参 ========== %%
if nargin < 7, pll_params = struct('enable',true,'Kp',0.01,'Ki',0.005); end
if nargin < 6 || isempty(lambda_rls), lambda_rls = 0.998; end
if nargin < 5 || isempty(num_fb), num_fb = 10; end
if nargin < 4 || isempty(num_ff), num_ff = 21; end

%% ========== 前向DFE ========== %%
[llr_fwd, x_fwd, nv_fwd] = eq_dfe(y, h_est, training, num_ff, num_fb, lambda_rls, pll_params);

%% ========== 后向DFE ========== %%
y_rev = fliplr(y);
training_rev = fliplr(training);
h_rev = [];
if ~isempty(h_est), h_rev = fliplr(h_est); end

[llr_bwd_rev, ~, nv_bwd] = eq_dfe(y_rev, h_rev, training_rev, num_ff, num_fb, lambda_rls, pll_params);
llr_bwd = fliplr(llr_bwd_rev);

%% ========== 联合判决 ========== %%
min_len = min(length(llr_fwd), length(llr_bwd));
LLR_out = zeros(1, min_len);

for k = 1:min_len
    if abs(llr_fwd(k)) >= abs(llr_bwd(k))
        LLR_out(k) = llr_fwd(k);
    else
        LLR_out(k) = llr_bwd(k);
    end
end

x_hat = llr_to_symbol(LLR_out, 'qpsk');
noise_var_est = min(nv_fwd, nv_bwd);

end
