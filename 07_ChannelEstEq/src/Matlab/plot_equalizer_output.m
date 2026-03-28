function plot_equalizer_output(x_true, x_rx_before, x_eq_list, eq_names, title_str)
% 功能：均衡前后对比可视化——星座图+误差分布+BER对比
% 版本：V2.0.0
% 输入：
%   x_true       - 发送符号 (1xN 复数)
%   x_rx_before  - 均衡前接收符号 (1xN 复数，经信道畸变的原始信号)
%   x_eq_list    - 均衡后符号cell数组 {x_eq1, x_eq2, ...}
%   eq_names     - 均衡器名称 {'DFE','MMSE-FDE',...}
%   title_str    - 标题

if nargin < 5, title_str = 'Equalization Result'; end
K = length(x_eq_list);
N = length(x_true);

% 星座参考点
constellation = unique([real(x_true) + 1j*imag(x_true)]);
if length(constellation) > 16, constellation = []; end

num_cols = K + 1;                      % 均衡前 + K个均衡后
figure('Name', title_str, 'NumberTitle', 'off', ...
       'Position', [30, 30, 280*num_cols, 700]);

%% 第一行：星座图对比

% 均衡前星座图
subplot(3, num_cols, 1);
plot(real(x_rx_before), imag(x_rx_before), '.', 'Color', [0.7,0.7,0.7], 'MarkerSize', 4);
hold on;
if ~isempty(constellation)
    plot(real(constellation), imag(constellation), 'r+', 'MarkerSize', 10, 'LineWidth', 2);
end
hold off;
axis equal; grid on;
title('均衡前（信道畸变）', 'Color', 'r');
xlabel('I'); ylabel('Q');
max_r = max(abs([real(x_rx_before), imag(x_rx_before)])) * 1.3;
if max_r > 0, xlim([-max_r, max_r]); ylim([-max_r, max_r]); end

% 各均衡器星座图
for k = 1:K
    subplot(3, num_cols, 1 + k);
    x_k = x_eq_list{k}(:).';
    n_k = min(length(x_k), N);
    plot(real(x_k(1:n_k)), imag(x_k(1:n_k)), '.', 'Color', [0.2,0.5,0.8], 'MarkerSize', 4);
    hold on;
    if ~isempty(constellation)
        plot(real(constellation), imag(constellation), 'r+', 'MarkerSize', 10, 'LineWidth', 2);
    end
    hold off;
    axis equal; grid on;
    title(sprintf('均衡后: %s', eq_names{k}), 'Color', [0,0.5,0]);
    xlabel('I'); ylabel('Q');
    if max_r > 0, xlim([-max_r, max_r]); ylim([-max_r, max_r]); end
end

%% 第二行：误差幅度对比

% 均衡前误差
subplot(3, num_cols, num_cols + 1);
err_before = abs(x_rx_before(1:N) - x_true);
plot(err_before, 'r', 'LineWidth', 0.5);
xlabel('符号索引'); ylabel('|误差|');
title(sprintf('均衡前 MSE=%.3f', mean(err_before.^2)));
grid on;

% 各均衡器误差
for k = 1:K
    subplot(3, num_cols, num_cols + 1 + k);
    x_k = x_eq_list{k}(:).';
    n_k = min(length(x_k), N);
    err_k = abs(x_k(1:n_k) - x_true(1:n_k));
    plot(err_k, 'Color', [0,0.5,0], 'LineWidth', 0.5);
    xlabel('符号索引'); ylabel('|误差|');
    title(sprintf('%s MSE=%.3f', eq_names{k}, mean(err_k.^2)));
    grid on;
end

%% 第三行：BER对比柱状图

subplot(3, num_cols, 2*num_cols + 1 : 3*num_cols);

% 计算BER（QPSK最近邻判决）
ber_list = zeros(1, K + 1);
labels = ['均衡前', eq_names];

% 均衡前BER
dec_before = qpsk_nearest(x_rx_before(1:N));
dec_true = qpsk_nearest(x_true);
ber_list(1) = sum(dec_before ~= dec_true) / N;

% 各均衡器BER
for k = 1:K
    x_k = x_eq_list{k}(:).';
    n_k = min(length(x_k), N);
    dec_k = qpsk_nearest(x_k(1:n_k));
    ber_list(k+1) = sum(dec_k ~= dec_true(1:n_k)) / n_k;
end

bar_colors = [0.9,0.3,0.3; repmat([0.3,0.6,0.9], K, 1)];
b = bar(ber_list);
b.FaceColor = 'flat';
for idx = 1:K+1
    b.CData(idx,:) = bar_colors(min(idx, size(bar_colors,1)), :);
end
set(gca, 'XTickLabel', labels, 'FontSize', 9);
ylabel('BER');
title('误码率对比（均衡前 vs 均衡后）');
grid on;
for idx = 1:K+1
    if ber_list(idx) > 0
        text(idx, ber_list(idx) + 0.01, sprintf('%.1f%%', ber_list(idx)*100), ...
             'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
    else
        text(idx, 0.01, '0%', 'HorizontalAlignment', 'center', 'FontSize', 9);
    end
end

sgtitle(title_str);

end

% --------------- QPSK最近邻判决 --------------- %
function d = qpsk_nearest(x)
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
d = zeros(size(x));
for n = 1:length(x)
    [~, idx] = min(abs(x(n) - constellation));
    d(n) = constellation(idx);
end
end
