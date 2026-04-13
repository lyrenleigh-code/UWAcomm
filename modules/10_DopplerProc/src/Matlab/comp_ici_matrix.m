function Y_comp = comp_ici_matrix(Y, alpha_est, N_fft)
% 功能：ICI矩阵补偿（10-2，OFDM高速场景）
% 版本：V1.0.0
% 输入：
%   Y         - 频域接收信号 (1xN_fft 或 KxN_fft，K个OFDM符号)
%   alpha_est - 多普勒因子估计（粗补偿后的残余值）
%   N_fft     - FFT点数
% 输出：
%   Y_comp - ICI补偿后的频域信号
%
% 备注：
%   - 宽带多普勒导致ICI：D_kl(α) = (1/N)Σexp(j2π(l-k(1+α))n/N)
%   - 补偿：Y_comp = D^{-1} * Y（或MMSE: (D'D+σ²I)^{-1}D'Y）
%   - 计算量 O(N²)，仅在高速场景（|α|>1e-4）需要

%% ========== 参数校验 ========== %%
if isempty(Y), error('频域信号不能为空！'); end
if abs(alpha_est) < 1e-6
    Y_comp = Y;                        % α太小不需要ICI补偿
    return;
end

%% ========== 构建ICI矩阵D ========== %%
D = zeros(N_fft, N_fft);
n = 0:N_fft-1;
for k = 0:N_fft-1
    for l = 0:N_fft-1
        D(k+1, l+1) = sum(exp(1j*2*pi*(l - k*(1+alpha_est)) .* n / N_fft)) / N_fft;
    end
end

%% ========== ICI补偿（正则化求逆） ========== %%
reg = 1e-4 * eye(N_fft);              % 正则化项防止矩阵奇异

if isvector(Y)
    Y = Y(:);
    Y_comp = ((D' * D + reg) \ (D' * Y)).';
else
    K = size(Y, 1);
    Y_comp = zeros(K, N_fft);
    D_inv = (D' * D + reg) \ D';
    for s = 1:K
        Y_comp(s, :) = (D_inv * Y(s, :).').';
    end
end

end
