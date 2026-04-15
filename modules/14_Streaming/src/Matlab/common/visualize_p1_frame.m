function visualize_p1_frame(session, sys, info, varargin)
% 功能：P1 帧的丰富可视化，可输出到独立 figure 或嵌入到 UI 的 uiaxes
% 版本：V1.0.0
% 输入：
%   session - 会话目录
%   sys     - 系统参数
%   info    - rx_stream_p1 返回的 info 结构（含 hdr, lfm_pos, decode_info, ...）
% 可选（name-value）：
%   'Axes'      - struct，字段为各 panel 名称对应的 axes 句柄；
%                 缺省则创建新 figure 带 subplots
%   'ChParams'  - 信道参数（用于 CIR panel 展示真实信道）
%   'FrameIdx'  - 帧序号（默认 1）
%
% Panels（7 个）：
%   1. tx_wave   TX 通带波形 + 帧结构标注
%   2. rx_wave   RX 通带波形（channel.wav）+ 帧结构 + 检测 LFM 位
%   3. spectrum  TX vs Channel 频谱对比
%   4. time_zoom 数据段时域对比（TX vs Channel 放大）
%   5. lfm_sync  LFM 匹配滤波峰（标注搜索窗口与实际峰）
%   6. energy    FSK 能量矩阵（前 N 符号）
%   7. cir       信道 CIR stems + 频响

%% ---- 参数解析 ----
p = inputParser;
addParameter(p, 'Axes',     []);
addParameter(p, 'ChParams', []);
addParameter(p, 'FrameIdx', 1);
parse(p, varargin{:});
ax_struct = p.Results.Axes;
ch_params = p.Results.ChParams;
frame_idx = p.Results.FrameIdx;

%% ---- 读波形 ----
raw_dir = fullfile(session, 'raw_frames');
ch_dir  = fullfile(session, 'channel_frames');
[raw_pb, fs]  = wav_read_frame(raw_dir, frame_idx);
[chan_pb, ~]  = wav_read_frame(ch_dir,  frame_idx);

% 读 TX meta（帧结构）
meta_tx = load(fullfile(raw_dir, sprintf('%04d.meta.mat', frame_idx)));
fr = meta_tx.frame;

%% ---- 创建 axes（若未传入）----
use_new_figure = isempty(ax_struct);
if use_new_figure
    fig = figure('Position', [60 60 1500 960], 'Name', 'Streaming P1 可视化');
    sgtitle(fig, sprintf('Streaming P1 — frame %04d', frame_idx), 'FontWeight', 'bold');
    ax_struct.tx_wave   = subplot(4, 2, 1);
    ax_struct.rx_wave   = subplot(4, 2, 2);
    ax_struct.spectrum  = subplot(4, 2, 3);
    ax_struct.time_zoom = subplot(4, 2, 4);
    ax_struct.lfm_sync  = subplot(4, 2, 5);
    ax_struct.energy    = subplot(4, 2, 6);
    ax_struct.cir       = subplot(4, 2, [7 8]);
end

%% ---- Panel 1: TX 通带波形 + 帧结构 ----
try
if isfield(ax_struct, 'tx_wave') && isvalid(ax_struct.tx_wave)
    ax = ax_struct.tx_wave; cla(ax, 'reset');
    t_ms = (0:length(raw_pb)-1) / fs * 1000;
    plot(ax, t_ms, raw_pb, 'Color', [0 0.45 0.74], 'LineWidth', 0.4);
    xlabel(ax, '时间 (ms)'); ylabel(ax, '幅度'); grid(ax, 'on');
    title(ax, sprintf('TX raw.wav (fc=%dHz, 总长 %.1fms)', sys.fc, t_ms(end)));

    % 帧边界（cell 数组：混合数字+字符串必须用 {}）
    segs = { ...
        0,                                          fr.N_pre,                                   'HFM+'; ...
        fr.N_pre + fr.guard_samp,                   fr.N_pre + fr.guard_samp + fr.N_pre,        'HFM-'; ...
        2*fr.N_pre + 2*fr.guard_samp,               2*fr.N_pre + 2*fr.guard_samp + fr.N_lfm,    'LFM1'; ...
        2*fr.N_pre + 3*fr.guard_samp + fr.N_lfm,    2*fr.N_pre + 3*fr.guard_samp + 2*fr.N_lfm,  'LFM2'; ...
        fr.data_start - 1,                          fr.data_start - 1 + fr.body_samples,        'DATA'};
    yl = get(ax, 'YLim');
    hold(ax, 'on');
    colors = [0.85 0.33 0.10; 0.47 0.67 0.19; 0.30 0.75 0.93; 0.30 0.75 0.93; 0.49 0.18 0.56];
    for s = 1:size(segs, 1)
        x0 = segs{s, 1} / fs * 1000;
        x1 = segs{s, 2} / fs * 1000;
        patch(ax, [x0 x1 x1 x0], [yl(1) yl(1) yl(2) yl(2)], colors(s,:), ...
            'FaceAlpha', 0.08, 'EdgeColor', 'none');
        text(ax, (x0+x1)/2, yl(2)*0.9, segs{s,3}, ...
            'HorizontalAlignment','center', 'FontSize', 9, 'FontWeight', 'bold', ...
            'Color', colors(s,:));
    end
    hold(ax, 'off');
