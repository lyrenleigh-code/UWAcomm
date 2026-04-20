function bench_plot_all(varargin)
% 功能：读取 bench_results/e2e_baseline_{A1,A2,A3,B}.csv 并生成 ≥10 张 PNG
% 版本：V1.0.0（2026-04-19）
% 输入（name-value 可选）：
%   'csv_dir',   char    CSV 输入目录（默认 tests/bench_results/）
%   'fig_dir',   char    PNG 输出目录（默认 wiki/comparisons/figures/）
%   'dpi',       int     图像分辨率（默认 150）
% 输出：
%   无（PNG 写入 fig_dir）
%
% 图清单：
%   A1-1  BER-SNR 曲线（6 subplot/scheme，各 fd 为一条线）
%   A1-2  BER-fd 曲线 @ snr=10（单图 6 scheme 对比）
%   A1-3  Heatmap scheme × fd @ snr=10
%   A2-1  BER-SNR 曲线（5 scheme subplot，α 为线，OTFS 跳过）
%   A2-2  BER-α 曲线 @ snr=10（5 scheme 对比）
%   A2-3  Heatmap scheme × α @ snr=10
%   A3-1  fd × α 热图，每 scheme 一张子图 @ snr=10
%   B-1   柱状图 scheme × channel @ snr=10
%   B-2   BER-SNR 曲线（4 subplot/channel，scheme 为线）
%   summary  4 stage 合并柱状图对比

%% 1. 参数解析
p = inputParser;
this_dir = fileparts(mfilename('fullpath'));
default_csv = fullfile(this_dir, 'bench_results');
default_fig = fullfile(fileparts(fileparts(fileparts(fileparts(fileparts(this_dir))))), ...
                        'wiki', 'comparisons', 'figures');
p.addParameter('csv_dir', default_csv, @ischar);
p.addParameter('fig_dir', default_fig, @ischar);
p.addParameter('dpi', 150, @isnumeric);
p.parse(varargin{:});
csv_dir = p.Results.csv_dir;
fig_dir = p.Results.fig_dir;
if ~exist(fig_dir, 'dir'), mkdir(fig_dir); end
dpi = p.Results.dpi;

fprintf('bench_plot_all V1.0.0\n');
fprintf('  CSV dir: %s\n', csv_dir);
fprintf('  Fig dir: %s\n', fig_dir);

%% 2. 读取 CSV
T_A1 = read_csv(fullfile(csv_dir, 'e2e_baseline_A1.csv'));
T_A2 = read_csv(fullfile(csv_dir, 'e2e_baseline_A2.csv'));
T_A3 = read_csv(fullfile(csv_dir, 'e2e_baseline_A3.csv'));
T_B  = read_csv(fullfile(csv_dir, 'e2e_baseline_B.csv'));

schemes_all = {'SC-FDE','OFDM','SC-TDE','OTFS','DSSS','FH-MFSK'};
schemes_a2  = {'SC-FDE','OFDM','SC-TDE','DSSS','FH-MFSK'};  % OTFS 跳过
channels    = {'disc-5Hz','hyb-K20','hyb-K10','hyb-K5'};

%% 3. A1 图
fprintf('\n== A1 图 ==\n');
plot_ber_snr_per_scheme(T_A1, schemes_all, 'fd_hz', 'fd=%gHz', ...
    'A1: BER vs SNR（Jakes 衰落扫描）', fullfile(fig_dir,'A1_ber_snr_per_scheme.png'), dpi);

plot_ber_x_at_snr(T_A1, schemes_all, 'fd_hz', 10, ...
    'A1: BER vs fd @ SNR=10dB', 'Jakes fd (Hz)', ...
    fullfile(fig_dir,'A1_ber_vs_fd_snr10.png'), dpi);

plot_heatmap(T_A1, schemes_all, 'fd_hz', 10, ...
    'A1 Heatmap: BER（scheme × fd）@ SNR=10dB', 'Jakes fd (Hz)', ...
    fullfile(fig_dir,'A1_heatmap_snr10.png'), dpi);

%% 4. A2 图
fprintf('\n== A2 图 ==\n');
plot_ber_snr_per_scheme(T_A2, schemes_a2, 'doppler_rate', 'α=%g', ...
    'A2: BER vs SNR（固定多普勒 α 扫描，OTFS skip）', ...
    fullfile(fig_dir,'A2_ber_snr_per_scheme.png'), dpi);

