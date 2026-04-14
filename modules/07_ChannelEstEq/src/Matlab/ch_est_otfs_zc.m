function [h_dd, path_info] = ch_est_otfs_zc(Y_dd, pilot_info, N, M)
% 功能：OTFS DD域ZC序列导频信道估计
% 版本：V3.0.0 — 最小二乘反解Toeplitz系统(消除partial correlation sidelobe)
% 输入：
%   Y_dd       - 接收DD域帧 (NxM 复数)
%   pilot_info - 导频信息（由 otfs_pilot_embed mode='sequence' 生成）
%   N, M       - OTFS维度
% 输出：
%   h_dd       - DD域信道响应 (NxM，稀疏)
%   path_info  - 路径信息
%
% 原理：
%   ZC序列占据pilot行k=pk的seq_len=2*gl+1个连续列，具CAZAC特性。
%   RX侧pilot局部化 → 用线性匹配滤波（而非循环反卷积）估计信道：
%     c[dl_hat] = sum_{i=dl_hat}^{seq_len-1} Y[pk+dk, col(i)] * conj(seq[i-dl_hat])
%     h[dk, dl] = c[dl] / ((seq_len-dl) * mean(|seq|²))
%   利用ZC的CAZAC特性：旁瓣低，主瓣集中在正确延迟位置。

%% ========== 1. 参数提取 ========== %%
if ~strcmp(pilot_info.mode, 'sequence')
    error('ch_est_otfs_zc仅支持sequence模式pilot, 当前=%s', pilot_info.mode);
end

seq = pilot_info.values(:).';
seq_len = length(seq);
pilot_pos = pilot_info.positions;
pk = pilot_pos(1, 1);
pilot_cols = pilot_pos(:, 2).';
gl = (seq_len - 1) / 2;

%% ========== 2. 确定多普勒保护范围 ========== %%
gk = 2;
if isfield(pilot_info, 'guard_mask')
    gmask = pilot_info.guard_mask;
    guard_rows = find(any(gmask, 2));
    if ~isempty(guard_rows)
        dists = min(abs(guard_rows - pk), N - abs(guard_rows - pk));
        gk = max(dists);
    end
end

seq_power = mean(abs(seq).^2);

%% ========== 4. 构建Toeplitz矩阵 S (seq_len × (gl+1)) ========== %%
n_taps = gl + 1;
S = zeros(seq_len, n_taps);
for j = 0:n_taps-1
    for i = j:seq_len-1
        S(i+1, j+1) = seq(i-j+1);
    end
end
S_pinv = pinv(S);

y_cols = pilot_cols;  % seq_len 列

%% ========== 5. LS 反解各 Doppler 偏移 + 用噪声行估计噪底 ========== %%
h_dd = zeros(N, M);
delays = [];
dopplers = [];
gains = [];

% 先在 guard 外收集噪声参考（h_vec域）
noise_h_vals = [];
for dk_n = [-gk-3, -gk-2, gk+2, gk+3]
    if abs(dk_n) < N/2
        k_n = mod(pk - 1 + dk_n, N) + 1;
        y_n = Y_dd(k_n, y_cols).';  % 2gl+1 × 1
        h_n_vec = S_pinv * y_n;
        noise_h_vals = [noise_h_vals; abs(h_n_vec)];
    end
end
if isempty(noise_h_vals)
    noise_h_std = 1e-6;
else
    noise_h_std = median(noise_h_vals);
end

% 主径幅度参考
y_main = Y_dd(pk, y_cols).';
h_main_vec = S_pinv * y_main;
main_peak = max(abs(h_main_vec));
threshold = max(3.0 * noise_h_std, main_peak * 0.02);

for dk = -gk:gk
    k_row = mod(pk - 1 + dk, N) + 1;
    y_row = Y_dd(k_row, y_cols).';  % y_len × 1

    % LS估计: h_vec = pinv(S) * y_row (n_taps × 1)
    h_vec = S_pinv * y_row;

    for dl = 0:gl
        h_est = h_vec(dl+1);
        if abs(h_est) > threshold
            % pilot 中心在 pilot_cols(gl+1)=pl
            l_out = mod(pilot_cols(gl+1) - 1 + dl, M) + 1;
            h_dd(k_row, l_out) = h_est;
            delays = [delays, dl];
            dopplers = [dopplers, dk];
            gains = [gains, h_est];
        end
    end
end

%% ========== 5. 输出路径信息 ========== %%
path_info.delay_idx = delays;
path_info.doppler_idx = dopplers;
path_info.gain = gains;
path_info.num_paths = length(gains);
path_info.noise_h_std = noise_h_std;
path_info.threshold = threshold;

end
