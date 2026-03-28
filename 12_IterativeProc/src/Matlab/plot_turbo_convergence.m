function plot_turbo_convergence(iter_results, title_str)
% 功能：Turbo均衡迭代收敛可视化——BER/MSE/星座图随迭代次数变化
% 版本：V1.0.0
% 输入：
%   iter_results - 迭代结果结构体
%       .ber_per_iter   : 1xK BER数组（每次迭代的BER）
%       .mse_per_iter   : 1xK MSE数组（每次迭代的均衡MSE）
%       .constellation  : {1xK} cell，每次迭代的均衡后符号（用于星座图）
%       .ref_symbols    : 参考符号（用于星座图参考点）
%       .scheme         : 体制名称字符串
%   title_str - 图标题

if nargin < 2, title_str = 'Turbo Equalization Convergence'; end

num_iter = length(iter_results.ber_per_iter);
has_constellation = isfield(iter_results, 'constellation') && ~isempty(iter_results.constellation);
has_mse = isfield(iter_results, 'mse_per_iter') && ~isempty(iter_results.mse_per_iter);

%% ========== 布局计算 ========== %%
if has_constellation
    num_const_show = min(num_iter, 4);  % 最多显示4次迭代的星座图
    figure('Name', title_str, 'NumberTitle', 'off', 'Position', [30, 30, 1200, 800]);

    % 第一行：BER收敛 + MSE收敛
    subplot(2, num_const_show, 1:floor(num_const_show/2));
else
    figure('Name', title_str, 'NumberTitle', 'off', 'Position', [50, 50, 800, 600]);
    subplot(2,1,1);
end

%% ========== BER收敛曲线 ========== %%
iter_axis = 1:num_iter;
semilogy(iter_axis, max(iter_results.ber_per_iter, 1e-5), 'bo-', ...
         'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', 'b');
xlabel('迭代次数'); ylabel('BER');
title('误码率收敛');
grid on;
xlim([0.5, num_iter+0.5]);
set(gca, 'XTick', iter_axis);
% 标注每次BER值
for k = 1:num_iter
    text(k, iter_results.ber_per_iter(k)*1.3, ...
         sprintf('%.2f%%', iter_results.ber_per_iter(k)*100), ...
         'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', 'b');
end

%% ========== MSE收敛曲线 ========== %%
if has_mse
    if has_constellation
        subplot(2, num_const_show, floor(num_const_show/2)+1:num_const_show);
    else
        subplot(2,1,2);
    end
    plot(iter_axis, 10*log10(iter_results.mse_per_iter + 1e-30), 'rs-', ...
         'LineWidth', 2, 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    xlabel('迭代次数'); ylabel('MSE (dB)');
    title('均方误差收敛');
    grid on;
    xlim([0.5, num_iter+0.5]);
    set(gca, 'XTick', iter_axis);
end

%% ========== 各迭代星座图 ========== %%
if has_constellation
    ref = iter_results.ref_symbols;
    const_unique = unique(ref);

    for k = 1:num_const_show
        iter_idx = round((k-1) * (num_iter-1) / max(num_const_show-1, 1)) + 1;
        iter_idx = min(iter_idx, num_iter);

        subplot(2, num_const_show, num_const_show + k);
        sym_k = iter_results.constellation{iter_idx};
        n_show = min(length(sym_k), 500);

        plot(real(sym_k(1:n_show)), imag(sym_k(1:n_show)), '.', ...
             'Color', [0.4, 0.6, 0.9], 'MarkerSize', 3);
        hold on;
        if ~isempty(const_unique) && length(const_unique) <= 16
            plot(real(const_unique), imag(const_unique), 'r+', 'MarkerSize', 10, 'LineWidth', 2);
        end
        hold off;
        axis equal; grid on;
        title(sprintf('迭代%d (BER=%.1f%%)', iter_idx, iter_results.ber_per_iter(iter_idx)*100));
        xlabel('I'); ylabel('Q');
        max_r = max(abs([real(sym_k(:)); imag(sym_k(:))])) * 1.3;
        if max_r > 0, xlim([-max_r, max_r]); ylim([-max_r, max_r]); end
    end
end

sgtitle(sprintf('%s [%s]', title_str, iter_results.scheme));

end
