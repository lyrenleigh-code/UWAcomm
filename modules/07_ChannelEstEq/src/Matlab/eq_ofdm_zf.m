function [X_hat, H_inv] = eq_ofdm_zf(Y_freq, H_est)
% 功能：OFDM ZF（迫零）频域均衡
% 版本：V1.0.0
% 输入：
%   Y_freq - 频域接收符号 (1xN 或 KxN，K个OFDM符号)
%   H_est  - 频域信道估计 (1xN)
% 输出：
%   X_hat - 均衡后的频域数据符号
%   H_inv - ZF均衡权重 (1/H)
%
% 备注：
%   - ZF: X_hat[k] = Y[k] / H[k]
%   - 简单但在信道零点处噪声增强严重

%% ========== 均衡 ========== %%
H_est = H_est(:).';
H_inv = 1 ./ (H_est + 1e-10);         % 避免除零

if isvector(Y_freq)
    X_hat = Y_freq(:).' .* H_inv;
else
    X_hat = Y_freq .* repmat(H_inv, size(Y_freq,1), 1);
end

end
