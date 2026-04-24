function p4_render_sync(entry, history, axes_struct, sys)
% P3_RENDER_SYNC  同步/多普勒 tab 四子图渲染（scheme 分支）
%
% 功能：
%   左上 — HFM+ 匹配滤波输出（来自 entry.sync_det.hfm_pos_corr）
%   左下 — HFM- 匹配滤波输出（entry.sync_det.hfm_neg_corr）
%   右上 — 符号级同步（scheme 分支：Turbo 画 sym_off_corr / FH-MFSK 画 hop peaks /
%          DSSS 画 rake finger / OTFS 画 DD path）
%   右下 — 历史检测偏差轨迹（sync_diff 随帧），代替未接入的 Doppler α 轨迹
% 版本：V1.0.0（2026-04-17 spec 2026-04-17-p3-demo-ui-sync-quality-viz Step 3）
% 输入：
%   entry        — 当前帧条目（含 sync_det / sync_diff / info / scheme）
%   history      — app.history cell array（用于历史偏差曲线）
%   axes_struct  — 四 axes：ax_hfm_pos / ax_hfm_neg / ax_sym_off / ax_doppler
%   sys          — 系统参数

S = p4_style();
P = S.PALETTE;
F = S.FONTS;

ax_hp = axes_struct.ax_hfm_pos;
ax_hn = axes_struct.ax_hfm_neg;
ax_so = axes_struct.ax_sym_off;
ax_dp = axes_struct.ax_doppler;

%% 1. 左上：HFM+ 匹配滤波
cla(ax_hp); hold(ax_hp, 'on');
if isfield(entry, 'sync_det') && ~isempty(entry.sync_det.hfm_pos_corr)
    det = entry.sync_det;
    t_ms = (0:length(det.hfm_pos_corr)-1) / sys.fs * 1000;
    plot(ax_hp, t_ms, det.hfm_pos_corr, '-', 'Color', P.chart_cyan, 'LineWidth', 1.0);
    yline(ax_hp, det.threshold, '--', 'Color', P.accent_hi, 'LineWidth', 1.0, ...
        'Label', 'threshold', 'LabelHorizontalAlignment', 'left');
    % 峰值 + GT 对齐（以 search window 为相对坐标）
    peak_local = det.fs_pos - det.search_abs_lo + 1;
    % filter 延迟 = N_pre - 1；peak 在 corr 图上是 peak_local + N_pre - 1
    N_pre = round(sys.preamble.dur * sys.fs);
    peak_corr_idx = peak_local + N_pre - 1;
    if peak_corr_idx >= 1 && peak_corr_idx <= length(det.hfm_pos_corr)
        xline(ax_hp, t_ms(peak_corr_idx), '-', 'Color', P.accent, ...
            'LineWidth', 1.5, 'Label', '检测峰');
    end
    title(ax_hp, sprintf('HFM+ 匹配滤波 (peak=%.0f, ratio=%.1f, conf=%.2f)', ...
        det.peak_val, det.peak_ratio, det.confidence), ...
        'Color', P.primary_hi);
    xlabel(ax_hp, 'time (ms)'); ylabel(ax_hp, '|corr|');
else
    text(ax_hp, 0.5, 0.5, '(无同步数据)', 'Units','normalized', ...
        'HorizontalAlignment','center','Color', P.text_muted, 'FontSize', 12);
    ax_hp.XColor='none'; ax_hp.YColor='none';
    ax_hp.BackgroundColor = P.surface; ax_hp.Color = P.surface;
end
p4_style_axes(ax_hp);
hold(ax_hp, 'off');

%% 2. 左下：HFM- 匹配滤波
cla(ax_hn); hold(ax_hn, 'on');
if isfield(entry, 'sync_det') && ~isempty(entry.sync_det.hfm_neg_corr)
    det = entry.sync_det;
    t_ms = (0:length(det.hfm_neg_corr)-1) / sys.fs * 1000;
    plot(ax_hn, t_ms, det.hfm_neg_corr, '-', 'Color', P.chart_amber, 'LineWidth', 1.0);
    title(ax_hn, 'HFM- 匹配滤波（反扫，用于 Doppler α 盲估计）', ...
        'Color', P.accent_hi);
    xlabel(ax_hn, 'time (ms)'); ylabel(ax_hn, '|corr|');
else
    text(ax_hn, 0.5, 0.5, '(无 HFM- 数据)', 'Units','normalized', ...
        'HorizontalAlignment','center','Color', P.text_muted, 'FontSize', 12);
    ax_hn.XColor='none'; ax_hn.YColor='none';
    ax_hn.BackgroundColor = P.surface; ax_hn.Color = P.surface;
end
p4_style_axes(ax_hn);
hold(ax_hn, 'off');

%% 3. 右上：符号级同步 — scheme 分支
cla(ax_so); hold(ax_so, 'on');
sch = '';
if isfield(entry, 'scheme'), sch = entry.scheme; end
info = entry.info;

