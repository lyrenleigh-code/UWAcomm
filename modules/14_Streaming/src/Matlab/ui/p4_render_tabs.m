function p4_render_tabs(sch, entry, tabs, sys, history, style)
% 功能：从历史 entry 刷新 P3 UI 的底部 tab（除 scope 和 log）
% 版本：V1.0.0（2026-04-22 抽自 p3_demo_ui.m update_tabs_from_entry L1306-1743）
% 用法：p4_render_tabs(sch, entry, tabs, sys, history, style)
% 输入：
%   sch     体制名
%   entry   历史条目 struct（scheme/info/h_tap/meta/tx_body_bb_clean/
%           pb_seg/bypass_rf/ber 等，由 try_decode_frame 打包）
%   tabs    tab 句柄 struct（= app.tabs）：
%           compare_tx/compare_rx/spectrum/pre_eq/eq_it1/eq_mid/post_eq/
%           h_td/h_fd/quality_ber/quality_snr/sync_hfm_pos/sync_hfm_neg/
%           sync_sym_off/sync_doppler
%   sys     系统参数（只读）= app.sys
%   history cell or struct array = app.history（质量/同步 tab 需要）
%   style   渲染风格 struct：.PALETTE, .FONTS
% 备注：
%   - quality 与 sync tab 内部错误用 warning 替代原 append_log（外化后无法访问
%     宿主的 append_log 嵌套函数）
%   - draw_unit_circle 作为本文件 local function

    P = style.PALETTE;
    F = style.FONTS;

    render_compare(sch, entry, tabs.compare_tx, tabs.compare_rx, sys, P);
    render_spectrum(sch, entry, tabs.spectrum, sys, P);

    eq_axes = {tabs.pre_eq, tabs.eq_it1, tabs.eq_mid, tabs.post_eq};
    render_eq(sch, entry, eq_axes, P, F);

    render_channel(sch, entry, tabs.h_td, tabs.h_fd, sys, P);

    % --- 质量历史 tab ---
    try
        p4_render_quality(history, struct( ...
            'ax_ber', tabs.quality_ber, ...
            'ax_snr', tabs.quality_snr));
    catch ME_q
        warning('p3_render_tabs:quality', '%s', ME_q.message);
    end

    % --- 同步/多普勒 tab ---
    try
        p4_render_sync(entry, history, struct( ...
            'ax_hfm_pos', tabs.sync_hfm_pos, ...
            'ax_hfm_neg', tabs.sync_hfm_neg, ...
            'ax_sym_off', tabs.sync_sym_off, ...
            'ax_doppler', tabs.sync_doppler), sys);
    catch ME_s
        warning('p3_render_tabs:sync', '%s', ME_s.message);
    end
end

% ========== TX/RX 对比 ==========
function render_compare(sch, entry, ax_tx, ax_rx, sys, P)
    cla(ax_tx); cla(ax_rx);
    try
        tx_clean = entry.tx_body_bb_clean;
        rx_cmp   = entry.pb_seg;
        if isfield(entry, 'bypass_rf') && entry.bypass_rf
            tx_cmp = real(tx_clean);
            rx_cmp = real(rx_cmp);
            sr = sys.fs;
            if strcmp(sch, 'OTFS'), sr = sys.sym_rate; end
            lbl_mode = '基带 Re';
        else
            [tx_pb_clean, ~] = upconvert(tx_clean, sys.fs, sys.fc);
            tx_cmp = real(tx_pb_clean);
            sr = sys.fs;
            lbl_mode = '通带';
        end
        if ~isempty(tx_cmp) && ~isempty(rx_cmp)
            n_show = min(length(tx_cmp), length(rx_cmp));
            t_s = (0:n_show-1) / sr;
            plot(ax_tx, t_s, tx_cmp(1:n_show), ...
                'Color', P.chart_cyan, 'LineWidth', 0.8);
            title(ax_tx, sprintf('TX %s（%.2fs, %d 样本）', lbl_mode, t_s(end), n_show), ...
                'Color', P.primary_hi);
            xlabel(ax_tx, 's'); ylabel(ax_tx, 'amplitude');
            plot(ax_rx, t_s, rx_cmp(1:n_show), ...
                'Color', P.chart_amber, 'LineWidth', 0.8);
            title(ax_rx, sprintf('RX %s（含噪声+信道）', lbl_mode), ...
                'Color', P.accent_hi);
            xlabel(ax_rx, 's'); ylabel(ax_rx, 'amplitude');
            p4_style_axes({ax_tx, ax_rx});
            linkaxes([ax_tx, ax_rx], 'x');
        end
    catch
    end
