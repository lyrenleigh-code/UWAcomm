%% test_resample_vs_matlab.m
% 功能：对比 comp_resample_spline V7.1 与 MATLAB 原生/常用重采样方法
% 版本：V1.0.0（2026-04-22）
%
% 对比方法（共 6 种）：
%   1. comp_resample_spline 'fast'     — Catmull-Rom 局部四点（V7.1，本项目）
%   2. comp_resample_spline 'accurate' — 自然三次样条全局求解（V7.1，本项目）
%   3. matlab interp1 'spline'         — 等价于 V7.1 accurate（参考基线）
%   4. matlab interp1 'pchip'          — 分段三次 Hermite（非光滑但单调）
%   5. matlab interp1 'linear'         — 线性插值（最差 baseline）
%   6. matlab resample(x, p, q)        — polyphase FIR + anti-aliasing，α 用 rat() 近似
%
% 评估指标：
%   - NMSE (dB)
%   - max|err|
%   - runtime (ms)
%   - α<0 对称性
%
% 使用 QPSK-RRC 信号（带限基带）作为代表，α 扫描 9 点

clear functions; clear; close all; clc;

this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

log_file = fullfile(this_dir, 'test_resample_vs_matlab_results.txt');
if exist(log_file, 'file'), delete(log_file); end
diary(log_file); diary on;

fprintf('========================================\n');
fprintf('  comp_resample_spline V7.1 vs MATLAB 原生方法\n');
fprintf('========================================\n\n');

%% ============ 参数 ============
fs    = 48000;
T_sig = 1.0;
N     = round(T_sig * fs);

alpha_list = [0, 1e-4, -1e-4, 1e-3, -1e-3, 3e-3, -3e-3, 1e-2, -1e-2, ...
              3e-2, -3e-2, 5e-2, -5e-2, 7e-2, -7e-2];

alpha_max_abs = max(abs(alpha_list));
N_rx_margin   = ceil(alpha_max_abs * N) + 500;
N_rx          = N + N_rx_margin;
t_rx          = (0:N_rx-1) / fs;

%% ============ 参考信号：QPSK-RRC sps=8 ============
rng(42);
sym_rate = 6000;
sps      = fs / sym_rate;
Nsym     = ceil(N_rx / sps) + 4;
syms_q   = (2*randi([0 1], 1, Nsym)-1) + 1j*(2*randi([0 1], 1, Nsym)-1);
syms_q   = syms_q / sqrt(2);
s_ref    = kron(syms_q, ones(1, sps));
h_lp     = fir1(64, sym_rate/fs);
s_ref    = conv(s_ref, h_lp, 'same');
s_ref    = s_ref(1:N_rx);
s_ref    = s_ref / sqrt(mean(abs(s_ref).^2));

%% ============ 主循环 ============
method_names = {'spline-fast', 'spline-accurate', 'matlab-spline', ...
                'matlab-pchip', 'matlab-linear', 'matlab-resample'};
n_methods = numel(method_names);
n_alpha   = numel(alpha_list);

nmse   = nan(n_methods, n_alpha);
maxerr = nan(n_methods, n_alpha);
tms    = nan(n_methods, n_alpha);

edge_pad = 200;
cmp_range = (edge_pad+1):(N - edge_pad);

