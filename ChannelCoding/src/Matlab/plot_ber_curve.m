function plot_ber_curve(snr_db, ber_data, legend_labels, title_str)
% 功能：BER vs SNR曲线绘制工具
% 版本：V1.0.0
% 输入：
%   snr_db        - SNR数组 (1xK dB值)
%   ber_data      - BER数据 (MxK 矩阵，每行一条曲线；或 1xK 单条曲线)
%   legend_labels - 图例标签 (1xM cell数组，可选)
%   title_str     - 图标题 (默认 'BER Performance')
%
% 示例：
%   snr = 0:2:12;
%   ber_conv = [0.15, 0.08, 0.02, 0.003, 0.0002, 0.00001, 0];
%   ber_turbo = [0.10, 0.03, 0.005, 0.0001, 0, 0, 0];
%   plot_ber_curve(snr, [ber_conv; ber_turbo], {'卷积码','Turbo码'}, 'BER对比');

if nargin < 4 || isempty(title_str), title_str = 'BER Performance'; end
if isvector(ber_data), ber_data = ber_data(:).'; end
[M, K] = size(ber_data);
if nargin < 3 || isempty(legend_labels)
    legend_labels = arrayfun(@(m) sprintf('方案%d', m), 1:M, 'UniformOutput', false);
end

figure('Name', title_str, 'NumberTitle', 'off', 'Position', [100, 100, 700, 500]);

markers = {'o-','s-','d-','^-','v-','p-','h-','*-'};
colors = lines(M);

hold on;
for m = 1:M
    ber = ber_data(m, :);
    % 将0值替换为极小值以便对数显示
    ber(ber == 0) = 1e-7;
    plot(snr_db, ber, markers{mod(m-1,8)+1}, ...
         'Color', colors(m,:), 'LineWidth', 1.8, 'MarkerSize', 7, ...
         'MarkerFaceColor', colors(m,:), 'DisplayName', legend_labels{m});
end

% BPSK理论曲线
snr_fine = linspace(min(snr_db), max(snr_db), 100);
ber_theory = 0.5 * erfc(sqrt(10.^(snr_fine/10)));
plot(snr_fine, ber_theory, 'k--', 'LineWidth', 1, 'DisplayName', 'BPSK理论');

hold off;
set(gca, 'YScale', 'log');
xlabel('E_b/N_0 (dB)'); ylabel('BER');
title(title_str);
legend('Location', 'southwest');
grid on;
ylim([1e-6, 1]);
xlim([min(snr_db)-1, max(snr_db)+1]);

end
