function [x_tilde, mu, nv_tilde] = eq_mmse_ic_tv_fde(Y_freq, h_time_block, delays_sym, x_bar, var_x, noise_var)
% 功能：ICI-aware MMSE-IC频域均衡器（时变信道，含软先验接口）
% 版本：V1.0.0
%
% 当信道在FFT块内变化时，频域产生载波间干扰(ICI)：
%   Y(k) = Σ_l H_tv(k,l)·X(l) + W(k)
% 本函数构建完整ICI矩阵H_tv，执行矩阵级MMSE-IC均衡。
% 静态信道时H_tv退化为对角阵，等价于eq_mmse_ic_fde。
%
% 输入：
%   Y_freq        - 频域接收信号 (1×N)
%   h_time_block  - 块内时变信道增益 (P×N，第p行=第p径在N个数据符号时刻的复增益)
%   delays_sym    - 各径符号级时延 (1×P，已mod N)
%   x_bar         - 时域软符号先验 (1×N，首次迭代全0)
%   var_x         - 残余符号方差 (标量，首次迭代=1)
%   noise_var     - 噪声方差 σ²_w
%
% 输出：
%   x_tilde  - 时域均衡输出 (1×N)
%   mu       - 等效增益 μ (标量)
%   nv_tilde - 等效噪声方差 σ²_z (标量)
%
% 数学推导：
%   频率-时间矩阵：H(l,n) = Σ_p g_p(n)·exp(-j2πl·d_p/N)
%   ICI矩阵：H_tv(k,l) = (1/N) Σ_n H(l,n)·exp(-j2π(k-l)n/N)
%   MMSE-IC：X̂ = X̄ + (H_tv'H_tv + σ²_w/σ²_x·I)^{-1}·H_tv'·(Y - H_tv·X̄)
%   等效增益：μ = mean(diag(G·H_tv))，G = (H_tv'H_tv + λI)^{-1}·H_tv'
%   等效噪声：σ²_z = μ(1-μ)σ²_x + σ²_w·||G||²_F/N
%
% 复杂度：O(N³)（N=128时 <5ms/块）
% 静态信道时H_tv为对角阵，结果与eq_mmse_ic_fde一致

%% ========== 入参 ========== %%
N = length(Y_freq);
Y_freq = Y_freq(:);
P = size(h_time_block, 1);

if nargin < 6 || isempty(noise_var), noise_var = 0.01; end
if nargin < 5 || isempty(var_x), var_x = 1; end
if nargin < 4 || isempty(x_bar), x_bar = zeros(1, N); end
x_bar = x_bar(:).';
var_x = max(var_x, 1e-8);
noise_var = max(noise_var, 1e-10);

%% ========== 1. 频率-时间矩阵 H(l,n) ========== %%
% H(l,n) = Σ_p g_p(n)·exp(-j2πl·d_p/N)
phase_delay = exp(-1j * 2*pi * (0:N-1).' * delays_sym(:).' / N);  % N×P
H_ln = phase_delay * h_time_block;  % N×N

%% ========== 2. ICI矩阵 H_tv(k,l) ========== %%
% H_tv(k,l) = (1/N)·DFT_k{ H(l,n)·exp(j2πl·n/N) }
% 利用FFT加速: O(N² log N)
n_vec = 0:N-1;
H_tv = zeros(N, N);
for l = 0:N-1
    shift = exp(1j * 2*pi * l * n_vec / N);
    H_tv(:, l+1) = fft(H_ln(l+1,:) .* shift).' / N;
end

%% ========== 3. MMSE-IC均衡 ========== %%
X_bar = fft(x_bar(:));
Residual = Y_freq - H_tv * X_bar;

lambda = noise_var / var_x;
HtH = H_tv' * H_tv;
M = HtH + lambda * eye(N);

% Cholesky分解 (Hermitian正定)
[L, flag] = chol(M, 'lower');
if flag ~= 0
    M = M + 1e-6 * eye(N);
    L = chol(M, 'lower');
end

% 均衡输出: X̂ = X̄ + G·(Y - H_tv·X̄)
G_Res = L' \ (L \ (H_tv' * Residual));
X_hat = X_bar + G_Res;
x_tilde = ifft(X_hat).';

%% ========== 4. 等效增益和噪声方差 ========== %%
% A = G·H_tv, mu = mean(diag(A))
A = L' \ (L \ HtH);
mu = real(mean(diag(A)));
mu = max(mu, 1e-8);

% 噪声方差 = 信号残差 + 噪声增强
G_tv = L' \ (L \ H_tv');
g_power = sum(abs(G_tv).^2, 2);
nv_tilde = mu * (1 - mu) * var_x + noise_var * mean(g_power);
nv_tilde = max(real(nv_tilde), 1e-10);

end
