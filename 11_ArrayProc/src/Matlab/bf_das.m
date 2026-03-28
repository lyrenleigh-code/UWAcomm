function [output, snr_gain] = bf_das(R_array, tau_delays, fs)
% 功能：DAS（Delay-And-Sum）常规波束形成——时延对齐+相干叠加
% 版本：V1.0.0
% 输入：
%   R_array    - 多通道接收信号 (MxN)
%   tau_delays - 各阵元时延补偿量 (1xM 秒)
%   fs         - 采样率 (Hz)
% 输出：
%   output   - 波束形成后的单路信号 (1xN)
%   snr_gain - SNR提升 (dB，理论值 = 10*log10(M))
%
% 备注：
%   - DAS：每通道做时延对齐后相干求和，SNR提升约10*log10(M) dB
%   - 时延补偿用分数样本插值（Farrow方法）

%% ========== 参数校验 ========== %%
if isempty(R_array), error('多通道信号不能为空！'); end
[M, N] = size(R_array);

if nargin < 3 || isempty(fs), fs = 48000; end
if nargin < 2 || isempty(tau_delays), tau_delays = zeros(1, M); end

%% ========== 时延对齐 + 求和 ========== %%
output = zeros(1, N);

for m = 1:M
    delay_samples = tau_delays(m) * fs;

    if abs(delay_samples) < 0.01
        % 无需补偿
        aligned = R_array(m, :);
    else
        % 分数延迟补偿（用线性插值，简单高效）
        int_delay = round(delay_samples);
        frac_delay = delay_samples - int_delay;

        % 整数部分：循环移位
        aligned = circshift(R_array(m, :), [0, -int_delay]);

        % 分数部分：线性插值
        if abs(frac_delay) > 0.01 && N > 1
            aligned_shifted = circshift(aligned, [0, -1]);
            aligned = (1 - abs(frac_delay)) * aligned + abs(frac_delay) * aligned_shifted;
        end
    end

    output = output + aligned;
end

% 归一化
output = output / M;

%% ========== SNR增益 ========== %%
snr_gain = 10 * log10(M);

end
