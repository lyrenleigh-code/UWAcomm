function [alpha_est, freq_est, spectrum] = est_doppler_zoomfft(r, preamble, fs, fc, zoom_factor, freq_range)
% 功能：Zoom-FFT频谱细化法多普勒估计
% 版本：V1.0.0
% 输入：
%   r           - 接收信号 (1xN)
%   preamble    - 已知前导码 (1xL)
%   fs          - 采样率 (Hz)
%   fc          - 载频 (Hz)
%   zoom_factor - 频率细化倍数 (默认 16)
%   freq_range  - 搜索频率范围 [f_min, f_max] (Hz，默认 fc附近)
% 输出：
%   alpha_est - 多普勒因子估计
%   freq_est  - 估计的接收频率 (Hz)
%   spectrum  - Zoom-FFT频谱
%
% 备注：
%   - 原理：对前导码做匹配滤波后，在载频附近做高分辨率FFT
%   - α = (freq_est - fc) / fc
%   - Zoom-FFT通过频移+低通+降采样+FFT实现频率细化
%   - 分辨率提高zoom_factor倍，但只覆盖局部频带

%% ========== 入参解析 ========== %%
if nargin < 6 || isempty(freq_range)
    bw = fs * 0.02;                    % 默认搜索±2%带宽
    freq_range = [fc - bw, fc + bw];
end
if nargin < 5 || isempty(zoom_factor), zoom_factor = 16; end
r = r(:).'; preamble = preamble(:).';

%% ========== 参数校验 ========== %%
if isempty(r), error('接收信号不能为空！'); end

%% ========== 匹配滤波 ========== %%
matched = xcorr(r, preamble);
[~, peak_idx] = max(abs(matched));
% 截取峰值附近的信号段
seg_len = min(length(preamble) * 4, length(r));
seg_start = max(1, peak_idx - length(preamble) - seg_len/2);
seg_end = min(length(matched), seg_start + seg_len - 1);
sig_seg = matched(seg_start:seg_end);

%% ========== Zoom-FFT ========== %%
N_seg = length(sig_seg);
f_center = mean(freq_range);
f_bw = diff(freq_range);

% 频移到基带
t_seg = (0:N_seg-1) / fs;
sig_shifted = sig_seg .* exp(-1j * 2 * pi * f_center * t_seg);

% 低通滤波
lp_order = min(32, floor(N_seg/4)*2);
if lp_order >= 2
    Wn = min(f_bw / fs, 0.99);
    b_lp = fir1(lp_order, Wn);
    sig_filtered = filter(b_lp, 1, sig_shifted);
else
    sig_filtered = sig_shifted;
end

% 降采样
dec_factor = max(1, floor(fs / (f_bw * 2)));
sig_dec = sig_filtered(1:dec_factor:end);

% 高分辨率FFT
N_fft = length(sig_dec) * zoom_factor;
S = fftshift(abs(fft(sig_dec, N_fft)));
fs_dec = fs / dec_factor;
f_axis = f_center + (-N_fft/2:N_fft/2-1) * fs_dec / N_fft;

%% ========== 找峰值频率 ========== %%
% 限制在搜索范围内
valid = f_axis >= freq_range(1) & f_axis <= freq_range(2);
S_valid = S;
S_valid(~valid) = 0;
[~, peak_f_idx] = max(S_valid);
freq_est = f_axis(peak_f_idx);

%% ========== 计算α ========== %%
alpha_est = (freq_est - f_center) / fc;  % 近似

spectrum = S;

end
