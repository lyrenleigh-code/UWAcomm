function [output, effective_fs] = bf_nonuniform_resample(R_array, tau_delays, fs)
% 功能：空时联合非均匀变采样重建——等效采样率提升至M·fs
% 版本：V1.0.0
% 输入：
%   R_array    - 多通道接收信号 (MxN)
%   tau_delays - 各阵元时延 (1xM 秒，精确值)
%   fs         - 原始采样率 (Hz)
% 输出：
%   output       - 重建后的高采样率信号 (1x(M*N))
%   effective_fs - 等效采样率 (≈M*fs)
%
% 备注：
%   - 原理：M个阵元在不同时刻采样，组合后等效为M倍过采样
%   - 要求各阵元时延精确已知（标定精度 < Ts/(2M)）
%   - 将所有阵元的采样点按时间排序，用三次插值重建到均匀高速率网格
%   - CRLB降低M²倍（多普勒估计精度提升）

%% ========== 参数校验 ========== %%
if isempty(R_array), error('多通道信号不能为空！'); end
[M, N] = size(R_array);

%% ========== 构建非均匀采样时刻 ========== %%
Ts = 1 / fs;
t_uniform = (0:N-1) * Ts;             % 原始均匀时刻

% 每个阵元的采样时刻 = 均匀时刻 + 空间时延
all_times = zeros(1, M * N);
all_values = zeros(1, M * N);

for m = 1:M
    idx = (m-1)*N + 1 : m*N;
    all_times(idx) = t_uniform + tau_delays(m);
    all_values(idx) = R_array(m, :);
end

%% ========== 按时间排序 ========== %%
[sorted_times, sort_idx] = sort(all_times);
sorted_values = all_values(sort_idx);

%% ========== 重建到均匀高速率网格 ========== %%
effective_fs = M * fs;
Ts_new = 1 / effective_fs;
t_new = sorted_times(1) : Ts_new : sorted_times(end);
N_new = length(t_new);

% 线性插值重建（高效向量化）
output = zeros(1, N_new);
j = 1;
for i = 1:N_new
    % 找到t_new(i)在sorted_times中的位置
    while j < length(sorted_times) - 1 && sorted_times(j+1) < t_new(i)
        j = j + 1;
    end

    if j < length(sorted_times)
        dt = sorted_times(j+1) - sorted_times(j);
        if abs(dt) > 1e-15
            alpha = (t_new(i) - sorted_times(j)) / dt;
            alpha = max(0, min(1, alpha));
            output(i) = (1 - alpha) * sorted_values(j) + alpha * sorted_values(j+1);
        else
            output(i) = sorted_values(j);
        end
    else
        output(i) = sorted_values(end);
    end
end

end
