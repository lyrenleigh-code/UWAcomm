function [alpha_est, corr_vals] = est_doppler_cp(r, N_fft, N_cp, interp_flag)
% 功能：CP自相关法多普勒估计（OFDM专用）
% 版本：V1.0.0
% 输入：
%   r           - 接收OFDM信号 (1xM)
%   N_fft       - FFT点数
%   N_cp        - CP长度
%   interp_flag - 是否用抛物线插值精化 (默认 true)
% 输出：
%   alpha_est - 多普勒因子估计
%   corr_vals - 自相关序列（供调试）
%
% 备注：
%   - 利用CP与数据尾部相同：R(m) = Σ r[n+m]·r*[n+m+N]
%   - 相关峰偏移量Δn与α的关系：α_coarse = Δn/N
%   - 抛物线插值可提高到亚样本精度

%% ========== 入参解析 ========== %%
if nargin < 4 || isempty(interp_flag), interp_flag = true; end
r = r(:).';

%% ========== 参数校验 ========== %%
if isempty(r), error('接收信号不能为空！'); end
if length(r) < N_fft + N_cp, error('信号长度不足一个OFDM符号！'); end

%% ========== CP自相关 ========== %%
corr_vals = zeros(1, N_fft);
for offset = 1:min(N_fft, length(r) - N_fft - N_cp + 1)
    seg1 = r(offset : offset + N_cp - 1);
    seg2 = r(offset + N_fft : offset + N_fft + N_cp - 1);
    corr_vals(offset) = abs(sum(seg1 .* conj(seg2)))^2;
end

%% ========== 粗估计 ========== %%
[~, peak_pos] = max(corr_vals);
alpha_coarse = (peak_pos - 1) / N_fft;

%% ========== 抛物线插值精化 ========== %%
if interp_flag && peak_pos > 1 && peak_pos < length(corr_vals)
    R_m1 = corr_vals(peak_pos - 1);
    R_0 = corr_vals(peak_pos);
    R_p1 = corr_vals(peak_pos + 1);
    denom = 2 * R_0 - R_p1 - R_m1;
    if abs(denom) > 1e-10
        delta = (R_p1 - R_m1) / (2 * denom);
        alpha_est = alpha_coarse + delta / N_fft;
    else
        alpha_est = alpha_coarse;
    end
else
    alpha_est = alpha_coarse;
end

end
