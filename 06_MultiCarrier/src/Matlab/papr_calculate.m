function [papr_db, peak_power, avg_power] = papr_calculate(signal)
% 功能：计算信号的峰均功率比(PAPR)
% 版本：V1.0.0
% 输入：
%   signal - 时域信号 (1xN 复数/实数数组)
% 输出：
%   papr_db    - PAPR值 (dB)
%   peak_power - 峰值功率
%   avg_power  - 平均功率
%
% 备注：
%   - PAPR = max(|s(t)|^2) / mean(|s(t)|^2)
%   - OFDM典型PAPR约 8~13 dB
%   - 单载波PAPR约 0~3 dB
%   - OTFS PAPR介于两者之间

%% ========== 1. 参数校验 ========== %%
if isempty(signal), error('输入信号不能为空！'); end
signal = signal(:).';

%% ========== 2. 计算PAPR ========== %%
power_inst = abs(signal).^2;
peak_power = max(power_inst);
avg_power = mean(power_inst);

if avg_power < 1e-30
    papr_db = 0;
else
    papr_db = 10 * log10(peak_power / avg_power);
end

end