for a_idx = 1:n_alpha
    alpha = alpha_list(a_idx);

    % --- 合成接收信号 y(n) = s_ref((1+α)·n)，长度 N_rx ---
    pos_query = (1:N_rx) * (1 + alpha);
    pos_query = max(1, min(pos_query, length(s_ref)));
    y = interp1(1:length(s_ref), s_ref, pos_query, 'spline', 0);

    % --- 各方法补偿，输出截取前 N 样本 vs s_ref(1:N) ---
    for m = 1:n_methods
        try
            tic;
            switch method_names{m}
                case 'spline-fast'
                    y_out = comp_resample_spline(y, alpha, fs, 'fast');
                case 'spline-accurate'
                    y_out = comp_resample_spline(y, alpha, fs, 'accurate');
                case 'matlab-spline'
                    y_out = matlab_interp1_resample(y, alpha, 'spline');
                case 'matlab-pchip'
                    y_out = matlab_interp1_resample(y, alpha, 'pchip');
                case 'matlab-linear'
                    y_out = matlab_interp1_resample(y, alpha, 'linear');
                case 'matlab-resample'
                    y_out = matlab_resample_polyphase(y, alpha);
            end
            tms(m, a_idx) = toc * 1000;

            y_out = y_out(1:min(end, N_rx));
            L = min(length(y_out), N);
            err = y_out(1:L) - s_ref(1:L);
            cmp = cmp_range(cmp_range <= L);
            e_in = y_out(cmp) - s_ref(cmp);
            sig_pwr = mean(abs(s_ref(cmp)).^2);
            err_pwr = mean(abs(e_in).^2);
            nmse(m, a_idx)   = 10*log10(err_pwr / sig_pwr);
            maxerr(m, a_idx) = max(abs(e_in));
        catch ME
            fprintf('[%s @ α=%.0e] 失败: %s\n', method_names{m}, alpha, ME.message);
        end
    end
end

%% ============ 输出 1：NMSE 矩阵 ============
fprintf('\n================== NMSE (dB)  — 越低越好 ==================\n');
fprintf('%-16s', 'α');
for m = 1:n_methods
    fprintf('| %-15s', method_names{m});
end
fprintf('\n%s\n', repmat('-', 1, 16 + n_methods*17));

for a = 1:n_alpha
    fprintf('%-+16.2e', alpha_list(a));
    for m = 1:n_methods
        v = nmse(m, a);
        if isnan(v)
            fprintf('| %-15s', '--');
        else
            fprintf('| %-+15.2f', v);
        end
    end
    fprintf('\n');
end

%% ============ 输出 2：对称性（+α vs -α） ============
fprintf('\n================== 对称性 diff (+α NMSE − −α NMSE, dB) ==================\n');
fprintf('     0 = 对称，|diff| 大表示不对称\n');
fprintf('%-16s', '|α|');
for m = 1:n_methods
    fprintf('| %-15s', method_names{m});
end
fprintf('\n%s\n', repmat('-', 1, 16 + n_methods*17));

for a = 2:2:n_alpha   % 取 +α 列
    alpha_pos = alpha_list(a);
    a_neg = find(abs(alpha_list - (-alpha_pos)) < 1e-12, 1);
    if isempty(a_neg), continue; end
    fprintf('%-16.2e', abs(alpha_pos));
    for m = 1:n_methods
        d = nmse(m, a) - nmse(m, a_neg);
        fprintf('| %-+15.2f', d);
    end
    fprintf('\n');
end

%% ============ 输出 3：runtime ============
fprintf('\n================== Runtime (ms) @ N=%d 样本 ==================\n', N_rx);
fprintf('%-16s', '方法');
fprintf('| %-12s | %-12s | %-12s\n', 'mean', 'median', 'max');
fprintf('%s\n', repmat('-', 1, 16 + 3*15));
for m = 1:n_methods
    t_m = tms(m, :);
    t_m = t_m(~isnan(t_m));
    fprintf('%-16s', method_names{m});
    fprintf('| %-12.2f | %-12.2f | %-12.2f\n', ...
            mean(t_m), median(t_m), max(t_m));
end

%% ============ 输出 4：综合评分（|α|≤3e-2 范围内对称性 + 精度 + 速度） ============
fprintf('\n================== 综合评分（工程意义，|α|≤3e-2） ==================\n');
fprintf('%-16s| %-12s | %-12s | %-12s | %-12s\n', ...
        '方法', 'mean NMSE', 'max sym diff', 'median ms', '推荐度');
fprintf('%s\n', repmat('-', 1, 16 + 4*15));

