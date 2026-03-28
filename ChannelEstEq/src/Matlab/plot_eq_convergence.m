function plot_eq_convergence(x_hat_list, ref_symbols, eq_names, window_size, title_str)
% 功能：均衡器收敛曲线可视化——滑动窗口MSE/BER随符号数变化
% 版本：V1.0.0
% 输入：
%   x_hat_list  - 均衡输出cell数组 {x1, x2, ...}，每个为1xN复数
%   ref_symbols - 参考符号（发送符号，1xN）
%   eq_names    - 算法名称cell数组
%   window_size - 滑动窗口大小（符号数，默认 30）
%   title_str   - 标题

if nargin < 5, title_str = 'Equalizer Convergence'; end
if nargin < 4 || isempty(window_size), window_size = 30; end

K = length(x_hat_list);
ref = ref_symbols(:).';
N_ref = length(ref);
colors = lines(K);

figure('Name', title_str, 'NumberTitle', 'off', 'Position', [50, 50, 1000, 700]);

% 上图：滑动窗口MSE
subplot(2,1,1);
hold on;
for k = 1:K
    x_k = x_hat_list{k}(:).';
    N_k = min(length(x_k), N_ref);

    % 逐符号误差
    err = abs(x_k(1:N_k) - ref(1:N_k)).^2;

    % 滑动窗口平均MSE
    mse_curve = zeros(1, N_k);
    for n = 1:N_k
        w_start = max(1, n - window_size + 1);
        mse_curve(n) = mean(err(w_start:n));
    end

    plot(1:N_k, 10*log10(mse_curve + 1e-30), 'Color', colors(k,:), ...
         'LineWidth', 1.5, 'DisplayName', eq_names{k});
end
hold off;
xlabel('符号索引'); ylabel('滑动MSE (dB)');
title(sprintf('均衡器收敛曲线（窗口=%d符号）', window_size));
legend('Location', 'northeast', 'FontSize', 9); grid on;

% 下图：累积BER
subplot(2,1,2);
hold on;
for k = 1:K
    x_k = x_hat_list{k}(:).';
    N_k = min(length(x_k), N_ref);

    % 逐符号判决
    dec = qpsk_hard_decision(x_k(1:N_k));
    ref_dec = qpsk_hard_decision(ref(1:N_k));

    % 累积BER
    cum_errors = cumsum(dec ~= ref_dec);
    cum_ber = cum_errors ./ (1:N_k);

    plot(1:N_k, cum_ber, 'Color', colors(k,:), ...
         'LineWidth', 1.5, 'DisplayName', eq_names{k});
end
hold off;
xlabel('符号索引'); ylabel('累积BER');
title('均衡器收敛——累积误码率');
legend('Location', 'northeast', 'FontSize', 9); grid on;
ylim([0, max(0.6, max(cum_ber)*1.2)]);

sgtitle(title_str);

end

% --------------- QPSK硬判决 --------------- %
function d = qpsk_hard_decision(x)
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
d = zeros(size(x));
for n = 1:length(x)
    [~, idx] = min(abs(x(n) - constellation));
    d(n) = constellation(idx);
end
end
