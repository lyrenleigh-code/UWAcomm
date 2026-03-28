function [decisions, diff_energy] = det_ded(corr_values)
% 功能：差分能量检测器(DED)——基于差分相关的能量判决，更抗快速相位波动
% 版本：V1.0.0
% 输入：
%   corr_values - 连续符号的相关值序列 (1xN 复数数组，由dsss_despread产生)
%                 要求差分编码：相邻符号相位差承载信息
% 输出：
%   decisions   - 能量检测判决结果 (1x(N-2) 数组，+1/-1)
%   diff_energy - 差分能量输出 (1x(N-2) 实数数组)
%
% 备注：
%   - DED原理：利用两组差分相关的能量差做判决
%     E1(n) = |corr(n)*conj(corr(n-1)) + corr(n-1)*conj(corr(n-2))|^2
%     E2(n) = |corr(n)*conj(corr(n-1)) - corr(n-1)*conj(corr(n-2))|^2
%     decision = sign(E1 - E2)
%   - 相比DCD，DED利用更多观测量，在快速相位波动下更鲁棒
%   - 需要至少3个连续符号，输出长度 = N-2
%   - 性能损失约 2-4 dB，但可工作于相干检测完全失效的场景

%% ========== 1. 参数校验 ========== %%
if isempty(corr_values)
    error('相关值序列不能为空！');
end
if length(corr_values) < 3
    error('DED至少需要3个符号的相关值！');
end

corr_values = corr_values(:).';

%% ========== 2. 差分能量计算 ========== %%
N = length(corr_values);

% 两组相邻差分相关
d1 = corr_values(2:N) .* conj(corr_values(1:N-1));      % diff at (n, n-1)
d2 = corr_values(1:N-1) .* conj([0, corr_values(1:N-2)]); % diff at (n-1, n-2)

% 对齐：d1(2:end) 和 d2(2:end) 对应相同的时间窗
d1_aligned = d1(2:end);               % n = 3,...,N
d2_aligned = d2(2:end);               % n-1 对应 n-2

% 能量差
E_sum  = abs(d1_aligned + d2_aligned).^2;
E_diff = abs(d1_aligned - d2_aligned).^2;
diff_energy = E_sum - E_diff;

%% ========== 3. 判决 ========== %%
decisions = sign(diff_energy);
decisions(decisions == 0) = 1;

end