for m = 1:n_methods
    idx_core = find(abs(alpha_list) <= 3e-2);
    nmse_m = nmse(m, idx_core);
    nmse_m = nmse_m(~isnan(nmse_m));

    mean_nmse = mean(nmse_m);

    max_diff = 0;
    for a = 2:2:n_alpha
        alpha_pos = alpha_list(a);
        if abs(alpha_pos) > 3e-2, continue; end
        a_neg = find(abs(alpha_list - (-alpha_pos)) < 1e-12, 1);
        d = abs(nmse(m, a) - nmse(m, a_neg));
        if d > max_diff, max_diff = d; end
    end

    t_m = tms(m, :);
    t_m = t_m(~isnan(t_m));
    median_ms = median(t_m);

    % 推荐评级
    if mean_nmse < -80 && max_diff < 3 && median_ms < 30
        rating = '★★★ 推荐';
    elseif mean_nmse < -60 && max_diff < 5
        rating = '★★ 可用';
    elseif mean_nmse < -30
        rating = '★ 边缘';
    else
        rating = '✗ 不推荐';
    end

    fprintf('%-16s| %-+12.2f | %-12.2f | %-12.2f | %-12s\n', ...
            method_names{m}, mean_nmse, max_diff, median_ms, rating);
end

%% ============ 可视化 ============
try
    % Figure 1: NMSE vs |α| 曲线（每条方法一条线，分 +α / -α）
    % 画图顺序：MATLAB 方法先画（下层），项目自实现方法后画（上层）
    % 避免 spline-accurate 与 matlab-spline NMSE 完全重叠时被覆盖
    f1 = figure('Name','NMSE vs α 对比','Position',[100 100 1100 700]);

    % 自实现方法（高亮）：粗实线 + 大实心 marker
    ours_idx = [find(strcmp(method_names,'spline-accurate')), ...
                find(strcmp(method_names,'spline-fast'))];
    % MATLAB 方法：细虚线 + 小 marker
    matlab_idx = setdiff(1:n_methods, ours_idx);

    plot_order = [matlab_idx, ours_idx];   % MATLAB 先画，自实现后画（覆盖在上）

    % 配色：MATLAB 方法用灰度/浅色，自实现用鲜明色
    color_map = struct();
    color_map.('spline_fast')       = [0.85 0.33 0.10];   % 橙红
    color_map.('spline_accurate')   = [0.00 0.45 0.74];   % 蓝
    color_map.('matlab_spline')     = [0.47 0.67 0.19];   % 绿
    color_map.('matlab_pchip')      = [0.49 0.18 0.56];   % 紫
    color_map.('matlab_linear')     = [0.50 0.50 0.50];   % 灰
    color_map.('matlab_resample')   = [0.93 0.69 0.13];   % 黄

    subplot(2,1,1);
    for k = 1:length(plot_order)
        m = plot_order(k);
        key = strrep(method_names{m}, '-', '_');
        c = color_map.(key);
        if any(m == ours_idx)
            lw = 2.5; ms = 11; lstyle = '-';
        else
            lw = 1.2; ms = 7;  lstyle = '--';
        end
        markers_all = {'o','s','d','^','v','x'};
        mkr = markers_all{m};
        pos_mask = alpha_list > 0;
        plot(alpha_list(pos_mask), nmse(m, pos_mask), lstyle, ...
             'Color', c, 'Marker', mkr, 'MarkerSize', ms, 'LineWidth', lw, ...
             'MarkerFaceColor', c * 0.8 + 0.2, ...
             'DisplayName', method_names{m});
        hold on;
    end
    set(gca, 'XScale', 'log');
    grid on;
    xlabel('+α'); ylabel('NMSE (dB)');
    title('+α 方向：NMSE vs |α|（QPSK-RRC, N=48000）| 粗实线=项目自实现，细虚线=MATLAB');
    legend('show', 'Location','southwest');

    subplot(2,1,2);
    for k = 1:length(plot_order)
        m = plot_order(k);
        key = strrep(method_names{m}, '-', '_');
        c = color_map.(key);
        if any(m == ours_idx)
            lw = 2.5; ms = 11; lstyle = '-';
        else
            lw = 1.2; ms = 7;  lstyle = '--';
        end
        markers_all = {'o','s','d','^','v','x'};
        mkr = markers_all{m};
        neg_mask = alpha_list < 0;
        plot(abs(alpha_list(neg_mask)), nmse(m, neg_mask), lstyle, ...
             'Color', c, 'Marker', mkr, 'MarkerSize', ms, 'LineWidth', lw, ...
             'MarkerFaceColor', c * 0.8 + 0.2, ...
             'DisplayName', method_names{m});
        hold on;
    end
    set(gca, 'XScale', 'log');
    grid on;
    xlabel('|−α|'); ylabel('NMSE (dB)');
    title('−α 方向：NMSE vs |α|');
    legend('show', 'Location','southwest');

    saveas(f1, fullfile(this_dir, 'test_resample_vs_matlab_nmse.png'));

    % Figure 2: runtime 柱状图
    f2 = figure('Name','Runtime 对比','Position',[120 120 900 500]);
    mean_tms = arrayfun(@(m) mean(tms(m,~isnan(tms(m,:)))), 1:n_methods);
    bar(mean_tms); set(gca, 'XTickLabel', method_names, 'XTickLabelRotation', 30);
    ylabel('mean runtime (ms)');
    title(sprintf('各方法平均 runtime（N=%d 样本）', N_rx));
    grid on;
    saveas(f2, fullfile(this_dir, 'test_resample_vs_matlab_runtime.png'));

    % Figure 3: 综合散点（NMSE vs runtime，α=3e-2 工况）
    f3 = figure('Name','精度-速度权衡 @ α=+3e-2','Position',[140 140 800 500]);
    a_plot = find(abs(alpha_list - 3e-2) < 1e-12, 1);
    for m = 1:n_methods
        scatter(tms(m, a_plot), nmse(m, a_plot), 150, colors(m,:), ...
                'filled', markers{m}); hold on;
        text(tms(m, a_plot)*1.1, nmse(m, a_plot), method_names{m}, ...
             'FontSize', 10);
    end
    grid on;
    xlabel('runtime (ms)'); ylabel('NMSE (dB)');
    title('精度-速度权衡 @ α=+3e-2（右下为最优）');
    set(gca, 'YDir', 'reverse');     % NMSE 越低越好
    saveas(f3, fullfile(this_dir, 'test_resample_vs_matlab_tradeoff.png'));

    fprintf('\n图已保存：\n  test_resample_vs_matlab_nmse.png\n  test_resample_vs_matlab_runtime.png\n  test_resample_vs_matlab_tradeoff.png\n');
