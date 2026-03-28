function [x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq, H_est, x_bar, var_x, noise_var)
% 功能：迭代MMSE-IC频域均衡器（正确LMMSE公式）
% 版本：V2.0.0
% 输入：
%   Y_freq    - 频域接收信号 (1×N)
%   H_est     - 频域信道估计 (1×N)
%   x_bar     - 时域软符号先验 (1×N，首次迭代全0)
%   var_x     - 残余符号方差 (标量，首次迭代=1)
%   noise_var - 噪声方差 σ²_w
% 输出：
%   x_tilde   - 时域均衡输出 (1×N)
%   mu        - 等效增益 μ = mean(G·H) (标量)
%   nv_tilde  - 等效噪声方差 (标量)
%
% 备注：
%   正确LMMSE公式（从条件均值推导）：
%     G[k] = σ²_x · H*[k] / (σ²_x·|H[k]|² + σ²_w)    注意：G = σ²_x · W
%     X̂[k] = X̄[k] + G[k] · (Y[k] - H[k]·X̄[k])       输出包含x̄项！
%     x̃    = IFFT(X̂) = x̄ + IFFT(G · (Y - H·X̄))
%     μ     = mean(G·H)
%
%   V1的错误：x̃ = IFFT(W·[Y-(1-WH)·X̄]) 丢失了x̄项，导致信号衰减

%% ========== 入参 ========== %%
H_est = H_est(:).';
Y_freq = Y_freq(:).';
N = length(H_est);

if nargin < 5 || isempty(noise_var), noise_var = 0.01; end
if nargin < 4 || isempty(var_x), var_x = 1; end
if nargin < 3 || isempty(x_bar), x_bar = zeros(1, N); end
x_bar = x_bar(:).';

var_x = max(var_x, 1e-8);
noise_var = max(noise_var, 1e-10);

%% ========== 正确LMMSE均衡 ========== %%
% LMMSE滤波器 G（注意：G = σ²_x · W，不是W本身）
G = var_x * conj(H_est) ./ (var_x * abs(H_est).^2 + noise_var);

% 频域软估计
X_bar = fft(x_bar);

% 残差 = 接收 - 预测
Residual = Y_freq - H_est .* X_bar;

% LMMSE输出：x̂ = x̄ + IFFT(G · 残差)
x_tilde = x_bar + ifft(G .* Residual);

%% ========== 等效增益和噪声 ========== %%
GH = G .* H_est;
mu = real(mean(GH));
mu = max(mu, 1e-8);

% 等效噪声方差
nv_tilde = mu * (1 - mu) * var_x + mean(abs(G).^2) * noise_var;
nv_tilde = max(real(nv_tilde), 1e-10);

end
