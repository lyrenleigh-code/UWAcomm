function [tau_est, tau_error] = bf_delay_calibration(R_array, preamble, fs, tau_true)
% 功能：阵元时延标定——估计各阵元相对于参考阵元的时延
% 版本：V1.0.0
% 输入：
%   R_array  - 多通道接收信号 (MxN)
%   preamble - 已知前导码 (1xL)
%   fs       - 采样率 (Hz)
%   tau_true - 真实时延（可选，用于计算标定误差）
% 输出：
%   tau_est   - 估计的各阵元时延 (1xM 秒，第1阵元=0)
%   tau_error - 标定误差 (1xM 秒，需提供tau_true)

%% ========== 参数校验 ========== %%
if isempty(R_array), error('多通道信号不能为空！'); end
[M, ~] = size(R_array);

%% ========== 互相关估计时延 ========== %%
tau_est = zeros(1, M);

% 以第1阵元为参考
ref_corr = xcorr(R_array(1,:), preamble);
[~, ref_peak] = max(abs(ref_corr));

for m = 2:M
    corr_m = xcorr(R_array(m,:), preamble);
    [~, peak_m] = max(abs(corr_m));

    % 时延差（采样点）→秒
    delay_samples = peak_m - ref_peak;
    tau_est(m) = delay_samples / fs;
end

%% ========== 标定误差 ========== %%
if nargin >= 4 && ~isempty(tau_true)
    tau_error = tau_est - tau_true;
else
    tau_error = [];
end

end
