function y_out = comp_resample_piecewise(y, alpha_avg, alpha_track, data_start, T_sym_samples)
% 功能：分段 Doppler 补偿——data 段每 symbol 用独立 α
% 版本：V1.0.0（2026-04-22）
% 对应 spec: 2026-04-22-dsss-symbol-doppler-tracking.md
%
% 输入：
%   y              - 1×N complex 基带信号
%   alpha_avg      - scalar，data 前段（preamble）用的均值 α
%   alpha_track    - 1×n_sym，逐符号 α 轨迹
%   data_start     - data 段起始样本索引（1-based）
%   T_sym_samples  - 每 symbol 样本数
% 输出：
%   y_out - 1×N complex，分段补偿后信号

y = y(:).';
N = length(y);
n_sym = length(alpha_track);

% 构造 piecewise query 索引
n_q = zeros(1, N);
% preamble 段用 alpha_avg 统一 resample
for n = 1:(data_start - 1)
    n_q(n) = n / (1 + alpha_avg);
end

% data 段：每 symbol 用独立 alpha_track(k)
cur_q = n_q(max(1, data_start-1)) + 1 / (1 + alpha_avg);  % 连接点
for k = 1:n_sym
    sym_start = data_start + (k-1) * T_sym_samples;
    sym_end   = min(data_start + k * T_sym_samples - 1, N);
    if sym_end < sym_start, continue; end
    dn = 1 / (1 + alpha_track(k));
    for n = sym_start:sym_end
        n_q(n) = cur_q;
        cur_q = cur_q + dn;
    end
end

% data 段之后（如 tail padding）用 alpha_track 最后值
data_total_end = data_start + n_sym * T_sym_samples - 1;
if data_total_end < N
    dn = 1 / (1 + alpha_track(end));
    for n = (data_total_end+1):N
        n_q(n) = cur_q;
        cur_q = cur_q + dn;
    end
end

% interp1 一次完成
n_q = max(1, min(n_q, N));  % clamp
y_out = interp1(1:N, y, n_q, 'spline', 0);

end