plot_ber_x_at_snr(T_A2, schemes_a2, 'doppler_rate', 10, ...
    'A2: BER vs α @ SNR=10dB', 'Doppler rate α', ...
    fullfile(fig_dir,'A2_ber_vs_alpha_snr10.png'), dpi);

plot_heatmap(T_A2, schemes_a2, 'doppler_rate', 10, ...
    'A2 Heatmap: BER（scheme × α）@ SNR=10dB', 'Doppler rate α', ...
    fullfile(fig_dir,'A2_heatmap_snr10.png'), dpi);

%% 5. A3 图（每 scheme 一张 fd × α 热图）
fprintf('\n== A3 图 ==\n');
plot_a3_heatmaps(T_A3, schemes_all, 10, ...
    fullfile(fig_dir,'A3_heatmaps_per_scheme_snr10.png'), dpi);

%% 6. B 图
fprintf('\n== B 图 ==\n');
plot_b_bar(T_B, schemes_all, channels, 10, ...
    fullfile(fig_dir,'B_bar_snr10.png'), dpi);

plot_b_ber_snr_per_channel(T_B, schemes_all, channels, ...
    fullfile(fig_dir,'B_ber_snr_per_channel.png'), dpi);

%% 7. Summary：4 stage 合并对比（snr=10）
plot_summary(T_A1, T_A2, T_A3, T_B, schemes_all, ...
    fullfile(fig_dir,'summary_snr10.png'), dpi);

fprintf('\n【bench_plot_all】完成，PNG 输出目录: %s\n', fig_dir);

end

%% ===================== Helper Functions =====================

function T = read_csv(path)
if ~exist(path, 'file')
    warning('read_csv:MissingCSV', 'CSV 不存在: %s', path);
    T = table();
    return;
end
T = readtable(path, 'TextType', 'string');
fprintf('  [read] %-30s %d rows\n', path, height(T));
end

function colors = scheme_colors()
colors = containers.Map(...
    {'SC-FDE','OFDM','SC-TDE','OTFS','DSSS','FH-MFSK'}, ...
    {[0.85 0.33 0.10],[0.00 0.45 0.74],[0.47 0.67 0.19],...
     [0.49 0.18 0.56],[0.93 0.69 0.13],[0.30 0.75 0.93]});
end

function plot_ber_snr_per_scheme(T, schemes, vary_col, vary_fmt, fig_title, out_path, dpi)
% 每个 scheme 一个子图，线为 vary_col 的不同取值
fig = figure('Visible','off','Position',[100 100 1400 900]);
sgtitle(fig_title, 'FontWeight', 'bold');
n = numel(schemes);
nc = 3; nr = ceil(n/nc);
for si = 1:n
    subplot(nr, nc, si);
    scheme = schemes{si};
    Ts = T(strcmp(T.scheme, scheme), :);
    if isempty(Ts), title(sprintf('%s (no data)', scheme)); continue; end
    vary_vals = unique(Ts.(vary_col));
    hold on;
    for vi = 1:numel(vary_vals)
        Tv = Ts(Ts.(vary_col) == vary_vals(vi), :);
        Tv = sortrows(Tv, 'snr_db');
        ber = max(Tv.ber_coded, 1e-4);  % 防止 log 0
        semilogy(Tv.snr_db, ber, '-o', 'LineWidth', 1.2, 'MarkerSize', 4, ...
                 'DisplayName', sprintf(vary_fmt, vary_vals(vi)));
    end
    hold off;
    set(gca, 'YScale', 'log', 'YLim', [1e-4 1]);
    grid on; xlabel('SNR (dB)'); ylabel('BER');
    title(scheme); legend('Location','best','FontSize',7);
end
exportgraphics(fig, out_path, 'Resolution', dpi);
close(fig);
fprintf('  [png] %s\n', out_path);
end

