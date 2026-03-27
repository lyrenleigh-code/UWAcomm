function [clipped, clip_ratio] = papr_clip(signal, target_papr_db, method)
% 功能：PAPR抑制——限幅或选择性映射降低峰均功率比
% 版本：V1.0.0
% 输入：
%   signal         - 时域OFDM/OTFS信号 (1xN 复数数组)
%   target_papr_db - 目标PAPR上限 (dB，默认 6)
%   method         - 抑制方法 (字符串，默认 'clip')
%                    'clip'    : 硬限幅（超过阈值的样本截断到阈值）
%                    'clip_filter': 限幅+滤波（限幅后低通滤波减少带外辐射）
%                    'scale'   : 幅度缩放（保持波形形状，仅缩放峰值）
% 输出：
%   clipped    - 限幅后信号 (1xN)
%   clip_ratio - 被限幅样本比例 (0~1)
%
% 备注：
%   - 硬限幅简单有效但引入非线性失真和带外辐射
%   - clip_filter在限幅后用低通滤波器平滑，减少失真
%   - PAPR抑制存在BER性能与PAPR的折中

%% ========== 1. 入参解析 ========== %%
if nargin < 3 || isempty(method), method = 'clip'; end
if nargin < 2 || isempty(target_papr_db), target_papr_db = 6; end
signal = signal(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(signal), error('输入信号不能为空！'); end

%% ========== 3. 计算限幅阈值 ========== %%
avg_power = mean(abs(signal).^2);
threshold = sqrt(avg_power * 10^(target_papr_db/10));

%% ========== 4. PAPR抑制 ========== %%
amplitude = abs(signal);
exceed_mask = amplitude > threshold;
clip_ratio = sum(exceed_mask) / length(signal);

switch method
    case 'clip'
        % 硬限幅：保持相位，幅度截断
        clipped = signal;
        clipped(exceed_mask) = threshold * exp(1j * angle(signal(exceed_mask)));

    case 'clip_filter'
        % 限幅+滤波
        clipped = signal;
        clipped(exceed_mask) = threshold * exp(1j * angle(signal(exceed_mask)));
        % 简易低通平滑（3阶移动平均）
        kernel = ones(1, 3) / 3;
        clipped = conv(clipped, kernel, 'same');

    case 'scale'
        % 逐样本幅度缩放（软限幅）
        scale_factor = min(threshold ./ max(amplitude, 1e-30), 1);
        clipped = signal .* scale_factor;

    otherwise
        error('不支持的方法: %s！支持 clip/clip_filter/scale', method);
end

end
