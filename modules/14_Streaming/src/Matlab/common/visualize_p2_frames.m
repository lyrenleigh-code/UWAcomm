function visualize_p2_frames(session, sys, info, varargin)
% 功能：P2 多帧可视化，可输出独立 figure 或嵌入 UI uiaxes
% 版本：V1.0.0
% 输入：
%   session - 会话目录
%   sys     - 系统参数
%   info    - rx_stream_p2 返回的 info 结构（含 detected_starts, peaks_info, decoded, ...）
% 可选（name-value）：
%   'Axes'      struct，字段为各 panel 名对应的 axes 句柄；空则创建新 figure
%   'ChParams'  信道参数（用于 CIR panel）
%   'FrameIdx'  外层 wav 帧序号（默认 1）
%
% Panels（7 个）：
%   1. tx_wave    TX 多帧 passband + 各帧 HFM+ 边界标注
%   2. rx_wave    RX 多帧 passband + 检测到的 HFM+ 位置 + 期望位置
%   3. detection  匹配滤波 |corr| + 自适应阈值 + 检测峰
%   4. spectrum   TX vs RX 整段频谱对比
%   5. data_zoom  第 1 帧数据段时域放大对比
%   6. energy     第 1 帧 FSK 能量矩阵
%   7. cir        信道 CIR (静态 stem / 时变 2D 热图)

%% ---- 参数解析 ----
p = inputParser;
addParameter(p, 'Axes',     []);
addParameter(p, 'ChParams', []);
addParameter(p, 'FrameIdx', 1);
parse(p, varargin{:});
ax_struct = p.Results.Axes;
ch_params = p.Results.ChParams;
frame_idx_outer = p.Results.FrameIdx;

%% ---- 读波形 + meta ----
raw_dir = fullfile(session, 'raw_frames');
ch_dir  = fullfile(session, 'channel_frames');
[raw_pb, fs]  = wav_read_frame(raw_dir, frame_idx_outer);
[chan_pb, ~]  = wav_read_frame(ch_dir,  frame_idx_outer);

meta_tx = load(fullfile(raw_dir, sprintf('%04d.meta.mat', frame_idx_outer)));
N_frames     = meta_tx.N_frames;
single_len   = meta_tx.single_frame_samples;
fr_template  = meta_tx.frame_metas{1}{1};

%% ---- 创建 axes（若未传入）----
use_new_figure = isempty(ax_struct);
if use_new_figure
    fig = figure('Position', [40 40 1600 950], 'Name', 'Streaming P2 多帧可视化');
    sgtitle(fig, sprintf('Streaming P2 — %d 帧', N_frames), 'FontWeight', 'bold');
    ax_struct.tx_wave   = subplot(4, 2, 1);
    ax_struct.rx_wave   = subplot(4, 2, 2);
    ax_struct.detection = subplot(4, 2, [3 4]);
    ax_struct.spectrum  = subplot(4, 2, 5);
    ax_struct.data_zoom = subplot(4, 2, 6);
    ax_struct.energy    = subplot(4, 2, 7);
    ax_struct.cir       = subplot(4, 2, 8);
end

t_full_ms = (0:length(raw_pb)-1) / fs * 1000;

%% ---- Panel 1: TX 多帧波形 + 帧边界 ----
try
if isfield(ax_struct, 'tx_wave') && isvalid(ax_struct.tx_wave)
    ax = ax_struct.tx_wave; cla(ax, 'reset');
    plot(ax, t_full_ms, raw_pb, 'Color', [0 0.45 0.74], 'LineWidth', 0.3);
    xlabel(ax, '时间 (ms)'); ylabel(ax, '幅度'); grid(ax, 'on');
    title(ax, sprintf('TX 多帧 raw.wav (%d 帧, %.2fs)', N_frames, t_full_ms(end)/1000));

    yl = get(ax, 'YLim');
    hold(ax, 'on');
    for fi = 1:N_frames
        x_boundary = (fi-1) * single_len / fs * 1000;
        xline(ax, x_boundary, 'Color', [0.85 0.33 0.10], 'LineWidth', 1, ...
            'LineStyle', '--');
        % 在帧顶部标 idx
        text(ax, x_boundary + (single_len/fs*1000)/2, yl(2)*0.92, ...
            sprintf('#%d', fi), 'HorizontalAlignment', 'center', ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.85 0.33 0.10]);
    end
    hold(ax, 'off');
end
catch ME1, warning('viz P2 tx_wave: %s', ME1.message); end

