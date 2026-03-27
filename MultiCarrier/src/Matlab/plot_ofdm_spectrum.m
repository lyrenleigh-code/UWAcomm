function plot_ofdm_spectrum(signal, fs, title_str)
% 功能：OFDM信号频谱和时域波形可视化
% 版本：V1.0.0
% 输入：
%   signal    - 时域OFDM信号 (1xN)
%   fs        - 采样率 (Hz，默认 1)
%   title_str - 图标题 (默认 'OFDM Signal')

%% ========== 入参 ========== %%
if nargin < 3 || isempty(title_str), title_str = 'OFDM Signal'; end
if nargin < 2 || isempty(fs), fs = 1; end
signal = signal(:).';
N = length(signal);

%% ========== 绘图 ========== %%
figure('Name', title_str, 'NumberTitle', 'off', 'Position', [100,100,900,600]);

% 时域波形
subplot(2,2,1);
t = (0:N-1) / fs * 1000;              % ms
plot(t, real(signal), 'b', 'LineWidth', 0.8);
xlabel('时间 (ms)'); ylabel('幅度');
title('时域波形（实部）'); grid on;

% 瞬时功率
subplot(2,2,2);
plot(t, 10*log10(abs(signal).^2 + 1e-30), 'r', 'LineWidth', 0.8);
xlabel('时间 (ms)'); ylabel('功率 (dB)');
title('瞬时功率'); grid on;

% 功率谱密度
subplot(2,2,3);
[psd, f] = periodogram(signal, [], N, fs);
plot(f/1000, 10*log10(psd + 1e-30), 'b', 'LineWidth', 1);
xlabel('频率 (kHz)'); ylabel('PSD (dB/Hz)');
title('功率谱密度'); grid on;

% PAPR CCDF
subplot(2,2,4);
papr_inst = abs(signal).^2 / mean(abs(signal).^2);
papr_db_vec = sort(10*log10(papr_inst + 1e-30));
ccdf = 1 - (1:N)/N;
plot(papr_db_vec, ccdf, 'r', 'LineWidth', 1.5);
xlabel('PAPR (dB)'); ylabel('CCDF P(PAPR > x)');
title(sprintf('PAPR分布 (峰值=%.1f dB)', max(papr_db_vec)));
set(gca, 'YScale', 'log'); grid on;

sgtitle(title_str);

end
