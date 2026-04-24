function p4_render_quality(history, axes_struct)
% P3_RENDER_QUALITY  质量历史 tab 渲染（最近 N 帧 BER / SNR / iter 演进）
%
% 功能：读 p3_demo_ui 的 `app.history` cell array（每元素含
%       `.ber / .info.estimated_snr / .iter / .scheme / .timestamp`），
%       渲染为两个子图：
%         1. BER 散点+连线，按 BER 值语义染色，scheme 分色 marker
%         2. SNR 曲线（左 Y 轴） + turbo_iter 柱状（右 Y 轴）
% 版本：V1.0.0（2026-04-17 spec 2026-04-17-p3-demo-ui-sync-quality-viz Step 2）
% 输入：
%   history      — cell array of entry（最近最多 20 条）
%   axes_struct  — struct 含 ax_ber / ax_snr 两个 uiaxes 句柄

%% 1. 色板
S = p4_style();
P = S.PALETTE;
F = S.FONTS;

ax_ber = axes_struct.ax_ber;
ax_snr = axes_struct.ax_snr;

%% 2. 空数据占位
if isempty(history)
    cla(ax_ber);
    text(ax_ber, 0.5, 0.5, '(暂无解码数据，Transmit 至少 1 次)', ...
        'Units','normalized','HorizontalAlignment','center', ...
        'Color', P.text_muted, 'FontSize', 13);
    ax_ber.XColor = 'none'; ax_ber.YColor = 'none';
    ax_ber.BackgroundColor = P.surface; ax_ber.Color = P.surface;

    cla(ax_snr);
    text(ax_snr, 0.5, 0.5, '(暂无解码数据)', ...
        'Units','normalized','HorizontalAlignment','center', ...
        'Color', P.text_muted, 'FontSize', 13);
    ax_snr.XColor = 'none'; ax_snr.YColor = 'none';
    ax_snr.BackgroundColor = P.surface; ax_snr.Color = P.surface;
    return;
end

%% 3. 提取序列
N = length(history);
idx_seq  = 1:N;
ber_seq  = zeros(1, N);
snr_seq  = zeros(1, N);
iter_seq = zeros(1, N);
sch_seq  = cell(1, N);
for k = 1:N
    e = history{k};
    ber_seq(k)  = e.ber;
    snr_seq(k)  = 0;
    if isfield(e, 'info') && isfield(e.info, 'estimated_snr')
        snr_seq(k) = e.info.estimated_snr;
    end
    iter_seq(k) = e.iter;
    if isfield(e, 'scheme'), sch_seq{k} = e.scheme; else, sch_seq{k} = '?'; end
end

% BER 下限截断（为 semilogy）
ber_plot = max(ber_seq, 1e-6);

%% 4. BER tab：语义染色 + 连线
cla(ax_ber); hold(ax_ber, 'on');
for k = 1:N
    b = ber_seq(k);
    if b < 1e-4
        c_pt = P.success;      % BER < 0.01% 绿
    elseif b < 1e-2
        c_pt = P.warning;      % BER < 1% 黄
    else
        c_pt = P.danger;       % BER ≥ 1% 红
    end
    scatter(ax_ber, idx_seq(k), ber_plot(k), 60, c_pt, ...
        'filled', 'MarkerEdgeColor', P.text);
    if b < 1e-6
        % BER=0 额外 "✓" 标记
        text(ax_ber, idx_seq(k), ber_plot(k) * 0.3, '✓', ...
            'HorizontalAlignment','center', 'Color', P.success, ...
            'FontWeight','bold', 'FontSize', 10);
    end
end
% 连线（同 scheme 同色）
plot(ax_ber, idx_seq, ber_plot, ':', 'Color', P.divider, 'LineWidth', 0.8);

set(ax_ber, 'YScale', 'log');
ylim(ax_ber, [1e-6, max(0.5, max(ber_plot)*1.5)]);
xlim(ax_ber, [0.5, N+0.5]);
xlabel(ax_ber, '帧序号');
ylabel(ax_ber, 'BER (semilog)');
title(ax_ber, sprintf('BER 历史（%d 帧）', N), 'Color', P.primary_hi);
p4_style_axes(ax_ber);
hold(ax_ber, 'off');

%% 5. SNR tab：双 Y 轴
cla(ax_snr); hold(ax_snr, 'on');
% 左 Y：SNR 曲线
yyaxis(ax_snr, 'left');
plot(ax_snr, idx_seq, snr_seq, '-o', ...
    'Color', P.chart_cyan, 'LineWidth', 1.5, ...
    'MarkerFaceColor', P.chart_cyan, 'MarkerSize', 5);
ylabel(ax_snr, 'estimated\_snr (dB)');
ax_snr.YColor = P.chart_cyan;
ylim(ax_snr, [max(-20, min(snr_seq)-3), max(snr_seq)+3]);

% 右 Y：iter 柱状
yyaxis(ax_snr, 'right');
bar_w = 0.45;
for k = 1:N
    rectangle(ax_snr, 'Position', [idx_seq(k)-bar_w/2, 0, bar_w, iter_seq(k)], ...
        'FaceColor', [P.chart_amber 0.4], ...
        'EdgeColor', P.accent_hi, 'LineWidth', 0.6);
end
ylabel(ax_snr, 'turbo\_iter');
ax_snr.YColor = P.accent_hi;
ylim(ax_snr, [0, max(max(iter_seq)+1, 8)]);

xlim(ax_snr, [0.5, N+0.5]);
xlabel(ax_snr, '帧序号');
title(ax_snr, 'SNR 估计（青） + Turbo 迭代数（琥珀）', 'Color', P.primary_hi);
% 手动 axes 样式（yyaxis 后 p3_style_axes 可能打乱 Y 颜色，这里只补 grid/bg）
ax_snr.BackgroundColor = P.surface;
ax_snr.Color = P.surface;
ax_snr.XColor = P.text_muted;
ax_snr.GridColor = P.divider;
ax_snr.GridAlpha = 0.25;
ax_snr.GridLineStyle = ':';
ax_snr.XGrid = 'on'; ax_snr.YGrid = 'on';
ax_snr.FontName = F.code;
ax_snr.FontSize = 10;
hold(ax_snr, 'off');

end
