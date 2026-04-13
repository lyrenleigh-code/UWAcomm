function [output, weights] = bf_mvdr(R_array, steering_vector, diag_loading)
% 功能：MVDR/Capon自适应波束形成——最小方差无失真响应
% 版本：V1.0.0
% 输入：
%   R_array         - 多通道接收信号 (MxN)
%   steering_vector - 期望方向导向矢量 (Mx1 复数)
%   diag_loading    - 对角加载量 (默认 0.01，提高数值稳定性)
% 输出：
%   output  - 波束形成后的单路信号 (1xN)
%   weights - MVDR权重向量 (Mx1)
%
% 备注：
%   - MVDR: w = R^{-1}a / (a'R^{-1}a)，最小化输出功率同时保持期望方向增益
%   - 对角加载(R + σI)提高协方差矩阵求逆的数值稳定性
%   - 相比DAS：能自适应抑制干扰方向，但需要足够快拍数估计协方差

%% ========== 参数校验 ========== %%
if isempty(R_array), error('多通道信号不能为空！'); end
[M, N] = size(R_array);

if nargin < 3 || isempty(diag_loading), diag_loading = 0.01; end
if nargin < 2 || isempty(steering_vector)
    steering_vector = ones(M, 1) / sqrt(M);  % 默认正面入射
end
steering_vector = steering_vector(:);

%% ========== 估计协方差矩阵 ========== %%
R_cov = (R_array * R_array') / N;

% 对角加载
R_loaded = R_cov + diag_loading * eye(M);

%% ========== MVDR权重计算 ========== %%
R_inv_a = R_loaded \ steering_vector;
weights = R_inv_a / (steering_vector' * R_inv_a);

%% ========== 波束形成 ========== %%
output = weights' * R_array;

end
