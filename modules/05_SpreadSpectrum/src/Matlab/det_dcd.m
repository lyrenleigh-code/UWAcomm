function [decisions, diff_corr] = det_dcd(corr_values)
% 功能：差分相关检测器(DCD)——利用相邻符号相关值的差分消除载波相位影响
% 版本：V1.0.0
% 输入：
%   corr_values - 连续符号的相关值序列 (1xN 复数数组，由dsss_despread产生)
%                 要求相邻符号承载相同或差分编码的信息
% 输出：
%   decisions - 差分检测判决结果 (1x(N-1) 数组，+1/-1)
%   diff_corr - 差分相关输出 (1x(N-1) 复数数组)
%
% 备注：
%   - DCD原理：diff(n) = Re{corr(n) * conj(corr(n-1))}
%   - 载波相位 φ 在相邻符号间近似不变时，差分运算消除 e^{jφ}
%   - 适用于低载波相位波动的移动水声通信场景
%   - 差分编码：发端对数据做差分预编码，收端DCD直接恢复原始比特
%   - 性能损失约 1-3 dB（相比相干检测），但无需载波相位估计

%% ========== 1. 参数校验 ========== %%
if isempty(corr_values)
    error('相关值序列不能为空！');
end
if length(corr_values) < 2
    error('DCD至少需要2个符号的相关值！');
end

corr_values = corr_values(:).';

%% ========== 2. 差分相关 ========== %%
N = length(corr_values);
diff_corr = corr_values(2:N) .* conj(corr_values(1:N-1));

%% ========== 3. 判决 ========== %%
decisions = sign(real(diff_corr));
decisions(decisions == 0) = 1;         % 零值判为+1

end