catch ME
    fprintf('\n[警告] 可视化失败：%s\n', ME.message);
end

fprintf('\n========================================\n');
fprintf('  对比测试完成\n');
fprintf('========================================\n');
diary off;


%% ============ 辅助函数 ============

function y_out = matlab_interp1_resample(y, alpha, method)
% MATLAB interp1 做 α 重采样
% pos = (1:N)/(1+α)，用 method 插值
N = length(y);
pos = (1:N) / (1 + alpha);
% 对 pos>N 部分做 zero-pad（与 comp_resample_spline V7.1 策略一致）
pos_max = max(pos);
if pos_max > N
    pad_right = ceil(pos_max - N) + 4;
    y = [y, zeros(1, pad_right)];
end
xi = 1:length(y);
if isreal(y)
    y_out = interp1(xi, y, pos, method, 0);
else
    y_out = interp1(xi, real(y), pos, method, 0) + ...
            1j * interp1(xi, imag(y), pos, method, 0);
end
end

function y_out = matlab_resample_polyphase(y, alpha)
% MATLAB 原生 resample(x, p, q)：
% 补偿 α 意味着用 1/(1+α) 的采样率比。用 rat() 近似成分数
% 例：α=-0.03 → 1/0.97 = 1.0309... → p/q ≈ 1031/1000
% 注意：resample 只做整倍数 polyphase，对分数比用 rat 近似
[p, q] = rat(1/(1+alpha), 1e-7);   % 容差 1e-7
% 限制 p/q 大小，避免内存爆炸
if p*q > 1e8
    [p, q] = rat(1/(1+alpha), 1e-5);
end

if isreal(y)
    y_out = resample(y, p, q);
else
    y_out = resample(real(y), p, q) + 1j * resample(imag(y), p, q);
end

% resample 输出长度 ≈ ceil(length(y)*p/q)，取前 length(y) 样本
N_orig = length(y);
if length(y_out) >= N_orig
    y_out = y_out(1:N_orig);
else
    y_out = [y_out, zeros(1, N_orig - length(y_out))];
end
end