function plot_ber_x_at_snr(T, schemes, x_col, snr_target, fig_title, xlabel_str, out_path, dpi)
% 单图，每 scheme 一条线，x 为 x_col，y 为 BER @ snr_target
fig = figure('Visible','off','Position',[100 100 900 600]);
cmap = scheme_colors();
hold on;
for si = 1:numel(schemes)
    scheme = schemes{si};
    Ts = T(strcmp(T.scheme, scheme) & T.snr_db == snr_target, :);
    if isempty(Ts), continue; end
    Ts = sortrows(Ts, x_col);
    ber = max(Ts.ber_coded, 1e-4);
    color = [0 0 0];
    if isKey(cmap, scheme), color = cmap(scheme); end
    semilogy(Ts.(x_col), ber, '-o', 'LineWidth', 1.8, 'MarkerSize', 7, ...
             'Color', color, 'DisplayName', scheme);
end
hold off;
set(gca, 'YScale', 'log', 'YLim', [1e-4 1]);
grid on; xlabel(xlabel_str); ylabel('BER'); title(fig_title);
legend('Location','best');
exportgraphics(fig, out_path, 'Resolution', dpi);
close(fig);
fprintf('  [png] %s\n', out_path);
end

function plot_heatmap(T, schemes, x_col, snr_target, fig_title, xlabel_str, out_path, dpi)
% 2D heatmap: row=scheme, col=x_col, value=BER @ snr
Ts = T(T.snr_db == snr_target, :);
x_vals = unique(Ts.(x_col));
M = NaN(numel(schemes), numel(x_vals));
for si = 1:numel(schemes)
    for xi = 1:numel(x_vals)
        row = Ts(strcmp(Ts.scheme, schemes{si}) & Ts.(x_col) == x_vals(xi), :);
        if ~isempty(row), M(si, xi) = row.ber_coded(1); end
    end
end
fig = figure('Visible','off','Position',[100 100 900 500]);
imagesc(M);
xlabel(xlabel_str); ylabel('Scheme');
set(gca,'XTick',1:numel(x_vals),'XTickLabel',arrayfun(@(v) num2str(v),x_vals,'UniformOutput',false));
set(gca,'YTick',1:numel(schemes),'YTickLabel',schemes);
colorbar; caxis([0 0.5]);
title(fig_title);
% 数字注释
for si = 1:numel(schemes)
    for xi = 1:numel(x_vals)
        if ~isnan(M(si,xi))
            text(xi, si, sprintf('%.2f', M(si,xi)), 'HorizontalAlignment','center', ...
                 'Color', ternary(M(si,xi)>0.25,'w','k'), 'FontSize', 8);
        end
    end
end
exportgraphics(fig, out_path, 'Resolution', dpi);
close(fig);
fprintf('  [png] %s\n', out_path);
end

function plot_a3_heatmaps(T, schemes, snr_target, out_path, dpi)
% A3: 每 scheme 一个子图，fd × α BER heatmap
Ts = T(T.snr_db == snr_target, :);
fds    = unique(Ts.fd_hz);
alphas = unique(Ts.doppler_rate);
fig = figure('Visible','off','Position',[100 100 1400 900]);
sgtitle(sprintf('A3: BER heatmap fd × α @ SNR=%ddB', snr_target), 'FontWeight','bold');
nc = 3; nr = ceil(numel(schemes)/nc);
for si = 1:numel(schemes)
    subplot(nr, nc, si);
    M = NaN(numel(fds), numel(alphas));
    for fi = 1:numel(fds)
        for ai = 1:numel(alphas)
            row = Ts(strcmp(Ts.scheme, schemes{si}) & ...
                      Ts.fd_hz == fds(fi) & Ts.doppler_rate == alphas(ai), :);
            if ~isempty(row), M(fi, ai) = row.ber_coded(1); end
        end
    end
    imagesc(M);
    xlabel('α (doppler\_rate)'); ylabel('fd (Hz)');
    set(gca,'XTick',1:numel(alphas),'XTickLabel',arrayfun(@(v) sprintf('%g',v),alphas,'UniformOutput',false));
    set(gca,'YTick',1:numel(fds),'YTickLabel',arrayfun(@(v) num2str(v),fds,'UniformOutput',false));
    colorbar; caxis([0 0.5]);
    title(schemes{si});
    for fi = 1:numel(fds)
        for ai = 1:numel(alphas)
            if ~isnan(M(fi,ai))
                text(ai, fi, sprintf('%.2f', M(fi,ai)), 'HorizontalAlignment','center', ...
                     'Color', ternary(M(fi,ai)>0.25,'w','k'), 'FontSize', 7);
            end
        end
    end