%% ---- Panel 2: RX 多帧波形 + 检测 vs 期望位置 ----
try
if isfield(ax_struct, 'rx_wave') && isvalid(ax_struct.rx_wave)
    ax = ax_struct.rx_wave; cla(ax, 'reset');
    t_rx_ms = (0:length(chan_pb)-1) / fs * 1000;
    plot(ax, t_rx_ms, chan_pb, 'Color', [0.85 0.33 0.10], 'LineWidth', 0.3);
    xlabel(ax, '时间 (ms)'); ylabel(ax, '幅度'); grid(ax, 'on');
    title(ax, sprintf('RX 多帧 channel.wav + 检测 (det=%d / exp=%d)', ...
        info.N_detected, info.N_expected));

    hold(ax, 'on');
    % 期望位置（绿虚线）
    for fi = 1:N_frames
        x_exp = (fi-1) * single_len / fs * 1000;
        xline(ax, x_exp, 'g--', 'LineWidth', 0.8, 'Alpha', 0.5);
    end
    % 检测位置（红实线）
    for ki = 1:length(info.detected_starts)
        x_det = info.detected_starts(ki) / fs * 1000;
        xline(ax, x_det, 'Color', [0.9 0.1 0.1], 'LineWidth', 1.2, ...
            'Label', sprintf('#%d', ki), 'LabelVerticalAlignment', 'top', ...
            'FontSize', 8);
    end
    hold(ax, 'off');
end
catch ME2, warning('viz P2 rx_wave: %s', ME2.message); end

%% ---- Panel 3: 匹配滤波检测面板 ----
try
if isfield(ax_struct, 'detection') && isvalid(ax_struct.detection)
    ax = ax_struct.detection; cla(ax, 'reset');
    pi_ = info.peaks_info;
    t_corr = (0:length(pi_.corr_mag)-1) / fs * 1000;

    h_corr = plot(ax, t_corr, pi_.corr_mag, 'Color', [0 0.45 0.74], 'LineWidth', 0.6);
    hold(ax, 'on');
    h_th = yline(ax, pi_.threshold, 'Color', [0.85 0.10 0.10], ...
        'LineStyle', '--', 'LineWidth', 1.2, ...
        'Label', sprintf('阈值=%.0f', pi_.threshold));
    h_nf = yline(ax, pi_.noise_floor, 'Color', [0.5 0.5 0.5], ...
        'LineStyle', ':', 'LineWidth', 0.8, ...
        'Label', sprintf('noise=%.0f', pi_.noise_floor));

    % 检测峰位置（峰位 = HFM+ 头位置 + N_template - 1）
    N_tpl = pi_.N_template;
    for ki = 1:length(info.detected_starts)
        peak_pos = info.detected_starts(ki) + N_tpl - 1;
        x_peak = peak_pos / fs * 1000;
        xline(ax, x_peak, 'Color', [0.10 0.55 0.20], ...
            'LineWidth', 1, 'Alpha', 0.7);
    end
    hold(ax, 'off');
    xlabel(ax, '时间 (ms)'); ylabel(ax, '|匹配滤波|'); grid(ax, 'on');
    title(ax, sprintf('HFM+ 滑动检测：检测到 %d 峰（绿线）', length(info.detected_starts)));
    legend(ax, [h_corr, h_th, h_nf], ...
        {'|corr|', '阈值', '噪底'}, 'Location', 'best');
end
catch ME3, warning('viz P2 detection: %s', ME3.message); end

%% ---- Panel 4: 频谱对比 ----
try
if isfield(ax_struct, 'spectrum') && isvalid(ax_struct.spectrum)
    ax = ax_struct.spectrum; cla(ax, 'reset');
    Nfft = 2^nextpow2(length(raw_pb));
    F_raw = fft(raw_pb, Nfft);
    F_ch  = fft(chan_pb, Nfft);
    f_ax = (0:Nfft-1) * fs / Nfft / 1000;
    half = 1:Nfft/2;
    h_tx = plot(ax, f_ax(half), 20*log10(abs(F_raw(half)) + 1e-10), ...
        'Color', [0 0.45 0.74], 'LineWidth', 0.9); hold(ax, 'on');
    h_ch = plot(ax, f_ax(half), 20*log10(abs(F_ch(half)) + 1e-10), ...
        'Color', [0.85 0.33 0.10], 'LineWidth', 0.9);
    h1 = xline(ax, sys.fc/1000, 'k--', 'fc');                                       h1.HandleVisibility = 'off';
    h2 = xline(ax, (sys.fc - sys.fhmfsk.total_bw/2)/1000, 'm:', 'f_{lo}');          h2.HandleVisibility = 'off';
    h3 = xline(ax, (sys.fc + sys.fhmfsk.total_bw/2)/1000, 'm:', 'f_{hi}');          h3.HandleVisibility = 'off';
    hold(ax, 'off');
    xlabel(ax, '频率 (kHz)'); ylabel(ax, '|X| (dB)'); grid(ax, 'on');
    title(ax, '整段频谱对比');
    legend(ax, [h_tx, h_ch], {'TX 多帧', 'RX 多帧'}, 'Location', 'northeast');
    xlim(ax, [0 fs/2/1000]);
end
catch ME4, warning('viz P2 spectrum: %s', ME4.message); end