end

% ========== 频谱 ==========
function render_spectrum(sch, entry, ax, sys, P)
    cla(ax);
    rx_seg2 = entry.pb_seg;
    Nfft = 8192;
    Pf = abs(fft(rx_seg2, Nfft));
    f_khz = (0:Nfft/2) / Nfft * sys.fs / 1000;
    P_pos = 20*log10(Pf(1:Nfft/2+1) + 1e-9);
    baseline = min(P_pos) - 3;
    ar = area(ax, f_khz, P_pos, baseline);
    ar.FaceColor = P.chart_cyan;
    ar.FaceAlpha = 0.28;
    ar.EdgeColor = P.primary_hi;
    ar.LineWidth = 1.0;
    xlabel(ax, '频率 (kHz)'); ylabel(ax, 'dB');
    title(ax, '通带频谱（接收信号）', 'Color', P.primary_hi);
    xline(ax, sys.fc/1000, '--', 'fc', ...
        'Color', P.accent, 'LabelVerticalAlignment', 'top', ...
        'LabelHorizontalAlignment', 'center');
    bw_rx = p4_downconv_bw(sch, sys);
    xline(ax, (sys.fc - bw_rx/2)/1000, ':', 'f_L', 'Color', P.success);
    xline(ax, (sys.fc + bw_rx/2)/1000, ':', 'f_H', 'Color', P.success);
    xlim(ax, [0, sys.fs/2/1000]);
    p4_style_axes(ax);
end

% ========== 均衡分析（按体制分派）==========
function render_eq(sch, entry, ax_cells, P, F)
    for k = 1:4, cla(ax_cells{k}); end
    info = entry.info;
    if strcmp(sch, 'FH-MFSK')
        render_eq_fhmfsk(entry, ax_cells, P);
    elseif strcmp(sch, 'DSSS')
        render_eq_dsss(entry, ax_cells, P, F);
    else
        render_eq_turbo(info, ax_cells, P);
    end
end

