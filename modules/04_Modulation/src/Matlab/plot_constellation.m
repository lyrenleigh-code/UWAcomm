function plot_constellation(M, mapping, received_symbols)
% 功能：绘制QAM/PSK星座图，标注比特映射，可选叠加接收符号
% 版本：V1.0.0
% 输入：
%   M                - 调制阶数 (2/4/8/16/64)
%   mapping          - 映射方式 ('gray'(默认) 或 'natural')
%   received_symbols - 接收端符号 (1xL 复数数组，可选，用于叠加散点)
%
% 备注：
%   - 参考星座点用红色圆圈标注，旁边标注比特模式
%   - 接收符号用蓝色小点叠加显示
%   - BPSK仅显示实轴

%% ========== 1. 入参解析 ========== %%
if nargin < 3
    received_symbols = [];
end
if nargin < 2 || isempty(mapping)
    mapping = 'gray';
end

%% ========== 2. 生成星座图 ========== %%
dummy_bits = zeros(1, log2(M));
[~, constellation, bit_map] = qam_modulate(dummy_bits, M, mapping);

bps = log2(M);

%% ========== 3. 绘图 ========== %%
figure('Name', sprintf('%dQAM 星座图 (%s映射)', M, mapping), ...
       'NumberTitle', 'off');
hold on; grid on; axis equal;

% 绘制坐标轴
max_range = max(abs([real(constellation), imag(constellation)])) * 1.4;
plot([-max_range, max_range], [0, 0], 'k-', 'LineWidth', 0.5);
plot([0, 0], [-max_range, max_range], 'k-', 'LineWidth', 0.5);

% 叠加接收符号
if ~isempty(received_symbols)
    plot(real(received_symbols), imag(received_symbols), '.', ...
         'Color', [0.5, 0.7, 1.0], 'MarkerSize', 3);
end

% 绘制参考星座点
plot(real(constellation), imag(constellation), 'ro', ...
     'MarkerSize', 10, 'MarkerFaceColor', [1, 0.3, 0.3], 'LineWidth', 1.5);

% 标注比特模式
for k = 1:M
    bit_str = strrep(num2str(bit_map(k,:)), '  ', '');
    bit_str = strrep(bit_str, ' ', '');
    text(real(constellation(k)), imag(constellation(k)) + max_range*0.07, ...
         bit_str, 'HorizontalAlignment', 'center', 'FontSize', 8, ...
         'FontName', 'Consolas');
end

% 标题和标签
title(sprintf('%d-QAM 星座图（%s映射）', M, mapping));
xlabel('同相分量 (I)');
ylabel('正交分量 (Q)');
xlim([-max_range, max_range]);
ylim([-max_range, max_range]);

hold off;

end