end
exportgraphics(fig, out_path, 'Resolution', dpi);
close(fig);
fprintf('  [png] %s\n', out_path);
end

function plot_b_bar(T, schemes, channels, snr_target, out_path, dpi)
% 柱状图：scheme × channel @ snr
M = NaN(numel(schemes), numel(channels));
for si = 1:numel(schemes)
    for ci = 1:numel(channels)
        row = T(strcmp(T.scheme, schemes{si}) & strcmp(T.profile, channels{ci}) & ...
                T.snr_db == snr_target, :);
        if ~isempty(row), M(si, ci) = row.ber_coded(1); end
    end
end
fig = figure('Visible','off','Position',[100 100 1000 600]);
b = bar(M);
set(gca, 'XTickLabel', schemes, 'XTickLabelRotation', 30);
ylabel('BER'); ylim([0 0.6]);
title(sprintf('B: 离散 Doppler / Rician 混合 BER 对比 @ SNR=%ddB', snr_target));
legend(channels, 'Location','best');
grid on;
exportgraphics(fig, out_path, 'Resolution', dpi);
close(fig);
fprintf('  [png] %s\n', out_path);
end

function plot_b_ber_snr_per_channel(T, schemes, channels, out_path, dpi)
% 4 subplot/channel，线为 scheme
fig = figure('Visible','off','Position',[100 100 1200 800]);
sgtitle('B: BER vs SNR（每 channel 6 scheme 对比）', 'FontWeight','bold');
cmap = scheme_colors();
nc = 2; nr = 2;
for ci = 1:numel(channels)
    subplot(nr, nc, ci);
    hold on;
    for si = 1:numel(schemes)
        Ts = T(strcmp(T.scheme, schemes{si}) & strcmp(T.profile, channels{ci}), :);
        if isempty(Ts), continue; end
        Ts = sortrows(Ts, 'snr_db');
        ber = max(Ts.ber_coded, 1e-4);
        color = [0 0 0];
        if isKey(cmap, schemes{si}), color = cmap(schemes{si}); end
        semilogy(Ts.snr_db, ber, '-o', 'LineWidth', 1.5, 'MarkerSize', 6, ...
                 'Color', color, 'DisplayName', schemes{si});
    end
    hold off;
    set(gca, 'YScale', 'log', 'YLim', [1e-4 1]);
    grid on; xlabel('SNR (dB)'); ylabel('BER');
    title(channels{ci}); legend('Location','best','FontSize',7);
end
exportgraphics(fig, out_path, 'Resolution', dpi);
close(fig);
fprintf('  [png] %s\n', out_path);
end

function plot_summary(T1, T2, T3, TB, schemes, out_path, dpi)
% 合并柱状图：各 stage 下 scheme 的"平均 BER @ snr=10"
stages = {'A1','A2','A3','B'};
M = NaN(numel(schemes), 4);
for si = 1:numel(schemes)
    for k = 1:4
        switch k
            case 1, T = T1(T1.snr_db==10 & strcmp(T1.scheme,schemes{si}), :);
            case 2, T = T2(T2.snr_db==10 & strcmp(T2.scheme,schemes{si}), :);
            case 3, T = T3(T3.snr_db==10 & strcmp(T3.scheme,schemes{si}), :);
            case 4, T = TB(TB.snr_db==10 & strcmp(TB.scheme,schemes{si}), :);
        end
        if ~isempty(T), M(si, k) = mean(T.ber_coded, 'omitnan'); end
    end
end
fig = figure('Visible','off','Position',[100 100 1100 550]);
bar(M);
set(gca, 'XTickLabel', schemes, 'XTickLabelRotation', 30);
ylabel('平均 BER @ SNR=10dB'); ylim([0 0.6]);
title('Summary: 各阶段平均 BER @ SNR=10dB');
legend(stages, 'Location','best');
grid on;
exportgraphics(fig, out_path, 'Resolution', dpi);
close(fig);
fprintf('  [png] %s\n', out_path);
end

function v = ternary(cond, a, b)
if cond, v = a; else, v = b; end
end