end
catch ME1, warning('viz panel tx_wave: %s', ME1.message); end

%% ---- Panel 1b: RX 通带波形（channel.wav）+ 帧结构 + 检测 LFM 位 ----
try
if isfield(ax_struct, 'rx_wave') && isvalid(ax_struct.rx_wave)
    ax = ax_struct.rx_wave; cla(ax, 'reset');
    t_ms = (0:length(chan_pb)-1) / fs * 1000;
    plot(ax, t_ms, chan_pb, 'Color', [0.85 0.33 0.10], 'LineWidth', 0.4);
    xlabel(ax, '时间 (ms)'); ylabel(ax, '幅度'); grid(ax, 'on');
    title(ax, sprintf('RX channel.wav (fc=%dHz, 总长 %.1fms, 含信道+噪声)', ...
        sys.fc, t_ms(end)));

    yl = get(ax, 'YLim');
    hold(ax, 'on');
    % 帧结构半透明色带（名义位置，TX 帧按理是相同布局）
    segs_rx = { ...
        0,                                          fr.N_pre,                                   'HFM+'; ...
        fr.N_pre + fr.guard_samp,                   fr.N_pre + fr.guard_samp + fr.N_pre,        'HFM-'; ...
        2*fr.N_pre + 2*fr.guard_samp,               2*fr.N_pre + 2*fr.guard_samp + fr.N_lfm,    'LFM1'; ...
        2*fr.N_pre + 3*fr.guard_samp + fr.N_lfm,    2*fr.N_pre + 3*fr.guard_samp + 2*fr.N_lfm,  'LFM2'; ...
        fr.data_start - 1,                          fr.data_start - 1 + fr.body_samples,        'DATA'};
    colors = [0.85 0.33 0.10; 0.47 0.67 0.19; 0.30 0.75 0.93; 0.30 0.75 0.93; 0.49 0.18 0.56];
    for s = 1:size(segs_rx, 1)
        x0 = segs_rx{s, 1} / fs * 1000;
        x1 = segs_rx{s, 2} / fs * 1000;
        patch(ax, [x0 x1 x1 x0], [yl(1) yl(1) yl(2) yl(2)], colors(s,:), ...
            'FaceAlpha', 0.06, 'EdgeColor', 'none');
        text(ax, (x0+x1)/2, yl(2)*0.9, segs_rx{s,3}, ...
            'HorizontalAlignment','center', 'FontSize', 9, 'FontWeight', 'bold', ...
            'Color', colors(s,:));
    end
    % 实际检测到的 LFM2 头部（用红色竖线）
    det_ms = info.lfm_pos / fs * 1000;
    xline(ax, det_ms, 'r-', sprintf('LFM2 detected (peak=%.3f)', info.sync_peak), ...
        'LineWidth', 1.5, 'LabelVerticalAlignment', 'bottom');
    % 数据段起点（由检测 LFM 推出）
    data_start_ms = (info.lfm_pos + fr.data_offset_from_lfm_head) / fs * 1000;
    xline(ax, data_start_ms, 'g--', 'DATA start (detected)', ...
        'LineWidth', 1.2, 'LabelVerticalAlignment', 'top');
    hold(ax, 'off');
end
catch ME1b, warning('viz panel rx_wave: %s', ME1b.message); end

