function plot_eye_diagram(signal, sps, num_periods, title_str)
% 功能：眼图绘制——观测脉冲成形后的码间干扰和定时余量
% 版本：V1.0.0
% 输入：
%   signal      - 脉冲成形后的基带信号 (1xN 复数/实数)
%   sps         - 每符号采样数
%   num_periods - 叠加的符号周期数 (默认 2，即显示2个符号周期宽度)
%   title_str   - 图标题 (默认 'Eye Diagram')

if nargin < 4 || isempty(title_str), title_str = 'Eye Diagram'; end
if nargin < 3 || isempty(num_periods), num_periods = 2; end
signal = signal(:).';

trace_len = num_periods * sps;         % 每条轨迹的长度
num_traces = floor(length(signal) / trace_len) - 1;

if num_traces < 2
    error('信号太短，无法绘制眼图！至少需要 %d 个采样。', 3*trace_len);
end

t_axis = (0:trace_len-1) / sps;       % 归一化时间轴（符号周期）

figure('Name', title_str, 'NumberTitle', 'off', 'Position', [80, 80, 900, 500]);

% 实部眼图
subplot(1,2,1);
hold on;
for k = 1:min(num_traces, 200)        % 最多叠加200条轨迹
    start = (k-1) * sps + 1;          % 每次偏移1个符号
    if start + trace_len - 1 > length(signal), break; end
    trace = real(signal(start : start + trace_len - 1));
    plot(t_axis, trace, 'b', 'LineWidth', 0.3, 'Color', [0, 0.3, 0.8, 0.15]);
end
hold off;
xlabel('时间 (符号周期)'); ylabel('幅度（实部）');
title('同相分量 (I)'); grid on;
xlim([0, num_periods]);

% 虚部眼图（仅复数信号）
subplot(1,2,2);
if ~isreal(signal)
    hold on;
    for k = 1:min(num_traces, 200)
        start = (k-1) * sps + 1;
        if start + trace_len - 1 > length(signal), break; end
        trace = imag(signal(start : start + trace_len - 1));
        plot(t_axis, trace, 'r', 'LineWidth', 0.3, 'Color', [0.8, 0.1, 0, 0.15]);
    end
    hold off;
    xlabel('时间 (符号周期)'); ylabel('幅度（虚部）');
    title('正交分量 (Q)'); grid on;
    xlim([0, num_periods]);
else
    % 实数信号：显示包络
    hold on;
    for k = 1:min(num_traces, 200)
        start = (k-1) * sps + 1;
        if start + trace_len - 1 > length(signal), break; end
        trace = abs(signal(start : start + trace_len - 1));
        plot(t_axis, trace, 'r', 'LineWidth', 0.3, 'Color', [0.8, 0.1, 0, 0.15]);
    end
    hold off;
    xlabel('时间 (符号周期)'); ylabel('包络');
    title('信号包络'); grid on;
    xlim([0, num_periods]);
end

sgtitle(sprintf('%s  (sps=%d, %d条轨迹)', title_str, sps, min(num_traces, 200)));

end
