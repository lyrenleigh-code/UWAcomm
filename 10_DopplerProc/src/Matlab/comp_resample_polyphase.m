function y_resampled = comp_resample_polyphase(y, alpha_est, fs, num_phases)
% 功能：多相滤波器重采样——低计算量多普勒补偿
% 版本：V1.0.0
% 输入：
%   y          - 接收信号 (1xN)
%   alpha_est  - 估计的多普勒因子
%   fs         - 采样率 (Hz)
%   num_phases - 多相滤波器分支数 (默认 32，越大精度越高)
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   - 原理：预计算num_phases组FIR滤波器系数，运行时只需查表+滤波
%   - 相比spline：精度略低但计算量固定，适合大数据量
%   - 相比Farrow：可用更高阶滤波器，旁瓣抑制更好
%   - 计算量 O(N * taps_per_phase)，与FFT方法相当

%% ========== 入参解析 ========== %%
if nargin < 4 || isempty(num_phases), num_phases = 32; end
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== 设计多相滤波器组 ========== %%
% 原型低通滤波器（截止频率为Nyquist）
taps_per_phase = 8;                    % 每分支抽头数
total_taps = taps_per_phase * num_phases;
h_proto = fir1(total_taps - 1, 1/num_phases) * num_phases;

% 分解为num_phases个子滤波器
poly_filters = reshape(h_proto, num_phases, taps_per_phase);

%% ========== 多相重采样 ========== %%
ratio = 1 + alpha_est;
y_resampled = zeros(1, N);

% 补零
pad = taps_per_phase;
y_padded = [zeros(1, pad), y, zeros(1, pad)];

for n = 1:N
    % 目标位置（浮点）
    pos = n * ratio;
    int_pos = floor(pos);
    frac = pos - int_pos;

    % 选择最近的多相分支
    phase_idx = round(frac * num_phases);
    if phase_idx == 0, phase_idx = 1; end
    if phase_idx > num_phases, phase_idx = num_phases; end

    % 取滤波器系数
    h_phase = poly_filters(phase_idx, :);

    % 滤波（卷积核心采样点）
    idx_start = int_pos + pad - floor(taps_per_phase/2);
    idx_end = idx_start + taps_per_phase - 1;

    if idx_start >= 1 && idx_end <= length(y_padded)
        seg = y_padded(idx_start : idx_end);
        y_resampled(n) = h_phase * seg(:);
    elseif int_pos + pad >= 1 && int_pos + pad <= length(y_padded)
        y_resampled(n) = y_padded(int_pos + pad);
    end
end

end