if ismember(sch, {'SC-FDE','OFDM','SC-TDE'})
    % Turbo 体制：符号定时 corr 曲线
    if isfield(info, 'sym_off_corr') && ~isempty(info.sym_off_corr)
        corr_v = info.sym_off_corr;
        off_seq = 0:length(corr_v)-1;
        stem(ax_so, off_seq, corr_v, 'filled', 'LineWidth', 1.5, ...
            'Color', P.chart_cyan, 'MarkerFaceColor', P.chart_cyan);
        if isfield(info, 'sym_off_best')
            xline(ax_so, info.sym_off_best, '--', 'Color', P.accent_hi, ...
                'LineWidth', 1.5, 'Label', sprintf('best=%d', info.sym_off_best));
        end
        title(ax_so, sprintf('符号定时搜索（best_off=%d / sps=%d）', ...
            info.sym_off_best, length(corr_v)), 'Color', P.primary_hi);
        xlabel(ax_so, 'sps 偏移'); ylabel(ax_so, '|corr|');
        xlim(ax_so, [-0.5 length(corr_v)-0.5]);
    end
elseif strcmp(sch, 'FH-MFSK')
    if isfield(info, 'hop_peaks')
        peaks = info.hop_peaks;
        pat = info.hop_pattern;
        k_idx = 1:length(peaks);
        % 实际检测到的跳频频点 - 理论跳频序列 = 选中偏差（符号判决位置）
        plot(ax_so, k_idx, peaks, 'o', 'Color', P.chart_cyan, ...
            'MarkerFaceColor', P.chart_cyan, 'MarkerSize', 4);
        hold(ax_so, 'on');
        plot(ax_so, k_idx, mod(pat, 8), '.', 'Color', P.chart_amber, ...
            'MarkerSize', 2);
        title(ax_so, sprintf('FH-MFSK 频点判决（蓝=peak, 橙=跳频基准, %d 符号）', ...
            length(peaks)), 'Color', P.primary_hi);
        xlabel(ax_so, '符号 #'); ylabel(ax_so, '频点索引 (0..7)');
        ylim(ax_so, [-0.5 7.5]);
    end
elseif strcmp(sch, 'DSSS')
    if isfield(info, 'rake_finger_delays')
        dl = info.rake_finger_delays;
        gn = abs(info.rake_finger_gains);
        if ~isempty(dl)
            stem(ax_so, dl, gn, 'filled', 'LineWidth', 2, ...
                'Color', P.chart_cyan, 'MarkerFaceColor', P.chart_amber, ...
                'MarkerSize', 8);
            title(ax_so, sprintf('DSSS Rake 合并径（%d finger）', length(dl)), ...
                'Color', P.primary_hi);
            xlabel(ax_so, 'chip 级时延'); ylabel(ax_so, '|h|');
        end
    end
elseif strcmp(sch, 'OTFS')
    if isfield(info, 'dd_path_info')
        pi_ = info.dd_path_info;
        if pi_.num_paths > 0
            scatter(ax_so, pi_.delay_idx, pi_.doppler_idx, ...
                60*abs(pi_.gain)+20, abs(pi_.gain), 'filled', ...
                'MarkerEdgeColor', P.text);
            colormap(ax_so, 'turbo'); colorbar(ax_so);
            title(ax_so, sprintf('OTFS DD 域路径（%d 径）', pi_.num_paths), ...
                'Color', P.primary_hi);
            xlabel(ax_so, 'delay idx'); ylabel(ax_so, 'doppler idx');
        end
    end
else
    text(ax_so, 0.5, 0.5, sprintf('(未识别 scheme: %s)', sch), ...
        'Units','normalized','HorizontalAlignment','center', ...
        'Color', P.text_muted, 'FontSize', 12);
    ax_so.XColor='none'; ax_so.YColor='none';
end
p4_style_axes(ax_so);
hold(ax_so, 'off');

%% 4. 右下：历史同步偏差曲线（代替未接入的 Doppler α）
cla(ax_dp); hold(ax_dp, 'on');
if ~isempty(history)
    N = length(history);
    idx = 1:N;
    diffs = zeros(1, N);
    for k = 1:N
        if isfield(history{k}, 'sync_diff')
            diffs(k) = history{k}.sync_diff;
        end
    end
    stem(ax_dp, idx, diffs, 'filled', 'Color', P.chart_cyan, ...
        'MarkerFaceColor', P.chart_cyan, 'LineWidth', 1.2);
    yline(ax_dp, 0, '-', 'Color', P.success, 'LineWidth', 1, 'Label', 'GT');
    title(ax_dp, sprintf('同步检测偏差历史（%d 帧，|diff| 越小越好）', N), ...
        'Color', P.primary_hi);
    xlabel(ax_dp, '帧序号'); ylabel(ax_dp, 'fs\_pos - GT (samples)');
    % 注记 Doppler 未接入
    text(ax_dp, 0.02, 0.95, 'Doppler α 轨迹占位（链路未接入）', ...
        'Units','normalized','Color', P.text_dim, ...
        'FontSize', 9, 'FontName', F.code, ...
        'VerticalAlignment', 'top');
else
    text(ax_dp, 0.5, 0.5, '(无历史数据)', 'Units','normalized', ...
        'HorizontalAlignment','center','Color', P.text_muted, 'FontSize', 12);
    ax_dp.XColor='none'; ax_dp.YColor='none';
    ax_dp.BackgroundColor = P.surface; ax_dp.Color = P.surface;
end
p4_style_axes(ax_dp);
hold(ax_dp, 'off');

end
