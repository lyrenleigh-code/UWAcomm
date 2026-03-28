function y_resampled = comp_resample_farrow(y, alpha_est, fs)
% 功能：Farrow滤波器重采样——可变分数延迟实现多普勒补偿
% 版本：V1.0.0
% 输入：
%   y, alpha_est, fs（同comp_resample_spline）
% 输出：
%   y_resampled - 重采样后信号 (1xN)
%
% 备注：
%   - Farrow结构：用多项式系数实现任意分数延迟
%   - 三阶Lagrange插值核，支持连续可变延迟
%   - 计算量固定（不依赖FFT），适合实时处理
%   - 每个输出样本只需4次乘+3次加

%% ========== 参数校验 ========== %%
if isempty(y), error('输入信号不能为空！'); end
y = y(:).';
N = length(y);

%% ========== Farrow重采样 ========== %%
% 累积重采样比
ratio = 1 + alpha_est;

y_resampled = zeros(1, N);
y_padded = [0, 0, y, 0, 0];           % 两端补零防越界
offset = 2;                           % padding偏移

% 逐样本计算新采样位置的分数延迟
for n = 1:N
    % 目标采样时刻（在原始采样格点上的浮点位置）
    pos = n * ratio;
    int_pos = floor(pos);
    frac = pos - int_pos;

    % Farrow三阶Lagrange插值
    idx = int_pos + offset;
    if idx >= 2 && idx <= length(y_padded) - 2
        x0 = y_padded(idx - 1);
        x1 = y_padded(idx);
        x2 = y_padded(idx + 1);
        x3 = y_padded(idx + 2);

        % 三阶Lagrange多项式系数
        c0 = x1;
        c1 = -x0/3 - x1/2 + x2 - x3/6;
        c2 = x0/2 - x1 + x2/2;
        c3 = -x0/6 + x1/2 - x2/2 + x3/6;

        y_resampled(n) = ((c3 * frac + c2) * frac + c1) * frac + c0;
    elseif idx >= 1 && idx <= length(y_padded)
        y_resampled(n) = y_padded(idx);
    end
end

end