%% ---- Panel 2: 频谱对比 ----
try
if isfield(ax_struct, 'spectrum') && isvalid(ax_struct.spectrum)
    ax = ax_struct.spectrum; cla(ax, 'reset');
    Nfft = 2^nextpow2(length(raw_pb));
    F_raw = fft(raw_pb, Nfft);
    F_ch  = fft(chan_pb, Nfft);
    f_ax = (0:Nfft-1) * fs / Nfft / 1000;   % kHz
    half = 1:Nfft/2;
    h_tx = plot(ax, f_ax(half), 20*log10(abs(F_raw(half)) + 1e-10), ...
        'Color', [0 0.45 0.74], 'LineWidth', 0.9); hold(ax, 'on');
    h_ch = plot(ax, f_ax(half), 20*log10(abs(F_ch(half))  + 1e-10), ...
        'Color', [0.85 0.33 0.10], 'LineWidth', 0.9);
    h1 = xline(ax, sys.fc/1000, 'k--', 'fc');                                       h1.HandleVisibility = 'off';
    h2 = xline(ax, (sys.fc - sys.fhmfsk.total_bw/2)/1000, 'm:', 'f_{lo}');          h2.HandleVisibility = 'off';
    h3 = xline(ax, (sys.fc + sys.fhmfsk.total_bw/2)/1000, 'm:', 'f_{hi}');          h3.HandleVisibility = 'off';
    hold(ax, 'off');
    xlabel(ax, '频率 (kHz)'); ylabel(ax, '|X| (dB)'); grid(ax, 'on');
    title(ax, 'TX vs Channel 频谱');
    legend(ax, [h_tx, h_ch], {'TX raw', 'channel'}, 'Location', 'northeast');
    xlim(ax, [0 fs/2/1000]);
end
catch ME2, warning('viz panel spectrum: %s', ME2.message); end

%% ---- Panel 3: 数据段时域对比（放大）----
try
if isfield(ax_struct, 'time_zoom') && isvalid(ax_struct.time_zoom)
    ax = ax_struct.time_zoom; cla(ax, 'reset');
    % 放大 data 段前 2ms
    ds = fr.data_start;
    de = min(ds + round(2e-3 * fs) - 1, length(raw_pb));
    t_zoom = (ds:de) / fs * 1000;
    plot(ax, t_zoom, raw_pb(ds:de), 'Color', [0 0.45 0.74], 'LineWidth', 0.8); hold(ax, 'on');
    plot(ax, t_zoom, chan_pb(ds:de), 'Color', [0.85 0.33 0.10], 'LineWidth', 0.8);
    hold(ax, 'off');
    xlabel(ax, '时间 (ms)'); ylabel(ax, '幅度'); grid(ax, 'on');
    title(ax, sprintf('数据段前 %dms（TX vs Channel）', 2));
    legend(ax, {'TX raw', 'channel'}, 'Location', 'best');
end
catch ME3, warning('viz panel time_zoom: %s', ME3.message); end

%% ---- Panel 4: LFM 同步峰 ----
try
if isfield(ax_struct, 'lfm_sync') && isvalid(ax_struct.lfm_sync)
    ax = ax_struct.lfm_sync; cla(ax, 'reset');
    % 重新计算相关图（匹配 detect_lfm_start 的逻辑）
    [bb_raw, ~] = downconvert(chan_pb, sys.fs, sys.fc, sys.fhmfsk.total_bw);
    [~, ~, corr_mag] = detect_lfm_start(bb_raw, sys, fr);
    t_corr = (0:length(corr_mag)-1) / fs * 1000;

    h_corr = plot(ax, t_corr, corr_mag, 'Color', [0 0.45 0.74], 'LineWidth', 0.6);
    hold(ax, 'on');
    % 标注搜索窗口
    x_win_lo = (fr.lfm2_peak_nom - fr.guard_samp - 200) / fs * 1000;
    x_win_hi = (fr.lfm2_peak_nom + fr.guard_samp + 200) / fs * 1000;
    yl = get(ax, 'YLim');
    h_win = patch(ax, [x_win_lo x_win_hi x_win_hi x_win_lo], ...
        [yl(1) yl(1) yl(2) yl(2)], [0.9 0.9 0.2], ...
        'FaceAlpha', 0.15, 'EdgeColor', 'none');
    % 实际检测峰
    peak_sample = info.lfm_pos + fr.N_lfm - 1;
    h_det = xline(ax, peak_sample / fs * 1000, 'r-', ...
        sprintf('detected (peak=%.3f)', info.sync_peak), 'LineWidth', 1.5);
    h_th = xline(ax, fr.lfm2_peak_nom / fs * 1000, 'g--', 'theoretical');
    hold(ax, 'off');
    xlabel(ax, '时间 (ms)'); ylabel(ax, '|corr|'); grid(ax, 'on');
    title(ax, 'LFM2 匹配滤波峰');
    legend(ax, [h_corr, h_win, h_det, h_th], ...
        {'|corr|', 'search win', 'detected', 'theoretical'}, ...
        'Location', 'best');
