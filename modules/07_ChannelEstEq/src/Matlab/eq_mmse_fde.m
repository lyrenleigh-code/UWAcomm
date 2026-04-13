function [x_hat, X_hat_freq] = eq_mmse_fde(Y_freq, H_est, noise_var)
% 功能：MMSE频域均衡（SC-FDE / OFDM通用）
% 版本：V1.0.0
% 输入：
%   Y_freq    - 频域接收信号 (1xN 或 KxN矩阵，K个块)
%   H_est     - 频域信道估计 (1xN)
%   noise_var - 噪声方差 (默认 0.01)
% 输出：
%   x_hat      - 均衡后的时域符号 (与Y_freq同尺寸)
%   X_hat_freq - 均衡后的频域符号
%
% 备注：
%   - MMSE: X_hat[k] = H*[k]/(|H[k]|^2 + sigma^2) * Y[k]
%   - SC-FDE：均衡后做IFFT回到时域
%   - OFDM：均衡后直接是频域数据符号

%% ========== 入参 ========== %%
if nargin < 3 || isempty(noise_var), noise_var = 0.01; end
H_est = H_est(:).';
N = length(H_est);

%% ========== MMSE均衡权重 ========== %%
W_mmse = conj(H_est) ./ (abs(H_est).^2 + noise_var);

%% ========== 均衡 ========== %%
if isvector(Y_freq)
    Y_freq = Y_freq(:).';
    X_hat_freq = W_mmse .* Y_freq;
    x_hat = ifft(X_hat_freq);
else
    % 多块模式
    [K, ~] = size(Y_freq);
    X_hat_freq = zeros(K, N);
    x_hat = zeros(K, N);
    for b = 1:K
        X_hat_freq(b, :) = W_mmse .* Y_freq(b, :);
        x_hat(b, :) = ifft(X_hat_freq(b, :));
    end
end

end
