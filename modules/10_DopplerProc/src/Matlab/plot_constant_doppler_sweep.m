function plot_constant_doppler_sweep(varargin)
% 功能：读 e2e_baseline_D.csv 画 alpha_est vs alpha_true 曲线 + BER vs α
% 版本：V1.0.0（2026-04-19）
% 对应 spec: 2026-04-19-constant-doppler-isolation.md
% 输入（可选 name-value）：
%   'csv_path', char   CSV 路径（默认 tests/bench_results/e2e_baseline_D.csv）
%   'fig_dir',  char   PNG 输出目录（默认 wiki/comparisons/figures/）
%   'dpi',      int    图像分辨率（默认 150）
%
% 图：
%   1. alpha_est vs alpha_true（对数双轴，理想线 y=x）
%   2. 估计误差 |α_est - α_true| vs α_true（对数）
%   3. BER vs α_true（对数横轴）

%% 参数
p = inputParser;
this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(this_dir))));
default_csv = fullfile(proj_root, 'modules', '13_SourceCode', 'src', 'Matlab', ...
                        'tests', 'bench_results', 'e2e_baseline_D.csv');
default_fig = fullfile(proj_root, 'wiki', 'comparisons', 'figures');
p.addParameter('csv_path', default_csv, @ischar);
p.addParameter('fig_dir',  default_fig, @ischar);
p.addParameter('dpi', 150, @isnumeric);
p.parse(varargin{:});
csv_path = p.Results.csv_path;
fig_dir  = p.Results.fig_dir;
dpi      = p.Results.dpi;
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end

fprintf('plot_constant_doppler_sweep V1.0.0\n');
fprintf('  CSV: %s\n', csv_path);
fprintf('  Fig: %s\n', fig_dir);

T = readtable(csv_path, 'TextType', 'string');
fprintf('  [read] %d rows\n', height(T));

schemes = unique(T.scheme);

%% 图 1: alpha_est vs alpha_true
fig1 = figure('Visible','off','Position',[100 100 1000 650]);
hold on;
for si = 1:numel(schemes)
    Ts = T(strcmp(T.scheme, schemes{si}), :);
    Ts = sortrows(Ts, 'doppler_rate');
    a_true = Ts.doppler_rate;
    a_est  = Ts.alpha_est;
    plot(a_true, a_est, '-o', 'LineWidth', 1.8, 'MarkerSize', 8, ...
         'DisplayName', schemes{si});
end
% 理想线 y=x
a_range = [min(T.doppler_rate), max(T.doppler_rate)];
plot(a_range, a_range, 'k--', 'LineWidth', 1, 'DisplayName', '理想 y=x');
% LFM 模糊阈值 ±8.3e-4
yl = ylim;
plot([8.3e-4 8.3e-4], yl, 'r:', 'LineWidth', 1.5, 'DisplayName', 'LFM ±π 模糊 (理论)');
plot([-8.3e-4 -8.3e-4], yl, 'r:', 'LineWidth', 1.5, 'HandleVisibility','off');
hold off;
grid on;
xlabel('\alpha_{true} (归一化多普勒率)');
ylabel('\alpha_{est}');
title('α 估计：alpha\_est vs alpha\_true  @ SNR=10dB');
legend('Location','best');
out1 = fullfile(fig_dir, 'D_alpha_est_vs_true.png');
exportgraphics(fig1, out1, 'Resolution', dpi); close(fig1);
fprintf('  [png] %s\n', out1);

%% 图 2: 估计误差
fig2 = figure('Visible','off','Position',[100 100 1000 650]);
hold on;
for si = 1:numel(schemes)
    Ts = T(strcmp(T.scheme, schemes{si}), :);
    Ts = sortrows(Ts, 'doppler_rate');
    a_true = Ts.doppler_rate;
    a_est  = Ts.alpha_est;
    err = abs(a_est - a_true);
    % 相对误差（α_true=0 时取绝对值）
    rel_err = err ./ max(abs(a_true), 1e-6);
    plot(abs(a_true), rel_err, '-s', 'LineWidth', 1.8, 'MarkerSize', 8, ...
         'DisplayName', schemes{si});
end
hold off;
set(gca, 'XScale', 'log', 'YScale', 'log');
grid on;
xlabel('|\alpha_{true}| (对数)');
ylabel('相对误差 |α_{est}-α_{true}| / max(|α_{true}|, 1e-6)');
title('α 估计相对误差 @ SNR=10dB');
legend('Location','best');
out2 = fullfile(fig_dir, 'D_alpha_rel_error.png');
exportgraphics(fig2, out2, 'Resolution', dpi); close(fig2);
fprintf('  [png] %s\n', out2);

%% 图 3: BER vs α
fig3 = figure('Visible','off','Position',[100 100 1000 650]);
hold on;
for si = 1:numel(schemes)
    Ts = T(strcmp(T.scheme, schemes{si}), :);
    Ts = sortrows(Ts, 'doppler_rate');
    plot(Ts.doppler_rate, Ts.ber_coded, '-o', 'LineWidth', 1.8, ...
         'MarkerSize', 8, 'DisplayName', schemes{si});
end
hold off;
grid on;
xlabel('\alpha_{true}');
ylabel('BER (coded)');
ylim([-0.02 0.6]);
title('BER vs α @ SNR=10dB（D 阶段：恒定 α 隔离）');
legend('Location','best');
out3 = fullfile(fig_dir, 'D_ber_vs_alpha.png');
exportgraphics(fig3, out3, 'Resolution', dpi); close(fig3);
fprintf('  [png] %s\n', out3);

%% 控制台汇总
fprintf('\n============ α 估计诊断汇总 ============\n');
fprintf('%-10s %-12s %-14s %-12s %-10s\n', 'scheme', 'α_true', 'α_est', '|err|', 'BER');
for si = 1:numel(schemes)
    Ts = T(strcmp(T.scheme, schemes{si}), :);
    Ts = sortrows(Ts, 'doppler_rate');
    for r = 1:height(Ts)
        fprintf('%-10s %+.2e    %+.3e     %.2e     %.4f\n', ...
            Ts.scheme{r}, Ts.doppler_rate(r), Ts.alpha_est(r), ...
            abs(Ts.alpha_est(r) - Ts.doppler_rate(r)), Ts.ber_coded(r));
    end
end
fprintf('==========================================\n');

end
