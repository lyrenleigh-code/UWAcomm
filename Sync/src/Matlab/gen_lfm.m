function [signal, t] = gen_lfm(fs, duration, f_start, f_end, amplitude)
% 功能：生成LFM（线性调频）信号
% 版本：V1.0.0
% 输入：
%   fs        - 采样率 (Hz)
%   duration  - 信号持续时间 (秒)
%   f_start   - 起始频率 (Hz)
%   f_end     - 终止频率 (Hz)
%   amplitude - 信号幅度 (默认 1)
% 输出：
%   signal - LFM时域波形 (1xN 实数数组)
%   t      - 时间轴 (1xN，单位：秒)
%
% 备注：
%   - 瞬时频率从 f_start 线性扫到 f_end
%   - 带宽 B = |f_end - f_start|
%   - 时宽带宽积 TB = duration * B，决定匹配滤波增益
%   - 上扫频：f_start < f_end；下扫频：f_start > f_end

%% ========== 1. 入参解析 ========== %%
if nargin < 5 || isempty(amplitude), amplitude = 1; end

%% ========== 2. 参数校验 ========== %%
if fs <= 0, error('采样率必须为正数！'); end
if duration <= 0, error('持续时间必须为正数！'); end

%% ========== 3. 生成LFM信号 ========== %%
N = round(fs * duration);
t = (0:N-1) / fs;

chirp_rate = (f_end - f_start) / duration;  % 调频斜率 (Hz/s)
phase = 2*pi * (f_start * t + 0.5 * chirp_rate * t.^2);
signal = amplitude * cos(phase);

end
