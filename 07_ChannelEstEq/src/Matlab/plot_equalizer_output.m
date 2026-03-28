function plot_equalizer_output(x_true, x_eq_list, eq_names, title_str)
% 功能：均衡结果可视化——星座图+BER对比
% 版本：V1.0.0
% 输入：
%   x_true     - 发送符号 (1xN 复数)
%   x_eq_list  - 均衡后符号cell数组 {x1, x2, ...}
%   eq_names   - 均衡器名称 {'DFE','MMSE-FDE',...}
%   title_str  - 标题

if nargin < 4, title_str = 'Equalizer Output'; end
K = length(x_eq_list);

num_plots = min(K, 4);
figure('Name', title_str, 'NumberTitle', 'off', ...
       'Position', [50, 50, 300*num_plots+100, 600]);

% 各均衡器星座图
for k = 1:num_plots
    subplot(2, num_plots, k);
    x_k = x_eq_list{k}(:).';
    plot(real(x_k), imag(x_k), '.', 'Color', [0.3,0.5,0.8], 'MarkerSize', 4);
    hold on;
    plot(real(x_true), imag(x_true), 'r+', 'MarkerSize', 8, 'LineWidth', 1.5);
    hold off;
    axis equal; grid on;
    title(eq_names{k}); xlabel('I'); ylabel('Q');
    max_r = max(abs([real(x_k), imag(x_k)])) * 1.3;
    xlim([-max_r, max_r]); ylim([-max_r, max_r]);
end

% BER柱状图
subplot(2, num_plots, num_plots+1:2*num_plots);
ber = zeros(1, K);
for k = 1:K
    x_k = x_eq_list{k}(:).';
    n = min(length(x_k), length(x_true));
    % BPSK BER
    dec = sign(real(x_k(1:n)));
    ref = sign(real(x_true(1:n)));
    ber(k) = sum(dec ~= ref) / n;
end
bar(ber, 'FaceColor', [0.8, 0.4, 0.2]);
set(gca, 'XTickLabel', eq_names, 'FontSize', 9);
ylabel('BER'); title('均衡后BER对比');
grid on;
for k = 1:K
    text(k, ber(k)+0.005, sprintf('%.2f%%', ber(k)*100), ...
         'HorizontalAlignment','center','FontSize',9);
end

sgtitle(title_str);
end
