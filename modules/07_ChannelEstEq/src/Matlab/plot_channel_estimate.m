function plot_channel_estimate(h_true, h_est_list, est_names, title_str)
% 功能：信道估计结果可视化——时域/频域/NMSE对比
% 版本：V1.0.0
% 输入：
%   h_true      - 真实信道 (1xN)
%   h_est_list  - 估计信道cell数组 {h1, h2, ...}，每个为1xN
%   est_names   - 算法名称cell数组 {'LS','OMP',...}
%   title_str   - 标题

if nargin < 4, title_str = 'Channel Estimation'; end
N = length(h_true);
K = length(h_est_list);

figure('Name', title_str, 'NumberTitle', 'off', 'Position', [50,50,1100,700]);
colors = lines(K+1);

% 时域幅度
subplot(2,2,1);
stem(0:N-1, abs(h_true), 'k', 'LineWidth', 1.5, 'DisplayName', '真实信道');
hold on;
for k = 1:K
    h_k = h_est_list{k}; h_k = h_k(:).';
    if length(h_k) < N, h_k = [h_k, zeros(1, N-length(h_k))]; end
    stem(0:N-1, abs(h_k), 'Color', colors(k+1,:), 'LineWidth', 1, ...
         'Marker', 'x', 'DisplayName', est_names{k});
end
hold off;
xlabel('抽头索引'); ylabel('|h|'); title('时域信道幅度');
legend('Location','best','FontSize',8); grid on;

% 频域幅度
subplot(2,2,2);
H_true = fft(h_true, N);
plot(0:N-1, 20*log10(abs(H_true)+1e-10), 'k-', 'LineWidth', 1.5, 'DisplayName', '真实');
hold on;
for k = 1:K
    h_k = h_est_list{k}(:).';
    if length(h_k) < N, h_k = [h_k, zeros(1, N-length(h_k))]; end
    H_k = fft(h_k, N);
    plot(0:N-1, 20*log10(abs(H_k)+1e-10), 'Color', colors(k+1,:), 'LineWidth', 1, ...
         'DisplayName', est_names{k});
end
hold off;
xlabel('子载波索引'); ylabel('|H| (dB)'); title('频域信道响应');
legend('Location','best','FontSize',8); grid on;

% NMSE柱状图
subplot(2,2,3);
nmse = zeros(1, K);
for k = 1:K
    h_k = h_est_list{k}(:).';
    if length(h_k) < N, h_k = [h_k, zeros(1, N-length(h_k))]; end
    nmse(k) = 10*log10(norm(h_k - h_true)^2 / norm(h_true)^2);
end
bar(nmse, 'FaceColor', [0.3, 0.6, 0.9]);
set(gca, 'XTickLabel', est_names, 'FontSize', 9);
ylabel('NMSE (dB)'); title('估计精度对比');
grid on;
for k = 1:K
    text(k, nmse(k)-1, sprintf('%.1f', nmse(k)), 'HorizontalAlignment','center','FontSize',9);
end

% 估计误差
subplot(2,2,4);
hold on;
for k = 1:K
    h_k = h_est_list{k}(:).';
    if length(h_k) < N, h_k = [h_k, zeros(1, N-length(h_k))]; end
    plot(0:N-1, abs(h_k - h_true), 'Color', colors(k+1,:), 'LineWidth', 1, ...
         'DisplayName', est_names{k});
end
hold off;
xlabel('抽头索引'); ylabel('|误差|'); title('估计误差');
legend('Location','best','FontSize',8); grid on;

sgtitle(title_str);
end
