function plot_burst_scatter(error_before, error_after, title_str)
% 功能：突发错误打散效果可视化——交织前后错误位置分布对比
% 版本：V1.0.0
% 输入：
%   error_before - 交织前的错误位置 (1xN 逻辑/0-1数组，1=错误)
%   error_after  - 交织后的错误位置 (1xN 逻辑/0-1数组)
%   title_str    - 图标题 (默认 'Burst Error Scatter')

if nargin < 3 || isempty(title_str), title_str = 'Burst Error Scatter'; end

N = length(error_before);
figure('Name', title_str, 'NumberTitle', 'off', 'Position', [80, 80, 900, 450]);

% 交织前
subplot(2,1,1);
stem(find(error_before), ones(1, sum(error_before)), 'r|', 'MarkerSize', 4, 'LineWidth', 1.2);
xlabel('比特位置'); ylabel('错误');
title(sprintf('交织前（%d个错误，最大连续=%d）', sum(error_before), max_consecutive(error_before)));
xlim([1, N]); ylim([0, 1.5]); grid on;

% 交织后
subplot(2,1,2);
stem(find(error_after), ones(1, sum(error_after)), 'b|', 'MarkerSize', 4, 'LineWidth', 1.2);
xlabel('比特位置'); ylabel('错误');
title(sprintf('交织后（%d个错误，最大连续=%d）', sum(error_after), max_consecutive(error_after)));
xlim([1, N]); ylim([0, 1.5]); grid on;

sgtitle(title_str);

end

% --------------- 辅助函数：最大连续1的长度 --------------- %
function maxlen = max_consecutive(x)
x = x(:).';
d = diff([0, x, 0]);
starts = find(d == 1);
ends = find(d == -1);
if isempty(starts)
    maxlen = 0;
else
    maxlen = max(ends - starts);
end
end
