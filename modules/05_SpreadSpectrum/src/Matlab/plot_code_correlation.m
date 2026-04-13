function plot_code_correlation(codes, code_names, code_type)
% 功能：扩频码自相关和互相关可视化
% 版本：V1.0.0
% 输入：
%   codes      - 扩频码集合 (KxL 矩阵，每行一个码，值为±1)
%   code_names - 码名称 (1xK cell数组，可选)
%   code_type  - 标题前缀 (字符串，默认 'Spreading Code')

if nargin < 3 || isempty(code_type), code_type = 'Spreading Code'; end
[K, L] = size(codes);
if nargin < 2 || isempty(code_names)
    code_names = arrayfun(@(k) sprintf('Code %d', k), 1:K, 'UniformOutput', false);
end

figure('Name', [code_type ' Correlation'], 'NumberTitle', 'off', ...
       'Position', [80, 80, 1000, 700]);

% 自相关
subplot(2,1,1);
hold on;
colors = lines(K);
for k = 1:K
    [acorr, lags] = xcorr(codes(k,:), 'coeff');
    plot(lags, acorr, 'Color', colors(k,:), 'LineWidth', 1.5, 'DisplayName', code_names{k});
end
hold off;
xlabel('延迟 (码片)'); ylabel('归一化自相关');
title([code_type ' — 自相关']); legend('Location','best'); grid on;
ylim([-0.3, 1.1]);

% 互相关（两两配对）
if K >= 2
    subplot(2,1,2);
    hold on;
    pair_idx = 0;
    for i = 1:min(K,4)
        for j = i+1:min(K,4)
            pair_idx = pair_idx + 1;
            [xcorr_val, lags] = xcorr(codes(i,:), codes(j,:), 'coeff');
            plot(lags, xcorr_val, 'LineWidth', 1.2, ...
                 'DisplayName', sprintf('%s vs %s', code_names{i}, code_names{j}));
        end
    end
    hold off;
    xlabel('延迟 (码片)'); ylabel('归一化互相关');
    title([code_type ' — 互相关']); legend('Location','best'); grid on;
    ylim([-0.5, 0.5]);
else
    subplot(2,1,2);
    text(0.5, 0.5, '需要至少2个码才能显示互相关', 'HorizontalAlignment', 'center');
end

sgtitle(sprintf('%s 相关性分析 (码长=%d)', code_type, L));

end