end
catch ME4, warning('viz panel lfm_sync: %s', ME4.message); end

%% ---- Panel 5: FSK 能量矩阵 ----
try
if isfield(ax_struct, 'energy') && isvalid(ax_struct.energy)
    ax = ax_struct.energy; cla(ax, 'reset');
    em = info.decode_info.energy_matrix;
    N_show = min(60, size(em, 1));
    imagesc(ax, 1:N_show, sys.fhmfsk.fb_base/1000, em(1:N_show, :).');
    axis(ax, 'xy'); colorbar(ax);
    xlabel(ax, '符号序号'); ylabel(ax, '基带频率 (kHz)');
    title(ax, sprintf('FSK 能量矩阵（前 %d / %d 符号）', N_show, size(em, 1)));
end
catch ME5, warning('viz panel energy: %s', ME5.message); end

%% ---- Panel 6: 信道 CIR（静态 stem / 时变 2D heatmap）----
try
if isfield(ax_struct, 'cir') && isvalid(ax_struct.cir)
    ax = ax_struct.cir; cla(ax, 'reset');

    % 读 ch_info（含 h_time 时变抽头矩阵）
    chinfo_path = fullfile(session, 'channel_frames', sprintf('%04d.chinfo.mat', frame_idx));
    has_chinfo = exist(chinfo_path, 'file') == 2;
    if has_chinfo
        ci = load(chinfo_path);
    else
        ci = [];
    end

    is_timevarying = ~isempty(ci) && isfield(ci, 'h_time') && ...
        isfield(ci, 'fading_type') && ~strcmpi(ci.fading_type, 'static');

    if is_timevarying
        % 2D heatmap: |h(t, τ)|
        h_abs = abs(ci.h_time);                   % P × N
        t_ms  = ci.t_axis * 1000;                  % 1 × N
        delays_ms = ci.delays_s * 1000;            % 1 × P

        % 子采样时间轴（防止像素爆炸）
        step = max(1, round(length(t_ms) / 400));
        t_show = t_ms(1:step:end);
        h_show = h_abs(:, 1:step:end);

        imagesc(ax, t_show, delays_ms, h_show);
        axis(ax, 'xy'); colorbar(ax);
        xlabel(ax, '时间 (ms)'); ylabel(ax, '时延 (ms)');
        title(ax, sprintf('时变信道 |h(t,\\tau)|（%s, fd=%gHz, %d径, SNR=%gdB）', ...
            ci.fading_type, ...
            getfield_or(ch_params, 'fading_fd_hz', 0), ...
            length(delays_ms), ch_params.snr_db));
    elseif ~isempty(ch_params) && isfield(ch_params, 'delays_s')
        % 静态：stem
        delays_ms = ch_params.delays_s * 1000;
        mags = abs(ch_params.gains);
        stem(ax, delays_ms, mags, 'filled', 'LineWidth', 1.8, ...
            'Color', [0 0.45 0.74], 'MarkerFaceColor', [0 0.45 0.74]);
        hold(ax, 'on');
        for p = 1:length(delays_ms)
            text(ax, delays_ms(p), mags(p) + 0.05, ...
                sprintf('\\angle%.1f°', angle(ch_params.gains(p))*180/pi), ...
                'HorizontalAlignment', 'center', 'FontSize', 8);
        end
        hold(ax, 'off');
        xlabel(ax, '时延 (ms)'); ylabel(ax, '|h|'); grid(ax, 'on');
        title(ax, sprintf('信道 CIR（静态, %d 径, SNR=%gdB）', ...
            length(delays_ms), ch_params.snr_db));
        xlim(ax, [-0.1, max(delays_ms) * 1.3 + 0.2]);
        ylim(ax, [0, max(mags) * 1.3]);
    else
        text(ax, 0.5, 0.5, '(信道参数未提供)', 'Units', 'normalized', ...
            'HorizontalAlignment', 'center');
        axis(ax, 'off');
    end
end
catch ME6, warning('viz panel cir: %s', ME6.message); end

end

% ================================================================
function v = getfield_or(s, fname, default)
if ~isempty(s) && isstruct(s) && isfield(s, fname), v = s.(fname); else, v = default; end
end
