function [waveform, t, freqs] = gen_fsk_waveform(freq_indices, M, f0, freq_spacing, fs, sym_duration)
% 功能：FSK波形生成——将频率索引转为实际正弦波形
% 版本：V1.0.0
% 输入：
%   freq_indices - 频率索引序列 (1xL 数组，取值 0 ~ M-1)
%                  由 mfsk_modulate 或 fh_spread 产生
%   M            - 频率数 (正整数)
%   f0           - 最低频率 (Hz，默认 1000)
%   freq_spacing - 频率间隔 (Hz，默认 100)
%                  第k个频率 = f0 + k * freq_spacing, k=0,...,M-1
%   fs           - 采样率 (Hz，默认 8000)
%   sym_duration - 每符号持续时间 (秒，默认 0.01)
% 输出：
%   waveform - FSK时域波形 (1xN 实数数组)
%   t        - 时间轴 (1xN 数组，单位：秒)
%   freqs    - M个频率值 (1xM 数组，Hz)
%
% 备注：
%   - 每个符号对应一个正弦信号段：cos(2*pi*f_k*t)
%   - 相位在符号边界连续（连续相位FSK, CPFSK）
%   - 正交条件：freq_spacing >= 1/sym_duration

%% ========== 1. 入参解析与初始化 ========== %%
if nargin < 6 || isempty(sym_duration), sym_duration = 0.01; end
if nargin < 5 || isempty(fs), fs = 8000; end
if nargin < 4 || isempty(freq_spacing), freq_spacing = 100; end
if nargin < 3 || isempty(f0), f0 = 1000; end
freq_indices = freq_indices(:).';

%% ========== 2. 参数校验 ========== %%
if isempty(freq_indices), error('频率索引不能为空！'); end
if any(freq_indices < 0) || any(freq_indices >= M)
    error('频率索引必须在 [0, %d] 范围内！', M-1);
end
if fs <= 0, error('采样率必须为正数！'); end
if sym_duration <= 0, error('符号持续时间必须为正数！'); end
max_freq = f0 + (M-1)*freq_spacing;
if max_freq >= fs/2
    warning('最高频率(%.1fHz)接近Nyquist频率(%.1fHz)！', max_freq, fs/2);
end

%% ========== 3. 频率表 ========== %%
freqs = f0 + (0:M-1) * freq_spacing;

%% ========== 4. 生成波形 ========== %%
samples_per_sym = round(sym_duration * fs);
num_symbols = length(freq_indices);
total_samples = num_symbols * samples_per_sym;

waveform = zeros(1, total_samples);
t = (0:total_samples-1) / fs;

phase = 0;                             % 连续相位
for s = 1:num_symbols
    f_k = freqs(freq_indices(s) + 1);
    idx_start = (s-1)*samples_per_sym + 1;
    idx_end = s * samples_per_sym;
    t_local = (0:samples_per_sym-1) / fs;

    waveform(idx_start:idx_end) = cos(2*pi*f_k*t_local + phase);

    % 更新相位保证连续性
    phase = phase + 2*pi*f_k*samples_per_sym/fs;
    phase = mod(phase, 2*pi);
end

end