function render_eq_fhmfsk(entry, ax_cells, P)
    info = entry.info;
    if isfield(info, 'energy_matrix')
        ax = ax_cells{1};
        imagesc(ax, 10*log10(info.energy_matrix.' + 1e-12)); axis(ax,'tight');
        xlabel(ax,'符号 #'); ylabel(ax,'频点 #');
        title(ax,'能量矩阵 (dB)', 'Color', P.primary_hi);
        colormap(ax, 'turbo'); colorbar(ax);
        p4_style_axes(ax);
    end
    if isfield(info, 'soft_llr')
        L = info.soft_llr;
        ax = ax_cells{2};
        histogram(ax, L, 60, 'FaceColor', P.chart_cyan, ...
            'FaceAlpha', 0.7, 'EdgeColor', P.primary_hi);
        xlabel(ax,'LLR'); ylabel(ax,'count');
        title(ax, sprintf('软判决 LLR (med=%.1f)', median(abs(L))), ...
            'Color', P.primary_hi);
        p4_style_axes(ax);

        ax = ax_cells{3};
        plot(ax, 1:length(L), L, '.', 'MarkerSize', 4, 'Color', P.chart_amber);
        xlabel(ax,'bit #'); ylabel(ax,'LLR');
        title(ax,'LLR 序列', 'Color', P.accent_hi);
        p4_style_axes(ax);
    end
    ax = ax_cells{4};
    text(ax, 0.5, 0.5, sprintf('FH-MFSK\n无星座图\nBER=%.3f%%', entry.ber*100), ...
        'Units','normalized','HorizontalAlignment','center', ...
        'FontSize',13, 'Color', P.text);
    ax.XColor='none'; ax.YColor='none';
    ax.BackgroundColor = P.surface;
    ax.Color = P.surface;
end

function render_eq_dsss(entry, ax_cells, P, F)
    info = entry.info;
    ns_max = 3000;
    if isfield(info, 'pre_eq_syms') && ~isempty(info.pre_eq_syms)
        ax = ax_cells{1};
        s = info.pre_eq_syms; ns = min(ns_max, length(s));
        plot(ax, real(s(1:ns)), imag(s(1:ns)), '.', ...
            'MarkerSize', 5, 'Color', P.chart_cyan);
        hold(ax,'on');
        draw_unit_circle(ax, P);
        plot(ax, [-1 1], [0 0], 'x', 'MarkerSize', 13, 'LineWidth', 2.2, ...
            'Color', P.accent_hi);
        hold(ax,'off');
        axis(ax, 'equal'); title(ax, 'Rake 输出(DBPSK)', 'Color', P.primary_hi);
        xlabel(ax,'I'); ylabel(ax,'Q');
        p4_style_axes(ax);
    end
    if isfield(info, 'post_eq_syms') && ~isempty(info.post_eq_syms)
        ax = ax_cells{2};
        s = info.post_eq_syms; ns = min(ns_max, length(s));
        plot(ax, real(s(1:ns)), imag(s(1:ns)), '.', ...
            'MarkerSize', 5, 'Color', P.chart_violet);
        hold(ax,'on');
        draw_unit_circle(ax, P);
        plot(ax, [-1 1], [0 0], 'x', 'MarkerSize', 13, 'LineWidth', 2.2, ...
            'Color', P.accent_hi);
        hold(ax,'off');
        axis(ax, 'equal'); title(ax, '差分检测后', 'Color', P.primary_hi);
        xlabel(ax,'I'); ylabel(ax,'Q');
        p4_style_axes(ax);
    end
    ax = ax_cells{3};
    text(ax, 0.5, 0.5, sprintf('DSSS Gold31\n无Turbo迭代\n单次 Rake+DCD'), ...
        'Units','normalized','HorizontalAlignment','center', ...
        'FontSize',12, 'Color', P.text_muted);
    ax.XColor='none'; ax.YColor='none';
    ax.BackgroundColor = P.surface;
    ax.Color = P.surface;
    ax = ax_cells{4};
    ok_color = P.success;
    if entry.ber > 0.05, ok_color = P.warning; end
    if entry.ber > 0.20, ok_color = P.danger; end
    text(ax, 0.5, 0.5, sprintf('BER=%.3f%%\nSNR=%.1fdB', entry.ber*100, info.estimated_snr), ...
        'Units','normalized','HorizontalAlignment','center','FontSize',15, ...
        'FontWeight','bold', 'Color', ok_color, 'FontName', F.code);
    ax.XColor='none'; ax.YColor='none';
    ax.BackgroundColor = P.surface;
    ax.Color = P.surface;
end

function render_eq_turbo(info, ax_cells, P)
    ns_max = 3000;
    ref_qpsk = [1+1j,1-1j,-1+1j,-1-1j]/sqrt(2);
    has_iters = isfield(info, 'eq_syms_iters') && ~isempty(info.eq_syms_iters);
    sel = [1 1 1 1];
    if has_iters
        n_it = length(info.eq_syms_iters);
        if n_it >= 4
            sel = [1, round(n_it/3), round(2*n_it/3), n_it];
        elseif n_it == 3
            sel = [1, 2, 2, 3];
        elseif n_it == 2
            sel = [1, 1, 2, 2];
        end
    end

    % 列 1：均衡前
    ax = ax_cells{1};
    if isfield(info,'pre_eq_syms') && ~isempty(info.pre_eq_syms)
        s = info.pre_eq_syms; ns = min(ns_max, length(s));
        scatter(ax, real(s(1:ns)), imag(s(1:ns)), 6, P.chart_cyan, ...
            'filled', 'MarkerFaceAlpha', 0.35);
        hold(ax,'on');
        draw_unit_circle(ax, P);
        plot(ax, real(ref_qpsk), imag(ref_qpsk), 'x', ...
            'MarkerSize', 11, 'LineWidth', 2.2, 'Color', P.accent_hi);
        hold(ax,'off');
        axis(ax, 'equal'); title(ax, '均衡前', 'Color', P.primary_hi);
        xlabel(ax,'I'); ylabel(ax,'Q');
    end
    p4_style_axes(ax);

    % 列 2/3/4
    iter_colors = {P.chart_cyan, P.chart_violet, P.chart_amber};
    for ci = 2:4
        ax = ax_cells{ci};
        pt_color = iter_colors{ci-1};
        if has_iters && sel(ci) <= length(info.eq_syms_iters)
            it_idx = sel(ci);
            s = info.eq_syms_iters{it_idx}; ns = min(ns_max, length(s));
            scatter(ax, real(s(1:ns)), imag(s(1:ns)), 6, pt_color, ...
                'filled', 'MarkerFaceAlpha', 0.45);
            hold(ax,'on');
            draw_unit_circle(ax, P);
            plot(ax, real(ref_qpsk), imag(ref_qpsk), 'x', ...
                'MarkerSize', 11, 'LineWidth', 2.2, 'Color', P.accent_hi);
            hold(ax,'off');
            axis(ax, 'equal');
            if ci == 4
                title(ax, sprintf('iter %d (末)', it_idx), 'Color', P.accent_hi);
            else
                title(ax, sprintf('iter %d', it_idx), 'Color', P.primary_hi);
            end
            xlabel(ax,'I');
        elseif isfield(info,'post_eq_syms') && ~isempty(info.post_eq_syms)
            s = info.post_eq_syms; ns = min(ns_max, length(s));
            scatter(ax, real(s(1:ns)), imag(s(1:ns)), 6, pt_color, ...
                'filled', 'MarkerFaceAlpha', 0.45);
            hold(ax,'on');
            draw_unit_circle(ax, P);
            plot(ax, real(ref_qpsk), imag(ref_qpsk), 'x', ...
                'MarkerSize', 11, 'LineWidth', 2.2, 'Color', P.accent_hi);
            hold(ax,'off');
            axis(ax, 'equal'); title(ax, '均衡后', 'Color', P.accent_hi);
            xlabel(ax,'I');
        end
        p4_style_axes(ax);
    end
end

% ========== 信道（OTFS: DD 域 / 其他: CIR + 频响）==========
function render_channel(sch, entry, ax_td, ax_fd, sys, P)
    cla(ax_td); cla(ax_fd);
    info = entry.info;
    h_tap = entry.h_tap;

    if strcmp(sch, 'OTFS') && isfield(info, 'h_dd') && ~isempty(info.h_dd)
        render_channel_otfs(entry, ax_td, ax_fd, P);
    elseif length(h_tap) <= 1
        render_channel_awgn(ax_td, ax_fd, P);
    else
        render_channel_multipath(sch, entry, ax_td, ax_fd, sys, P);
    end
end

function render_channel_otfs(entry, ax_td, ax_fd, P)
    info = entry.info;
    h_tap = entry.h_tap;
    h_dd_est = info.h_dd;
    [N_dd, M_dd] = size(h_dd_est);
    sps_use = entry.meta.sps;

    h_dd_true = zeros(N_dd, M_dd);
    for k_tap = 1:length(h_tap)
        if abs(h_tap(k_tap)) > 1e-6
            tau_sym = round((k_tap-1) / sps_use);
            if tau_sym >= 0 && tau_sym < M_dd
                h_dd_true(1, tau_sym+1) = h_dd_true(1, tau_sym+1) + h_tap(k_tap);
            end
        end
    end

    dl_range = 0:M_dd-1;
    dk_range = -floor(N_dd/2) : ceil(N_dd/2)-1;

    to_dB = @(M) 20*log10(max(M, eps) / max(max(M(:)), eps));
    db_lo = -30;

    hdd_true_mag = abs(h_dd_true);
    hdd_true_db = to_dB(hdd_true_mag);
    hdd_true_shift = fftshift(hdd_true_db, 1);
    imagesc(ax_td, dl_range, dk_range, hdd_true_shift);
    axis(ax_td, 'xy');
    clim(ax_td, [db_lo, 0]);
    colormap(ax_td, 'turbo');
    cbar_t = colorbar(ax_td); cbar_t.Color = P.text_muted;
    cbar_t.Label.String = 'dB';
    n_true_paths = sum(hdd_true_mag(:) > 1e-6);
    title(ax_td, sprintf('真实 DD |h_{true}|  (%d 径)', n_true_paths), ...
        'Color', P.primary_hi);
    xlabel(ax_td, '时延 delay (l)'); ylabel(ax_td, '多普勒 doppler (k)');
    p4_style_axes(ax_td);

    hdd_est_mag = abs(h_dd_est);
    hdd_est_db = to_dB(hdd_est_mag);
    hdd_est_shift = fftshift(hdd_est_db, 1);
    imagesc(ax_fd, dl_range, dk_range, hdd_est_shift);
    axis(ax_fd, 'xy');
    clim(ax_fd, [db_lo, 0]);
    colormap(ax_fd, 'turbo');
    cbar_e = colorbar(ax_fd); cbar_e.Color = P.text_muted;
    cbar_e.Label.String = 'dB';

    if isfield(info, 'path_info') && ~isempty(info.path_info) && ...
       info.path_info.num_paths > 0
        pi_ = info.path_info;
        dk_c = pi_.doppler_idx(:);
        dk_c(dk_c >= N_dd/2) = dk_c(dk_c >= N_dd/2) - N_dd;
        hold(ax_fd, 'on');
        scatter(ax_fd, pi_.delay_idx(:), dk_c, ...
            40 + 200*abs(pi_.gain(:))/(max(abs(pi_.gain))+eps), ...
            P.text, 'o', 'LineWidth', 1.2);
        hold(ax_fd, 'off');
        title(ax_fd, sprintf('估计 DD |h_{est}| + path (%d 径)', pi_.num_paths), ...
            'Color', P.accent_hi);
    else
        title(ax_fd, '估计 DD |h_{est}| (无 path)', 'Color', P.accent_hi);
    end
    xlabel(ax_fd, '时延 delay (l)'); ylabel(ax_fd, '多普勒 doppler (k)');
    p4_style_axes(ax_fd);
end

function render_channel_awgn(ax_td, ax_fd, P)
    text(ax_td, 0.5, 0.5, 'AWGN  ·  无多径', 'Units','normalized', ...
        'HorizontalAlignment','center', 'FontSize', 14, ...
        'FontWeight', 'bold', 'Color', P.primary);
    text(ax_fd, 0.5, 0.5, 'AWGN  ·  平坦频响', 'Units','normalized', ...
        'HorizontalAlignment','center', 'FontSize', 14, ...
        'FontWeight', 'bold', 'Color', P.primary);
    ax_td.XColor='none'; ax_td.YColor='none';
    ax_fd.XColor='none'; ax_fd.YColor='none';
    ax_td.BackgroundColor = P.surface;
    ax_td.Color = P.surface;
    ax_fd.BackgroundColor = P.surface;
    ax_fd.Color = P.surface;
end

function render_channel_multipath(sch, entry, ax_td, ax_fd, sys, P)
    info = entry.info;
    h_tap = entry.h_tap;

    % 采样率
    if strcmp(sch, 'DSSS')
        h_fs = sys.fs;
    elseif strcmp(sch, 'OTFS')
        h_fs = sys.sym_rate;
    else
        h_fs = sys.fs;
    end

    % 时域 CIR
    t_true_sec = (0:length(h_tap)-1) / h_fs;
    h_true_handles = p4_plot_channel_stem(ax_td, t_true_sec, h_tap, ...
        'Label', '|h| 真实');
    hold(ax_td, 'on');
    has_est_td = false;
    h_est_rep = [];
    if strcmp(sch, 'DSSS') && isfield(info, 'h_est') && isfield(info, 'chip_delays')
        t_est_ms = info.chip_delays * sys.dsss.sps / h_fs * 1000;
        h_est_rep = stem(ax_td, t_est_ms, abs(info.h_est), 'LineWidth', 1.2, ...
            'Color', P.danger, 'MarkerSize', 5, ...
            'MarkerFaceColor', P.danger_bg, ...
            'MarkerEdgeColor', P.danger);
        has_est_td = true;
    elseif ismember(sch, {'SC-FDE','OFDM','SC-TDE'}) && isfield(info, 'H_est_block1')
        h_est_td = ifft(info.H_est_block1);
        t_est_ms = (0:length(h_est_td)-1) / sys.sym_rate * 1000;
        h_est_rep = stem(ax_td, t_est_ms, abs(h_est_td), 'LineWidth', 1.2, ...
            'Color', P.danger, 'MarkerSize', 4, ...
            'MarkerFaceColor', P.danger_bg, ...
            'MarkerEdgeColor', P.danger);
        has_est_td = true;
    end
    hold(ax_td, 'off');
    % P4: 在标题后附 α(t) 统计（若 entry 含 alpha_true）
    title_str = '时域 CIR  ·  真实(渐变) vs 估计(红)';
    if isfield(entry, 'alpha_true') && ~isempty(entry.alpha_true)
        at = entry.alpha_true;
        title_str = sprintf('%s  |  α(t) mean=%.2e std=%.2e', ...
            title_str, mean(at), std(at));
    end
    title(ax_td, title_str, 'Color', P.primary_hi);
    if has_est_td
        if ~isempty(h_true_handles.stems) && ...
           isgraphics(h_true_handles.stems(1)) && isgraphics(h_est_rep)
            lgd = legend(ax_td, [h_true_handles.stems(1), h_est_rep], ...
                {'|h| 真实', '|h| 估计'}, 'Location', 'best');
            lgd.Color = P.surface_alt;
            lgd.TextColor = P.text;
            lgd.EdgeColor = P.border_subtle;
        end
    end
    p4_style_axes(ax_td);

    % 频响
    bw_rx = p4_downconv_bw(sch, sys);
    Nf = 512;
    H_true = fft(h_tap, Nf);
    f_hz = (0:Nf-1)/Nf * h_fs - h_fs/2;
    H_true_db = 20*log10(abs(fftshift(H_true))+1e-9);
    baseline_fd = min(H_true_db) - 3;
    ar_true = area(ax_fd, f_hz/1000, H_true_db, baseline_fd);
    ar_true.FaceColor = P.chart_cyan;
    ar_true.FaceAlpha = 0.25;
    ar_true.EdgeColor = P.primary_hi;
    ar_true.LineWidth = 1.3;
    hold(ax_fd, 'on');
    has_est_fd = false;
    if ismember(sch, {'SC-FDE','OFDM','SC-TDE'}) && isfield(info, 'H_est_block1')
        H_est = info.H_est_block1;
        Nf_est = length(H_est);
        f_est_hz = (0:Nf_est-1)/Nf_est * sys.sym_rate - sys.sym_rate/2;
        plot(ax_fd, f_est_hz/1000, 20*log10(abs(fftshift(H_est))+1e-9), ...
            '--', 'LineWidth', 1.3, 'Color', P.chart_amber);
        has_est_fd = true;
    elseif strcmp(sch, 'DSSS') && isfield(info, 'h_est') && isfield(info, 'chip_delays')
        h_est_full = zeros(1, Nf);
        est_samp = info.chip_delays * sys.dsss.sps;
        for p = 1:length(est_samp)
            if est_samp(p)+1 <= Nf
                h_est_full(est_samp(p)+1) = info.h_est(p);
            end
        end
        H_est_d = fft(h_est_full, Nf);
        plot(ax_fd, f_hz/1000, 20*log10(abs(fftshift(H_est_d))+1e-9), ...
            '--', 'LineWidth', 1.3, 'Color', P.chart_amber);
        has_est_fd = true;
    end
    hold(ax_fd, 'off');
    xlim(ax_fd, [-bw_rx/2/1000 * 1.1, bw_rx/2/1000 * 1.1]);
    xlabel(ax_fd, '频率 (kHz)'); ylabel(ax_fd, '|H(f)| (dB)');
    title(ax_fd, sprintf('频域响应 (BW=%.1fkHz)', bw_rx/1000), ...
        'Color', P.primary_hi);
    if has_est_fd
        lgd = legend(ax_fd, {'真实', '估计'}, 'Location', 'best');
        lgd.Color = P.surface_alt;
        lgd.TextColor = P.text;
        lgd.EdgeColor = P.border_subtle;
    end
    p4_style_axes(ax_fd);
end

% ========== 辅助：单位圆 ==========
function draw_unit_circle(ax, P)
    th = linspace(0, 2*pi, 128);
    line(ax, cos(th), sin(th), 'Color', P.text_muted, 'LineWidth', 0.6);
    line(ax, [-1.3 1.3], [0 0], 'Color', P.divider, 'LineStyle', ':', 'LineWidth', 0.5);
    line(ax, [0 0], [-1.3 1.3], 'Color', P.divider, 'LineStyle', ':', 'LineWidth', 0.5);
end
