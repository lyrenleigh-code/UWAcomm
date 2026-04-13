function [x_hat, H_tv] = eq_mmse_tv_fde(Y_freq, h_time_block, delays_sym, N_fft, noise_var)
% 功能：时变信道MMSE频域均衡——构建ICI矩阵并MMSE求逆
% 版本：V1.0.0
% 输入：
%   Y_freq        - 频域接收信号 (1×N_fft)
%   h_time_block  - 块内时变信道增益 (P×N_fft，P条路径在N_fft个符号时刻的复增益)
%   delays_sym    - 各路径符号级时延 (1×P)
%   N_fft         - FFT点数
%   noise_var     - 噪声方差
% 输出：
%   x_hat  - 均衡后时域符号 (1×N_fft)
%   H_tv   - 时变信道ICI矩阵 (N_fft × N_fft)
%
% 备注：
%   时变信道在频域产生ICI：Y(k) = Σ_l H_tv(k,l)·X(l) + N(k)
%   H_tv(k,l) = (1/N) Σ_n H(l,n)·exp(-j2π(k-l)n/N)
%   其中 H(l,n) = Σ_p g_p(n)·exp(-j2πl·d_p/N) 是时刻n的频响
%   MMSE均衡：X̂ = (H_tv'H_tv + σ²I)^{-1} H_tv' Y

%% ========== 入参 ========== %%
Y_freq = Y_freq(:);
N = N_fft;
P = size(h_time_block, 1);
if nargin < 5 || isempty(noise_var), noise_var = 0.01; end

%% ========== 构建时变频响 H(l,n) ========== %%
% H(l,n) = sum_p g_p(n) * exp(-j2π*l*d_p/N), l=0..N-1, n=0..N-1
H_ln = zeros(N, N);  % H(l+1, n+1)
for n = 1:N
    for p = 1:P
        d = delays_sym(min(p, length(delays_sym)));
        phase = exp(-1j * 2 * pi * (0:N-1).' * d / N);
        H_ln(:, n) = H_ln(:, n) + h_time_block(p, n) * phase;
    end
end

%% ========== 构建ICI矩阵 H_tv(k,l) ========== %%
% H_tv(k,l) = (1/N) Σ_n H(l,n) * exp(-j2π(k-l)n/N)
% 等价于对 H(l,n) 沿n做DFT，频率索引为(k-l)
H_tv = zeros(N, N);
n_vec = (0:N-1).';
for k = 0:N-1
    for l = 0:N-1
        dft_kernel = exp(-1j * 2*pi * (k-l) * n_vec / N) / N;
        H_tv(k+1, l+1) = H_ln(l+1, :) * dft_kernel;
    end
end

%% ========== MMSE均衡 ========== %%
X_hat = (H_tv' * H_tv + noise_var * eye(N)) \ (H_tv' * Y_freq);
x_hat = ifft(X_hat).';  % 频域→时域

end
