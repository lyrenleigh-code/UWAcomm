function plot_beampattern(array_config, weights, title_str)
% 功能：波束方向图可视化
% 版本：V1.0.0
% 输入：
%   array_config - 阵列配置（由gen_array_config生成）
%   weights      - 波束形成权重 (Mx1，默认等权DAS)
%   title_str    - 标题

if nargin < 3, title_str = 'Beam Pattern'; end
M = array_config.M;
if nargin < 2 || isempty(weights)
    weights = ones(M, 1) / sqrt(M);
end
weights = weights(:);

fc = array_config.fc;
c = array_config.c;
lambda = c / fc;

%% ========== 计算方向图 ========== %%
theta_scan = linspace(-pi/2, pi/2, 361);
bp = zeros(1, length(theta_scan));

for i = 1:length(theta_scan)
    % 导向矢量
    look_dir = [sin(theta_scan(i)), cos(theta_scan(i)), 0];
    tau = array_config.positions * look_dir.' / c;
    a = exp(-1j * 2 * pi * fc * tau);

    bp(i) = abs(weights' * a)^2;
end

bp_db = 10 * log10(bp / max(bp) + 1e-30);

%% ========== 绘图 ========== %%
figure('Name', title_str, 'NumberTitle', 'off', 'Position', [80, 80, 900, 400]);

% 直角坐标
subplot(1,2,1);
plot(theta_scan * 180/pi, bp_db, 'b', 'LineWidth', 1.5);
xlabel('角度 (度)'); ylabel('增益 (dB)');
title('波束方向图（直角坐标）');
grid on; ylim([-40, 5]);
xlim([-90, 90]);

% 极坐标
subplot(1,2,2);
polarplot(theta_scan, max(bp_db, -40) + 40, 'b', 'LineWidth', 1.5);
title('波束方向图（极坐标）');
rlim([0, 45]);

sgtitle(sprintf('%s (%s, M=%d, d=%.2fλ)', title_str, array_config.type, M, array_config.d/lambda));

end
