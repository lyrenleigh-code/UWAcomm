function [baseband, t] = downconvert(passband, fs, fc, lpf_bandwidth)
% 功能：数字下变频——将通带信号解调回复基带
% 版本：V1.0.0
% 输入：
%   passband      - 通带实信号 (1xN 实数数组)
%   fs            - 采样率 (Hz，须与发端一致)
%   fc            - 载波频率 (Hz，须与发端一致)
%   lpf_bandwidth - 低通滤波器截止频率 (Hz，默认 fc/2)
%                   用于滤除二倍频分量
% 输出：
%   baseband - 复基带信号 (1xN 复数数组)
%   t        - 时间轴 (1xN 数组，单位：秒)
%
% 备注：
%   - 下变频：I(t) = LPF{s(t)*2*cos(2*pi*fc*t)}
%            Q(t) = LPF{s(t)*(-2*sin(2*pi*fc*t))}
%   - 乘以2补偿正交混频的幅度衰减
%   - 低通滤波器去除2fc处的二倍频分量

%% ========== 1. 入参解析 ========== %%
passband = passband(:).';
if nargin < 4 || isempty(lpf_bandwidth)
    lpf_bandwidth = fc / 2;
end

%% ========== 2. 参数校验 ========== %%
if isempty(passband), error('通带信号不能为空！'); end
if fs <= 0, error('采样率必须为正数！'); end
if fc <= 0, error('载波频率必须为正数！'); end

%% ========== 3. 生成时间轴和本振信号 ========== %%
N = length(passband);
t = (0:N-1) / fs;

carrier_cos = cos(2*pi*fc*t);
carrier_sin = sin(2*pi*fc*t);

%% ========== 4. 正交混频 ========== %%
I_raw = 2 * passband .* carrier_cos;
Q_raw = -2 * passband .* carrier_sin;

%% ========== 5. 低通滤波（去除2fc分量） ========== %%
I_filt = lpf_filter(I_raw, fs, lpf_bandwidth);
Q_filt = lpf_filter(Q_raw, fs, lpf_bandwidth);

baseband = I_filt + 1j * Q_filt;

end

% --------------- 辅助函数：简易低通滤波器 --------------- %
function y = lpf_filter(x, fs, cutoff)
% LPF_FILTER FIR低通滤波器
% 输入参数：
%   x      - 输入信号
%   fs     - 采样率 (Hz)
%   cutoff - 截止频率 (Hz)

% 滤波器阶数（根据信号长度自适应）
order = min(64, floor(length(x)/4) * 2);
if order < 4, order = 4; end

% 归一化截止频率
Wn = cutoff / (fs/2);
if Wn >= 1, Wn = 0.99; end

% FIR滤波器设计
b = fir1(order, Wn);
y = filtfilt(b, 1, x);

end
