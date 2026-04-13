function [signal, t] = gen_hfm(fs, duration, f_start, f_end, amplitude)
% 功能：生成HFM（双曲调频）信号，具有Doppler不变性
% 版本：V1.0.0
% 输入：
%   fs        - 采样率 (Hz)
%   duration  - 信号持续时间 (秒)
%   f_start   - 起始频率 (Hz，正数)
%   f_end     - 终止频率 (Hz，正数)
%   amplitude - 信号幅度 (默认 1)
% 输出：
%   signal - HFM时域波形 (1xN 实数数组)
%   t      - 时间轴 (1xN，单位：秒)
%
% 备注：
%   - 瞬时频率沿双曲线变化：f(t) = f0*f1 / (f1 - (f1-f0)*t/T)
%   - Doppler不变性：时间压缩/扩展只引起频移，不改变信号包络形状
%   - 匹配滤波输出对Doppler鲁棒，适合移动水声通信同步
%   - f_start 和 f_end 必须同号（均为正数）

%% ========== 1. 入参解析 ========== %%
if nargin < 5 || isempty(amplitude), amplitude = 1; end

%% ========== 2. 参数校验 ========== %%
if fs <= 0, error('采样率必须为正数！'); end
if duration <= 0, error('持续时间必须为正数！'); end
if f_start <= 0 || f_end <= 0, error('HFM频率必须为正数！'); end

%% ========== 3. 生成HFM信号 ========== %%
N = round(fs * duration);
t = (0:N-1) / fs;
T = duration;
f0 = f_start;
f1 = f_end;

% 双曲调频相位
% phi(t) = -2*pi*f0*f1*T/(f1-f0) * log(1 - (f1-f0)/(f1)*t/T)
if abs(f1 - f0) < 1e-6
    % 退化为单频
    phase = 2*pi*f0*t;
else
    k = f0 * f1 * T / (f1 - f0);
    phase = -2*pi * k * log(1 - (f1 - f0) / f1 * t / T);
end

signal = amplitude * cos(phase);

end
