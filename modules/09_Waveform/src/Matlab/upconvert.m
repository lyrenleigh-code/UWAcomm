function [passband, t] = upconvert(baseband, fs, fc)
% 功能：数字上变频——将复基带信号调制到通带载波频率
% 版本：V1.0.0
% 输入：
%   baseband - 复基带信号 (1xN 复数数组)
%   fs       - 采样率 (Hz，正实数，须满足 fs >= 2*(fc + B/2))
%   fc       - 载波频率 (Hz，正实数)
% 输出：
%   passband - 通带实信号 (1xN 实数数组)
%              passband(n) = Re{baseband(n) * exp(j*2*pi*fc*t(n))}
%   t        - 时间轴 (1xN 数组，单位：秒)
%
% 备注：
%   - 上变频：s(t) = Re{x(t) * exp(j*2*pi*fc*t)}
%            = I(t)*cos(2*pi*fc*t) - Q(t)*sin(2*pi*fc*t)
%   - I(t) = real(baseband), Q(t) = imag(baseband)
%   - 采样率须满足Nyquist条件：fs >= 2*(fc + 信号带宽/2)

%% ========== 1. 入参解析 ========== %%
baseband = baseband(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(baseband), error('基带信号不能为空！'); end
if fs <= 0, error('采样率必须为正数！'); end
if fc <= 0, error('载波频率必须为正数！'); end
if fc >= fs/2
    warning('载波频率(%.1fHz)接近或超过Nyquist频率(%.1fHz)，可能产生混叠！', fc, fs/2);
end

%% ========== 3. 生成时间轴 ========== %%
N = length(baseband);
t = (0:N-1) / fs;

%% ========== 4. 上变频 ========== %%
I = real(baseband);
Q = imag(baseband);
carrier_cos = cos(2*pi*fc*t);
carrier_sin = sin(2*pi*fc*t);

passband = I .* carrier_cos - Q .* carrier_sin;

end
