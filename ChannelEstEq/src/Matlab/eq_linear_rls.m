function [LLR_out, x_hat, noise_var_est] = eq_linear_rls(y, training, num_taps, lambda_rls, pll_params)
% 功能：RLS线性均衡器（含PLL，输出LLR，Turbo迭代第1次用）
% 版本：V1.0.0 — 参考Turbo Equalization工程实现
% 输入：
%   y          - 接收信号 (1xN)
%   training   - 训练序列 (1xT)
%   num_taps   - 均衡器阶数 (默认 21)
%   lambda_rls - RLS遗忘因子 (默认 0.998)
%   pll_params - PLL参数（同eq_dfe）
% 输出：
%   LLR_out, x_hat, noise_var_est（同eq_dfe）
%
% 备注：
%   - 线性均衡 = DFE的反馈阶数为0的特例
%   - Turbo迭代第1次用线性（无先验信息），后续切DFE

%% ========== 入参 ========== %%
if nargin < 5, pll_params = struct('enable', true, 'Kp', 0.01, 'Ki', 0.005); end
if nargin < 4 || isempty(lambda_rls), lambda_rls = 0.998; end
if nargin < 3 || isempty(num_taps), num_taps = 21; end

%% ========== 调用DFE（反馈阶数=0） ========== %%
[LLR_out, x_hat, noise_var_est] = eq_dfe(y, [], training, num_taps, 0, lambda_rls, pll_params);

end