%% ---- Panel 5: 第 1 帧数据段时域对比（放大）----
try
if isfield(ax_struct, 'data_zoom') && isvalid(ax_struct.data_zoom)
    ax = ax_struct.data_zoom; cla(ax, 'reset');
    if ~isempty(info.detected_starts)
        % 从 RX 第 1 个检测起点 + frame data offset
        k1 = info.detected_starts(1);
        ds = k1 + fr_template.data_offset_from_lfm_head;
        ds_tx = (1-1)*single_len + fr_template.data_start;   % TX 第 1 帧 data 起点
        zoom_len = round(2e-3 * fs);   % 2 ms
        de = min(ds + zoom_len - 1, length(chan_pb));
        de_tx = min(ds_tx + zoom_len - 1, length(raw_pb));
        if ds < length(chan_pb) && ds_tx < length(raw_pb)
            t_zoom = (ds:de) / fs * 1000;
            t_zoom_tx = (ds_tx:de_tx) / fs * 1000;
            plot(ax, t_zoom_tx, raw_pb(ds_tx:de_tx), ...
                'Color', [0 0.45 0.74], 'LineWidth', 0.8); hold(ax, 'on');
            plot(ax, t_zoom, chan_pb(ds:de), ...
                'Color', [0.85 0.33 0.10], 'LineWidth', 0.8);
            hold(ax, 'off');
            xlabel(ax, '时间 (ms)'); ylabel(ax, '幅度'); grid(ax, 'on');
            title(ax, '第 1 帧数据段 2ms 放大（TX vs RX）');
            legend(ax, {'TX', 'RX'}, 'Location', 'best');
        end
    end
end
catch ME5, warning('viz P2 data_zoom: %s', ME5.message); end

%% ---- Panel 6: 第 1 帧 FSK 能量矩阵 ----
try
if isfield(ax_struct, 'energy') && isvalid(ax_struct.energy)
    ax = ax_struct.energy; cla(ax, 'reset');
    decoded = info.decoded{1};
    if ~isempty(decoded) && isfield(decoded{1}, 'k')
        % 重新计算第 1 帧的 energy_matrix（rx_stream_p2 没存）
        % 简化：标注本帧文本即可，要看能量矩阵跑 P1 demo
        text(ax, 0.5, 0.5, ...
            sprintf('第 1 帧解码: "%s"\n（FSK 能量矩阵详见 P1 单帧 demo）', ...
                decoded{1}.text), ...
            'Units', 'normalized', 'HorizontalAlignment', 'center', ...
            'FontSize', 12, 'Interpreter', 'none');
        axis(ax, 'off');
    else
        text(ax, 0.5, 0.5, '(无解码帧)', 'Units', 'normalized', ...
            'HorizontalAlignment', 'center', 'FontSize', 12);
        axis(ax, 'off');
    end
end
catch ME6, warning('viz P2 energy: %s', ME6.message); end

%% ---- Panel 7: 信道 CIR ----
try
if isfield(ax_struct, 'cir') && isvalid(ax_struct.cir)
    ax = ax_struct.cir; cla(ax, 'reset');
    chinfo_path = fullfile(session, 'channel_frames', sprintf('%04d.chinfo.mat', frame_idx_outer));
    has_chinfo = exist(chinfo_path, 'file') == 2;
    if has_chinfo, ci = load(chinfo_path); else, ci = []; end
    is_tv = ~isempty(ci) && isfield(ci, 'h_time') && ...
        isfield(ci, 'fading_type') && ~strcmpi(ci.fading_type, 'static');

    if is_tv
        h_abs = abs(ci.h_time);
        t_ms = ci.t_axis * 1000;
        delays_ms = ci.delays_s * 1000;
        step = max(1, round(length(t_ms) / 400));
        imagesc(ax, t_ms(1:step:end), delays_ms, h_abs(:, 1:step:end));
        axis(ax, 'xy'); colorbar(ax);
        xlabel(ax, '时间 (ms)'); ylabel(ax, '时延 (ms)');
        title(ax, sprintf('时变 |h(t,τ)|（%s, fd=%gHz）', ...
            ci.fading_type, getfield_or(ch_params, 'fading_fd_hz', 0)));
    elseif ~isempty(ch_params) && isfield(ch_params, 'delays_s')
        delays_ms = ch_params.delays_s * 1000;
        mags = abs(ch_params.gains);
        stem(ax, delays_ms, mags, 'filled', 'LineWidth', 1.8, ...
            'Color', [0 0.45 0.74], 'MarkerFaceColor', [0 0.45 0.74]);
        xlabel(ax, '时延 (ms)'); ylabel(ax, '|h|'); grid(ax, 'on');
        title(ax, sprintf('信道 CIR（静态 %d 径, SNR=%gdB）', ...
            length(delays_ms), ch_params.snr_db));
        xlim(ax, [-0.1, max(delays_ms)*1.3 + 0.2]);
        ylim(ax, [0, max(mags)*1.3]);
    else
        text(ax, 0.5, 0.5, '(信道参数未提供)', 'Units', 'normalized', ...
            'HorizontalAlignment', 'center'); axis(ax, 'off');
    end
end
catch ME7, warning('viz P2 cir: %s', ME7.message); end

end

% ================================================================
function v = getfield_or(s, fname, default)
if ~isempty(s) && isstruct(s) && isfield(s, fname), v = s.(fname); else, v = default; end
end
