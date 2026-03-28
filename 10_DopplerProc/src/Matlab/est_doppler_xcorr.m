function [alpha_est, alpha_coarse, tau_est] = est_doppler_xcorr(r, x_pilot, T_v, fs, fc, alpha_bound)
% 功能：复自相关幅相联合法多普勒估计（SC-FDE/SC-TDE推荐）
% 版本：V1.0.0
% 输入：
%   r           - 接收信号 (1xN，含前导/后导)
%   x_pilot     - 测速导频序列 (1xL，chirp或m序列)
%   T_v         - 前后测速序列发送时间间隔 (秒)
%   fs          - 采样率 (Hz)
%   fc          - 载频 (Hz)
%   alpha_bound - 预期最大|α| (默认 0.02)
% 输出：
%   alpha_est    - 精细α估计（幅相联合+解模糊）
%   alpha_coarse - 粗α估计（仅幅度）
%   tau_est      - 帧到达时延 (秒)
%
% 备注：
%   - 粗估计（幅度）：两个峰值位置差Δn，α_coarse = (Δn/fs - T_v)/T_v
%   - 精细估计（相位）：α_phase = angle(R2·R1*) / (2π·fc·T_v)
%   - 解模糊：选与α_coarse最近的相位估计值

%% ========== 入参解析 ========== %%
if nargin < 6 || isempty(alpha_bound), alpha_bound = 0.02; end
r = r(:).'; x_pilot = x_pilot(:).';
L = length(x_pilot);

%% ========== 参数校验 ========== %%
if isempty(r), error('接收信号不能为空！'); end
if isempty(x_pilot), error('导频序列不能为空！'); end

%% ========== 第一个测速序列互相关 ========== %%
corr1 = abs(xcorr(r, x_pilot));
[~, idx1_raw] = max(corr1);
idx1 = idx1_raw - length(x_pilot) + 1;  % 修正xcorr偏移

%% ========== 第二个测速序列搜索（在T_v附近） ========== %%
expected_offset = round(T_v * fs);
search_margin = round(alpha_bound * T_v * fs) + 10;
search_start = max(1, idx1 + expected_offset - search_margin);
search_end = min(length(r) - L, idx1 + expected_offset + search_margin);

corr2_seg = zeros(1, search_end - search_start + 1);
for ii = search_start:search_end
    if ii + L - 1 <= length(r)
        corr2_seg(ii - search_start + 1) = abs(sum(r(ii:ii+L-1) .* conj(x_pilot)))^2;
    end
end
[~, local_idx2] = max(corr2_seg);
idx2 = search_start + local_idx2 - 1;

%% ========== 粗估计（幅度法） ========== %%
T_v_rx = (idx2 - idx1) / fs;
alpha_coarse = (T_v_rx - T_v) / T_v;

%% ========== 精细估计（相位法） ========== %%
R1 = sum(r(max(1,idx1) : min(length(r),idx1+L-1)) .* conj(x_pilot(1:min(L, length(r)-idx1+1))));
R2 = sum(r(max(1,idx2) : min(length(r),idx2+L-1)) .* conj(x_pilot(1:min(L, length(r)-idx2+1))));
phase_diff = angle(R2 * conj(R1));
alpha_phase = phase_diff / (2*pi*fc*T_v);

%% ========== 解模糊 ========== %%
k_unwrap = round((alpha_coarse - alpha_phase) * fc * T_v);
alpha_est = alpha_phase + k_unwrap / (fc * T_v);

%% ========== 帧时延 ========== %%
tau_est = (idx1 - 1) / fs;

end
