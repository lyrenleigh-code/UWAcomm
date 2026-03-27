function plot_sync_spectrogram(signal, fs, title_str)
% 功能：同步信号时频谱图可视化（适合LFM/HFM等调频信号）
% 版本：V1.0.0
% 输入：
%   signal    - 时域信号 (1xN)
%   fs        - 采样率 (Hz，默认 48000)
%   title_str - 图标题 (默认 'Sync Signal')

if nargin < 3 || isempty(title_str), title_str = 'Sync Signal'; end
if nargin < 2 || isempty(fs), fs = 48000; end
signal = signal(:).';
N = length(signal);

figure('Name', title_str, 'NumberTitle', 'off', 'Position', [80, 80, 1000, 700]);

% 时域波形
subplot(2,2,1);
t = (0:N-1) / fs * 1000;
plot(t, real(signal), 'b', 'LineWidth', 0.8);
xlabel('时间 (ms)'); ylabel('幅度');
title('时域波形'); grid on;

% 频谱
subplot(2,2,2);
f = (-N/2:N/2-1) * fs / N / 1000;
S = fftshift(abs(fft(signal)));
plot(f, 20*log10(S/max(S) + 1e-10), 'r', 'LineWidth', 1);
xlabel('频率 (kHz)'); ylabel('幅度 (dB)');
title('频谱'); grid on; ylim([-60, 5]);

% 时频谱图（短时傅里叶变换）
subplot(2,2,[3,4]);
win_len = min(128, floor(N/4));
noverlap = floor(win_len * 0.75);
nfft = max(256, 2^nextpow2(win_len));
spectrogram(signal, hamming(win_len), noverlap, nfft, fs, 'yaxis');
title('时频谱图 (STFT)');
colorbar; colormap('jet');

sgtitle(title_str);

end
