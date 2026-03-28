function plot_doppler_estimation(alpha_true, alpha_est_list, est_names, comp_results, title_str)
% 功能：多普勒估计与补偿结果可视化
% 版本：V1.0.0
% 输入：
%   alpha_true     - 真实α（标量或1xN时变序列）
%   alpha_est_list - 各方法估计的α (cell数组)
%   est_names      - 方法名称 (cell数组)
%   comp_results   - 重采样结果结构体（可选）
%       .y_orig    : 原始信号
%       .y_comp    : 补偿后信号
%       .y_ref     : 参考信号（无多普勒）
%   title_str      - 标题

if nargin < 5, title_str = 'Doppler Estimation'; end
if nargin < 4, comp_results = []; end

K = length(alpha_est_list);

figure('Name', title_str, 'NumberTitle', 'off', 'Position', [50, 50, 1000, 700]);

% 估计误差柱状图
subplot(2,2,1);
errors = zeros(1, K);
for k = 1:K
    a_k = alpha_est_list{k};
    if ~isscalar(a_k), a_k = a_k(1); end  % 取第一个值（防止向量）
    if isscalar(alpha_true)
        errors(k) = abs(a_k - alpha_true);
    else
        errors(k) = abs(a_k - mean(alpha_true));
    end
end
bar(errors * 1e6);
set(gca, 'XTickLabel', est_names, 'FontSize', 9);
ylabel('|误差| (×10^{-6})');
title('估计误差对比');
grid on;
for k = 1:K
    text(k, errors(k)*1e6 + max(errors)*1e6*0.05, sprintf('%.2f', errors(k)*1e6), ...
         'HorizontalAlignment','center','FontSize',9);
end

% 估计值 vs 真实值
subplot(2,2,2);
if isscalar(alpha_true)
    alpha_t = alpha_true;
else
    alpha_t = mean(alpha_true);
end
hold on;
plot([0, K+1], [alpha_t, alpha_t]*1e3, 'k--', 'LineWidth', 1.5, 'DisplayName', '真实值');
for k = 1:K
    a_k = alpha_est_list{k};
    if ~isscalar(a_k), a_k = a_k(1); end
    plot(k, a_k*1e3, 'o', 'MarkerSize', 10, 'MarkerFaceColor', 'auto', ...
         'DisplayName', est_names{k});
end
hold off;
ylabel('\alpha \times 10^{-3}');
title('估计值 vs 真实值');
legend('Location','best','FontSize',8); grid on;
xlim([0, K+1]);

% 时变α（如果有）
subplot(2,2,3);
if ~isscalar(alpha_true) && length(alpha_true) > 1
    plot(alpha_true * 1e3, 'b', 'LineWidth', 1);
    xlabel('采样索引'); ylabel('\alpha \times 10^{-3}');
    title('时变多普勒因子');
    grid on;
else
    text(0.5, 0.5, '固定α（非时变）', 'HorizontalAlignment', 'center');
end

% 补偿效果（如果有）
subplot(2,2,4);
if ~isempty(comp_results) && isfield(comp_results, 'y_comp')
    lens = length(comp_results.y_comp);
    if isfield(comp_results, 'y_ref'), lens = min(lens, length(comp_results.y_ref)); end
    if isfield(comp_results, 'y_orig'), lens = min(lens, length(comp_results.y_orig)); end
    N_show = min(200, lens);
    hold on;
    if isfield(comp_results, 'y_ref')
        plot(real(comp_results.y_ref(1:N_show)), 'k', 'LineWidth', 1.5, 'DisplayName', '参考（无Doppler）');
    end
    if isfield(comp_results, 'y_orig')
        plot(real(comp_results.y_orig(1:N_show)), 'r--', 'LineWidth', 0.8, 'DisplayName', '补偿前');
    end
    plot(real(comp_results.y_comp(1:N_show)), 'b', 'LineWidth', 1, 'DisplayName', '补偿后');
    hold off;
    xlabel('采样索引'); ylabel('幅度');
    title('重采样补偿效果');
    legend('Location','best','FontSize',8); grid on;
else
    text(0.5, 0.5, '无补偿结果', 'HorizontalAlignment', 'center');
end

sgtitle(title_str);

end
