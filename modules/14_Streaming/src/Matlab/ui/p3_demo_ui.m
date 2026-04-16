function p3_demo_ui()
% 功能：Streaming P3.1 流式 GUI demo —— RX 持续监听 + TX 触发发送 + 实时通带示波器
% 版本：V3.0.0
% 用法：在 MATLAB 命令行执行 p3_demo_ui()
%
% 架构（单进程 timer 模拟"软件无线电"）：
%   - RX 开关：on 时，timer 100ms 持续画通带示波器、检测帧、触发解调
%   - TX 触发：点 Transmit → modem_encode → 基带卷积+复 AWGN → upconvert → 切片入 FIFO
%   - FIFO 共享 ring：TX 推 / RX 读，timer 每 tick 推一个 50ms 切片（2× 加速）
%   - 解调时机：RX 累积满一帧通带样本后自动 downconvert + modem_decode
%
% V3 变更：
%   - 解码历史（最多 20 条）+ RX 下拉选择 → 切换 tab 显示
%   - 信道 tab 拆为 时域 / 频域
%   - 日志移至底部 tab；TX 面板改为信号信息面板
%   - 移除 p3_diag.txt 诊断输出和直通对照测试

%% ---- 路径注册 ----
this_dir       = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
mod14_root     = fileparts(fileparts(streaming_root));
modules_root   = fileparts(mod14_root);
proj_root      = fileparts(modules_root);
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(modules_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(modules_root, '03_Interleaving',  'src', 'Matlab'));
addpath(fullfile(modules_root, '05_SpreadSpectrum','src', 'Matlab'));
addpath(fullfile(modules_root, '06_MultiCarrier',  'src', 'Matlab'));
addpath(fullfile(modules_root, '07_ChannelEstEq',  'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform',      'src', 'Matlab'));
addpath(fullfile(modules_root, '12_IterativeProc', 'src', 'Matlab'));

%% ---- 全局状态 ----
app = struct();
app.proj_root = proj_root;
app.sys = sys_params_default();

% FIFO（passband real 样本 ring buffer）
app.fifo_capacity = round(8 * app.sys.fs);
app.fifo = zeros(1, app.fifo_capacity);
app.fifo_write = 0;
app.fifo_read  = 0;

% TX 待叠加的信号（passband real）+ 起始绝对位置
app.tx_signal       = [];
app.tx_signal_start = 0;
app.tx_meta_pending = struct();
app.tx_h_tap        = [];
app.tx_pending      = false;

% 噪声底
app.noise_var_pb = 0.05;

% RX 状态
app.rx_running = false;
app.last_decode_at = 0;
app.last_info = [];
app.last_bits_in = [];
app.last_bits_out = [];
app.last_text_bits_len = 0;

% Scope 持久句柄
app.scope_line = [];
app.scope_window_s = 0.4;
app.last_body_bb_rx = [];

% 信号检测
app.det_status = '空闲';

% Timer
app.timer = [];
app.tick_ms = 100;
app.chunk_ms = 50;

% RF bypass
app.bypass_rf = false;

% 解码历史（cell array of structs, 最多 20）
app.history = {};
app.dec_count = 0;

%% ---- 主 figure ----
app.fig = uifigure('Name', 'Streaming P3 — 软件无线电流式 Demo', ...
    'Position', [40 40 1500 950], 'Color', [0.95 0.95 0.96], ...
    'CloseRequestFcn', @(~,~) on_close());

main = uigridlayout(app.fig, [3 1]);
main.RowHeight   = {110, '1x', 320};
main.ColumnWidth = {'1x'};
main.Padding     = [10 10 10 10];
main.RowSpacing  = 8;

%% ==== 顶栏 ====
top = uigridlayout(main, [1 5]);
top.Layout.Row = 1;
top.ColumnWidth = {'1x', 280, 220, 240, 140, 80};

title_lbl = uilabel(top, 'Text', 'Streaming P3 — 软件无线电流式 Demo', ...
    'FontSize', 17, 'FontWeight', 'bold', 'FontColor', [0.1 0.3 0.6]);
title_lbl.Layout.Column = 1;

% scheme 下拉 + RF bypass
sch_panel = uigridlayout(top, [2 2]);
sch_panel.Layout.Column = 2;
sch_panel.ColumnWidth = {'fit', '1x'};
sch_panel.RowHeight = {'1x', 22};
sch_panel.RowSpacing = 2;
uilabel(sch_panel, 'Text', '调制:', 'FontSize', 12, 'HorizontalAlignment', 'right');
app.scheme_dd = uidropdown(sch_panel, ...
    'Items', {'FH-MFSK (8-FSK 跳频, 非相干)', 'SC-FDE (QPSK + Turbo, 相干)', ...
              'OFDM (QPSK + Turbo, 相干)', 'SC-TDE (QPSK + Turbo, 相干)'}, ...
    'Value', 'SC-FDE (QPSK + Turbo, 相干)', ...
    'FontSize', 12, ...
    'ValueChangedFcn', @(~,~) on_scheme_changed());
app.bypass_chk = uicheckbox(sch_panel, ...
    'Text', 'Bypass RF (复基带直通, 调试用)', ...
    'Value', false, 'FontSize', 10, ...
    'ValueChangedFcn', @(~,~) on_bypass_changed());
app.bypass_chk.Layout.Row = 2; app.bypass_chk.Layout.Column = [1 2];

% RX 开关
rx_sw_panel = uigridlayout(top, [1 2]);
rx_sw_panel.Layout.Column = 3;
rx_sw_panel.ColumnWidth = {'fit', '1x'};
uilabel(rx_sw_panel, 'Text', 'RX 监听:', 'FontSize', 13, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'right');
app.rx_switch = uiswitch(rx_sw_panel, 'slider', 'Items', {'OFF', 'ON'}, ...
    'Value', 'OFF', 'FontSize', 12, ...
    'ValueChangedFcn', @(~,~) on_rx_switch());

% status
app.status_lbl = uilabel(top, 'Text', 'Ready', ...
    'FontSize', 13, 'HorizontalAlignment', 'center', ...
    'BackgroundColor', [0.90 0.95 0.90], 'FontColor', [0.1 0.5 0.1]);
app.status_lbl.Layout.Column = 4;

% Transmit
app.tx_btn = uibutton(top, 'push', 'Text', 'Transmit', ...
    'FontSize', 15, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.2 0.6 0.3], 'FontColor', 'white', ...
    'ButtonPushedFcn', @(~,~) on_transmit());
app.tx_btn.Layout.Column = 5;

% 音频监听开关
app.monitor_btn = uibutton(top, 'state', 'Text', 'Mon', ...
    'FontSize', 12, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.3 0.45 0.7], 'FontColor', 'white', ...
    'ValueChangedFcn', @(src,~) on_monitor_toggle(src));
app.monitor_btn.Layout.Column = 6;
app.audio_monitor = false;
app.audio_buf = [];
app.audio_play_until = 0;

%% ==== 中部：TX | RX ====
mid = uigridlayout(main, [1 2]);
mid.Layout.Row = 2;
mid.ColumnWidth = {'1x', '1x'};
mid.ColumnSpacing = 10;

%% ---- TX panel ----
tx_panel = uipanel(mid, 'Title', 'TX 发射端', 'FontSize', 13, ...
    'FontWeight', 'bold', 'BackgroundColor', [0.98 0.98 1.0]);
tx_panel.Layout.Column = 1;
tx_grid = uigridlayout(tx_panel, [13 2]);
tx_grid.RowHeight = {25, 55, 25, 28, 28, 28, 28, 28, 28, 28, 28, 25, '1x'};
tx_grid.ColumnWidth = {140, '1x'};
tx_grid.RowSpacing = 4;

% 文本输入
lbl_txt = uilabel(tx_grid, 'Text', '发射文本:', 'FontWeight', 'bold');
lbl_txt.Layout.Row = 1;
app.text_in = uitextarea(tx_grid, ...
    'Value', sprintf(['Hello 水声通信 P3.1 流式 demo\n' ...
                      '点击 Transmit 启动一帧发射，RX 持续监听并解调']), ...
    'FontSize', 12);
app.text_in.Layout.Row = [1 2]; app.text_in.Layout.Column = 2;

% 信道参数
lbl_ch = uilabel(tx_grid, 'Text', '信道参数:', 'FontWeight', 'bold');
lbl_ch.Layout.Row = 3;

[~, app.snr_edit] = mk_row(tx_grid, 4, 'SNR (dB):', 'numeric', 15, [-20 40]);
[~, app.doppler_edit] = mk_row(tx_grid, 5, '多普勒 (Hz):', 'numeric', 0, [-50 50]);

lbl_fad = uilabel(tx_grid, 'Text', '衰落类型:');
lbl_fad.Layout.Row = 6; lbl_fad.Layout.Column = 1;
app.fading_dd = uidropdown(tx_grid, ...
    'Items', {'static (恒定)', 'slow (Jakes 慢衰落)', 'fast (Jakes 快衰落)'}, ...
    'Value', 'static (恒定)');
app.fading_dd.Layout.Row = 6; app.fading_dd.Layout.Column = 2;

[~, app.jakes_fd_edit] = mk_row(tx_grid, 7, 'Jakes fd (Hz):', 'numeric', 2, [0 20]);

lbl_pre = uilabel(tx_grid, 'Text', '信道预设:');
lbl_pre.Layout.Row = 8; lbl_pre.Layout.Column = 1;
app.preset_dd = uidropdown(tx_grid, ...
    'Items', {'AWGN (无多径)', '6径 标准水声', '6径 深衰减', '3径 短时延'}, ...
    'Value', '6径 标准水声');
app.preset_dd.Layout.Row = 8; app.preset_dd.Layout.Column = 2;

% scheme 特定（动态显示）
lbl_mod = uilabel(tx_grid, 'Text', '调制参数:', 'FontWeight', 'bold');
lbl_mod.Layout.Row = 9;

% SC-FDE 参数（行 10/11）
app.lbl_blk = uilabel(tx_grid, 'Text', 'blk_fft:');
app.lbl_blk.Layout.Row = 10; app.lbl_blk.Layout.Column = 1;
app.blk_dd  = uidropdown(tx_grid, ...
    'Items', {'128 (推荐)', '256', '512'}, 'Value', '128 (推荐)');
app.blk_dd.Layout.Row = 10; app.blk_dd.Layout.Column = 2;

app.lbl_iter = uilabel(tx_grid, 'Text', 'Turbo 迭代:');
app.lbl_iter.Layout.Row = 11; app.lbl_iter.Layout.Column = 1;
app.iter_edit = uieditfield(tx_grid, 'numeric', 'Value', 6, ...
    'Limits', [1 15], 'RoundFractionalValues', 'on', 'ValueDisplayFormat', '%d');
app.iter_edit.Layout.Row = 11; app.iter_edit.Layout.Column = 2;

% FH-MFSK payload
app.lbl_pl = uilabel(tx_grid, 'Text', 'payload bits:');
app.lbl_pl.Layout.Row = 10; app.lbl_pl.Layout.Column = 1;
app.pl_dd  = uidropdown(tx_grid, ...
    'Items', {'256', '512', '1024', '2048 (默认)'}, 'Value', '2048 (默认)');
app.pl_dd.Layout.Row = 10; app.pl_dd.Layout.Column = 2;

% TX 信号信息面板（替换原 Log 区域）
txinfo_panel = uipanel(tx_grid, 'Title', 'TX 信号信息', 'FontSize', 11);
txinfo_panel.Layout.Row = [12 13]; txinfo_panel.Layout.Column = [1 2];
txinfo_grid = uigridlayout(txinfo_panel, [1 1]); txinfo_grid.Padding = [5 5 5 5];
app.txinfo_area = uitextarea(txinfo_grid, 'Editable', 'off', ...
    'FontName', 'Consolas', 'FontSize', 10, ...
    'Value', '(Transmit 后显示信号统计)');

%% ---- RX panel ----
rx_rpanel = uipanel(mid, 'Title', 'RX 接收端', 'FontSize', 13, ...
    'FontWeight', 'bold', 'BackgroundColor', [1.0 0.98 0.95]);
rx_rpanel.Layout.Column = 2;

rx_grid = uigridlayout(rx_rpanel, [5 1]);
rx_grid.RowHeight = {25, 110, 90, 30, '1x'};
rx_grid.RowSpacing = 6;

% 解码文本 header（带 Clear 按钮）
hdr_grid = uigridlayout(rx_grid, [1 2]);
hdr_grid.ColumnWidth = {'1x', 100};
hdr_grid.Padding = [0 0 0 0];
uilabel(hdr_grid, 'Text', '解码文本（自动）:', 'FontWeight', 'bold');
app.clear_btn = uibutton(hdr_grid, 'push', 'Text', 'Clear', ...
    'BackgroundColor', [0.9 0.9 0.9], ...
    'ButtonPushedFcn', @(~,~) on_clear());
app.text_out = uitextarea(rx_grid, 'Editable', 'off', ...
    'Value', '(打开 RX 监听 → 点 Transmit → 检测+解码)', ...
    'FontSize', 12);

% BER 大字 + 监听状态
ber_panel = uipanel(rx_grid, 'Title', 'BER / 监听状态', 'FontSize', 11);
ber_grid = uigridlayout(ber_panel, [2 4]);
ber_grid.RowHeight = {30, 30};
ber_grid.ColumnWidth = {120, '1x', 120, '1x'};
ber_grid.Padding = [10 6 10 6];
uilabel(ber_grid, 'Text', '比特 BER:', 'FontName','Consolas');
app.lbl_ber = uilabel(ber_grid, 'Text', '—', 'FontName','Consolas', ...
    'FontSize', 22, 'FontWeight', 'bold', 'FontColor', [0.1 0.4 0.7]);
uilabel(ber_grid, 'Text', '错误/总:', 'FontName','Consolas');
app.lbl_err = uilabel(ber_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');
uilabel(ber_grid, 'Text', 'FIFO 长度:', 'FontName','Consolas');
app.lbl_fifo = uilabel(ber_grid, 'Text', '0 样本', 'FontName','Consolas','FontWeight','bold');
uilabel(ber_grid, 'Text', '检测状态:', 'FontName','Consolas');
app.lbl_det = uilabel(ber_grid, 'Text', '空闲', 'FontName','Consolas','FontWeight','bold');

% 解码历史下拉
hist_grid = uigridlayout(rx_grid, [1 2]);
hist_grid.ColumnWidth = {100, '1x'};
hist_grid.Padding = [0 0 0 0];
uilabel(hist_grid, 'Text', '解码历史:', 'FontWeight', 'bold');
app.hist_dd = uidropdown(hist_grid, ...
    'Items', {'(无)'}, 'Value', '(无)', ...
    'ValueChangedFcn', @(~,~) on_history_select());

% info struct
info_panel = uipanel(rx_grid, 'Title', '解码 info', 'FontSize', 11);
info_grid = uigridlayout(info_panel, [4 4]);
info_grid.RowHeight = {25, 25, 25, 25};
info_grid.ColumnWidth = {130, '1x', 130, '1x'};
info_grid.Padding = [10 6 10 6];
info_grid.RowSpacing = 2;

uilabel(info_grid, 'Text', 'estimated_snr:', 'FontName','Consolas');
app.lbl_esnr = uilabel(info_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');
uilabel(info_grid, 'Text', 'estimated_ber:', 'FontName','Consolas');
app.lbl_eber = uilabel(info_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');
uilabel(info_grid, 'Text', 'turbo_iter:', 'FontName','Consolas');
app.lbl_iter_show = uilabel(info_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');
uilabel(info_grid, 'Text', 'convergence:', 'FontName','Consolas');
app.lbl_conv = uilabel(info_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');
uilabel(info_grid, 'Text', 'noise_var:', 'FontName','Consolas');
app.lbl_nv = uilabel(info_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');
uilabel(info_grid, 'Text', '解码次数:', 'FontName','Consolas');
app.lbl_dec_cnt = uilabel(info_grid, 'Text', '0', 'FontName','Consolas','FontWeight','bold');
uilabel(info_grid, 'Text', 'TX bits:', 'FontName','Consolas');
app.lbl_txb = uilabel(info_grid, 'Text', '—', 'FontName','Consolas','FontSize',9);
uilabel(info_grid, 'Text', 'RX bits:', 'FontName','Consolas');
app.lbl_rxb = uilabel(info_grid, 'Text', '—', 'FontName','Consolas','FontSize',9);

%% ==== 底部 7 tab ====
bot = uitabgroup(main); bot.Layout.Row = 3;
app.tabs = struct();

% 带 axes 的 tab
ax_tab_specs = {
    'scope',    '实时通带示波器';
    'spectrum', '通带频谱';
    'pre_eq',   '均衡前 / 能量矩阵';
    'post_eq',  '均衡后 / 软 LLR';
    'h_td',     '信道(时域)';
    'h_fd',     '信道(频域)'};
for ti = 1:size(ax_tab_specs,1)
    tab = uitab(bot, 'Title', ax_tab_specs{ti,2});
    tg = uigridlayout(tab, [1 1]); tg.Padding = [8 8 8 8];
    ax = uiaxes(tg);
    if ti == 1
        text(ax, 0.5, 0.5, '打开 RX 监听并点 Transmit', ...
            'Units','normalized','HorizontalAlignment','center', ...
            'FontSize', 14, 'Color', [0.5 0.5 0.5]);
    else
        text(ax, 0.5, 0.5, '解码后显示', ...
            'Units','normalized','HorizontalAlignment','center', ...
            'FontSize', 14, 'Color', [0.5 0.5 0.5]);
    end
    ax.XColor = 'none'; ax.YColor = 'none';
    app.tabs.(ax_tab_specs{ti,1}) = ax;
end

% 日志 tab（uitextarea, 无 axes）
log_tab = uitab(bot, 'Title', '日志');
log_tg = uigridlayout(log_tab, [1 1]); log_tg.Padding = [8 8 8 8];
app.log_area = uitextarea(log_tg, 'Editable', 'off', ...
    'FontName', 'Consolas', 'FontSize', 10);

%% ---- 启动定时器 ----
app.timer = timer('ExecutionMode','fixedSpacing', 'Period', app.tick_ms/1000, ...
    'TimerFcn', @(~,~) on_tick(), 'BusyMode', 'drop');
start(app.timer);

%% ---- 初始化 ----
append_log('[UI] p3_demo_ui 启动');
append_log(sprintf('[UI] fs=%dHz fc=%dHz tick=%dms chunk=%dms (%.1fx 加速)', ...
    app.sys.fs, app.sys.fc, app.tick_ms, app.chunk_ms, app.tick_ms/app.chunk_ms));
on_scheme_changed();

%% ============================================================
%% 内部函数
%% ============================================================
function [lbl, edt] = mk_row(g, row, label, type, val, lim)
    lbl = uilabel(g, 'Text', label);
    lbl.Layout.Row = row; lbl.Layout.Column = 1;
    edt = uieditfield(g, type, 'Value', val, 'Limits', lim, ...
        'ValueDisplayFormat', '%g');
    edt.Layout.Row = row; edt.Layout.Column = 2;
end

function on_scheme_changed()
    sch = current_scheme();
    is_turbo = ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE'});
    is_fhmfsk = strcmp(sch, 'FH-MFSK');
    show(app.lbl_blk,  is_turbo); show(app.blk_dd,    is_turbo);
    show(app.lbl_iter, is_turbo); show(app.iter_edit, is_turbo);
    show(app.lbl_pl,   is_fhmfsk); show(app.pl_dd,    is_fhmfsk);
    append_log(sprintf('[UI] scheme -> %s', sch));
end

function s = current_scheme()
    sel = app.scheme_dd.Value;
    if startsWith(sel, 'SC-FDE'), s = 'SC-FDE';
    elseif startsWith(sel, 'OFDM'), s = 'OFDM';
    elseif startsWith(sel, 'SC-TDE'), s = 'SC-TDE';
    else, s = 'FH-MFSK';
    end
end

function show(h, vis)
    if vis, h.Visible = 'on'; else, h.Visible = 'off'; end
end

function on_bypass_changed()
    app.bypass_rf = logical(app.bypass_chk.Value);
    if app.bypass_rf
        app.fifo = complex(zeros(1, app.fifo_capacity));
        append_log('[BYPASS] RF 旁路 ON — 复基带直通');
    else
        app.fifo = zeros(1, app.fifo_capacity);
        append_log('[BYPASS] RF 旁路 OFF — 通带路径');
    end
    app.fifo_write = 0; app.fifo_read = 0;
    app.tx_signal = []; app.tx_pending = false; app.tx_meta_pending = struct();
    app.last_decode_at = 0;
end

function on_rx_switch()
    if strcmp(app.rx_switch.Value, 'ON')
        app.rx_running = true;
        append_log(sprintf('[RX] 监听 ON  噪声底 var=%.3e', app.noise_var_pb));
        set_status('RX 监听中', [0.1 0.5 0.7]);
    else
        app.rx_running = false;
        append_log('[RX] 监听 OFF');
        set_status('Ready', [0.1 0.5 0.1]);
    end
end

function on_clear()
    app.fifo(:) = 0;
    app.fifo_write = 0; app.fifo_read = 0;
    app.last_decode_at = 0;
    app.tx_signal = []; app.tx_signal_start = 0; app.tx_pending = false;
    app.tx_meta_pending = struct();
    app.last_info = []; app.last_bits_in = []; app.last_bits_out = [];
    app.dec_count = 0;
    app.history = {};
    app.hist_dd.Items = {'(无)'}; app.hist_dd.Value = '(无)';
    app.text_out.Value = '(已清空)';
    app.text_out.FontColor = [0.3 0.3 0.3];
    app.lbl_ber.Text = '—'; app.lbl_ber.FontColor = [0.1 0.4 0.7];
    app.lbl_err.Text = '—';
    app.lbl_esnr.Text = '—'; app.lbl_eber.Text = '—';
    app.lbl_iter_show.Text = '—'; app.lbl_conv.Text = '—';
    app.lbl_nv.Text = '—'; app.lbl_dec_cnt.Text = '0';
    app.lbl_txb.Text = '—'; app.lbl_rxb.Text = '—';
    app.lbl_det.Text = '空闲';
    app.txinfo_area.Value = '(Transmit 后显示信号统计)';
    if ~isempty(app.scope_line) && isvalid(app.scope_line)
        delete(app.scope_line); app.scope_line = [];
    end
    cla(app.tabs.scope, 'reset');
    cla(app.tabs.spectrum, 'reset');
    cla(app.tabs.pre_eq, 'reset');
    cla(app.tabs.post_eq, 'reset');
    cla(app.tabs.h_td, 'reset');
    cla(app.tabs.h_fd, 'reset');
    append_log('[CLEAR] RX + FIFO + 历史 已清空');
end

function on_monitor_toggle(src)
    app.audio_monitor = logical(src.Value);
    if app.audio_monitor
        app.audio_buf = [];
        app.audio_play_until = 0;
        src.Text = 'Mon ON';
        src.BackgroundColor = [0.7 0.3 0.2];
        append_log('[MON] 音频监听 ON');
    else
        app.audio_buf = [];
        src.Text = 'Mon';
        src.BackgroundColor = [0.3 0.45 0.7];
        append_log('[MON] 音频监听 OFF');
    end
end

function flush_audio()
    if ~app.audio_monitor, return; end
    min_n = round(0.3 * app.sys.fs);   % 攒够 300ms 再播
    if length(app.audio_buf) < min_n, return; end
    % 上一段尚未播完 → 跳过
    if app.audio_play_until > now, return; end
    sig = app.audio_buf;
    app.audio_buf = [];
    if ~isreal(sig), sig = real(sig); end
    peak = max(abs(sig)) + 1e-12;
    sig = sig / peak * 0.8;
    sound(sig, app.sys.fs);
    app.audio_play_until = now + length(sig)/app.sys.fs/86400;  % datenum 偏移
end

function on_close()
    try, stop(app.timer); delete(app.timer); catch, end
    try, clear sound; catch, end
    delete(app.fig);
end

function on_transmit()
    try
        sch = current_scheme();
        if ~app.rx_running
            append_log('[!] 请先打开 RX 监听');
            set_status('请先打开 RX 监听', [0.7 0.4 0.1]);
            return;
        end

        % --- 应用参数 ---
        mem = app.sys.codec.constraint_len - 1;
        if strcmp(sch, 'SC-FDE')
            app.sys.scfde.blk_fft    = parse_lead_int(app.blk_dd.Value);
            app.sys.scfde.blk_cp     = app.sys.scfde.blk_fft;
            app.sys.scfde.N_blocks   = 32;
            app.sys.scfde.turbo_iter = app.iter_edit.Value;
            app.sys.scfde.fading_type = 'static';
            app.sys.scfde.fd_hz       = 0;
            N_info = app.sys.scfde.blk_fft * app.sys.scfde.N_blocks - mem;
        elseif strcmp(sch, 'OFDM')
            app.sys.ofdm.blk_fft    = parse_lead_int(app.blk_dd.Value);
            app.sys.ofdm.blk_cp     = round(app.sys.ofdm.blk_fft / 2);
            app.sys.ofdm.N_blocks   = 16;
            app.sys.ofdm.turbo_iter = app.iter_edit.Value;
            app.sys.ofdm.fading_type = 'static';
            app.sys.ofdm.fd_hz       = 0;
            null_idx_tmp = 1:app.sys.ofdm.null_spacing:app.sys.ofdm.blk_fft;
            N_data_sc = app.sys.ofdm.blk_fft - length(null_idx_tmp);
            N_info = N_data_sc * app.sys.ofdm.N_blocks - mem;
        elseif strcmp(sch, 'SC-TDE')
            app.sys.sctde.turbo_iter = app.iter_edit.Value;
            app.sys.sctde.fading_type = 'static';
            app.sys.sctde.fd_hz       = 0;
            N_data_sym = 2000;
            N_info = N_data_sym - mem;
        else
            pl = parse_lead_int(app.pl_dd.Value);
            app.sys.frame.payload_bits = pl;
            app.sys.frame.body_bits = app.sys.frame.header_bits + pl + ...
                app.sys.frame.payload_crc_bits;
            N_info = app.sys.frame.body_bits;
        end

        % --- 信源：文本 -> bits ---
        txt = app.text_in.Value;
        if iscell(txt), txt = strjoin(txt, newline); end
        txt = strtrim(txt);
        if isempty(txt), txt = 'demo'; end
        bits_raw = text_to_bits(txt);
        if length(bits_raw) >= N_info
            info_bits = bits_raw(1:N_info);
            app.last_text_bits_len = N_info;
        else
            rng_st = rng; rng(42);
            pad = randi([0 1], 1, N_info - length(bits_raw));
            rng(rng_st);
            info_bits = [bits_raw, pad];
            app.last_text_bits_len = length(bits_raw);
        end
        app.last_bits_in = info_bits;

        % --- modem encode ---
        [body_bb, meta_tx] = modem_encode(info_bits, sch, app.sys);

        % --- 基带信道 ---
        [h_tap, ch_label] = build_channel_tap(sch);
        rx_clean = conv(body_bb, h_tap);
        rx_clean = rx_clean(1:length(body_bb));

        snr_db = app.snr_edit.Value;
        app.tx_meta_pending = meta_tx;
        app.tx_meta_pending.scheme = sch;
        app.tx_h_tap = h_tap;

        if app.bypass_rf
            sig_pwr_bb = mean(abs(rx_clean).^2);
            nv_bb = sig_pwr_bb * 10^(-snr_db/10);
            app.noise_var_pb = nv_bb;
            app.tx_signal = rx_clean;
            app.tx_signal_start = app.fifo_write + 1;
            app.tx_pending = true;
            app.tx_meta_pending.noise_var = nv_bb;
            app.tx_meta_pending.frame_start_write = app.tx_signal_start;
            app.tx_meta_pending.frame_pb_samples  = length(rx_clean);
            append_log(sprintf('[TX-BYPASS] %s %s body=%d, nv=%.3e (SNR=%gdB)', ...
                sch, ch_label, length(body_bb), nv_bb, snr_db));
        else
            [tx_pb, ~] = upconvert(rx_clean, app.sys.fs, app.sys.fc);
            tx_pb = real(tx_pb);
            sig_pwr_pb = mean(tx_pb.^2);
            app.noise_var_pb = sig_pwr_pb * 10^(-snr_db/10);
            app.tx_signal       = tx_pb;
            app.tx_signal_start = app.fifo_write + 1;
            app.tx_pending      = true;
            bw_tx = downconv_bandwidth(sch);
            app.tx_meta_pending.noise_var = 8 * app.noise_var_pb * bw_tx / app.sys.fs;
            app.tx_meta_pending.frame_start_write = app.tx_signal_start;
            app.tx_meta_pending.frame_pb_samples  = length(tx_pb);
            append_log(sprintf('[TX] %s %s body=%d pb=%d, nv=%.3e (SNR=%gdB)', ...
                sch, ch_label, length(body_bb), length(tx_pb), app.noise_var_pb, snr_db));
        end

        % --- 更新 TX 信号信息面板 ---
        update_txinfo_panel(sch, body_bb, h_tap, ch_label, snr_db, N_info, info_bits);
        set_status('信号注入中...', [0.2 0.5 0.7]);
    catch ME
        append_log(sprintf('[TX-ERR] %s', ME.message));
        if ~isempty(ME.stack)
            append_log(sprintf('  @ %s line %d', ME.stack(1).name, ME.stack(1).line));
        end
    end
end

function update_txinfo_panel(sch, body_bb, h_tap, ch_label, snr_db, N_info, info_bits)
    % 计算信号统计并显示在 TX 信息面板
    dur_s = length(body_bb) / app.sys.sym_rate;
    if strcmp(sch, 'SC-FDE')
        bw_hz = app.sys.sym_rate * (1 + app.sys.scfde.rolloff);
        sym_count = sprintf('%d blk x %d sym', ...
            app.sys.scfde.N_blocks, app.sys.scfde.blk_fft);
        code_rate = sprintf('1/%d (conv)', app.sys.codec.constraint_len);
        total_coded = length(body_bb);
    elseif strcmp(sch, 'OFDM')
        bw_hz = app.sys.sym_rate * (1 + app.sys.ofdm.rolloff);
        sym_count = sprintf('%d blk x %d FFT', ...
            app.sys.ofdm.N_blocks, app.sys.ofdm.blk_fft);
        code_rate = sprintf('1/%d (conv)', app.sys.codec.constraint_len);
        total_coded = length(body_bb);
    elseif strcmp(sch, 'SC-TDE')
        bw_hz = app.sys.sym_rate * (1 + app.sys.sctde.rolloff);
        sym_count = sprintf('train=%d + data', app.sys.sctde.train_len);
        code_rate = sprintf('1/%d (conv)', app.sys.codec.constraint_len);
        total_coded = length(body_bb);
    else
        bw_hz = app.sys.fhmfsk.total_bw;
        n_hops = floor(length(body_bb) / (app.sys.fhmfsk.samples_per_sym));
        sym_count = sprintf('%d hops', n_hops);
        code_rate = '—';
        total_coded = N_info;
    end
    lines = {
        sprintf('体制:       %s', sch);
        sprintf('信号时长:   %.3f s', dur_s);
        sprintf('带宽:       %.0f Hz', bw_hz);
        sprintf('样本数:     %d', length(body_bb));
        sprintf('符号数:     %s', sym_count);
        sprintf('码率:       %s', code_rate);
        sprintf('信息比特:   %d / 编码 %d', N_info, total_coded);
        sprintf('SNR:        %g dB', snr_db);
        sprintf('信道:       %s (%d 抽头)', ch_label, length(h_tap));
    };
    app.txinfo_area.Value = lines;
end

function on_tick()
    try
        if ~app.rx_running, return; end

        % 监听模式下 chunk = tick 周期（1:1 实时），否则 50ms（2x 加速）
        if app.audio_monitor
            eff_ms = app.tick_ms;
        else
            eff_ms = app.chunk_ms;
        end
        chunk_n = round(eff_ms / 1000 * app.sys.fs);
        if app.bypass_rf
            chunk = sqrt(app.noise_var_pb/2) * ...
                (randn(1, chunk_n) + 1j*randn(1, chunk_n));
        else
            chunk = sqrt(app.noise_var_pb) * randn(1, chunk_n);
        end

        if app.tx_pending && ~isempty(app.tx_signal)
            sig_lo = app.tx_signal_start;
            sig_hi = sig_lo + length(app.tx_signal) - 1;
            cur_lo = app.fifo_write + 1;
            cur_hi = cur_lo + chunk_n - 1;
            ov_lo  = max(sig_lo, cur_lo);
            ov_hi  = min(sig_hi, cur_hi);
            if ov_hi >= ov_lo
                idx_in_chunk  = (ov_lo:ov_hi) - cur_lo + 1;
                idx_in_signal = (ov_lo:ov_hi) - sig_lo + 1;
                chunk(idx_in_chunk) = chunk(idx_in_chunk) + app.tx_signal(idx_in_signal);
            end
            if app.fifo_write + chunk_n >= sig_hi
                app.tx_pending_done = true;
            end
        end

        push_fifo(chunk);

        % 音频监听：把当前 chunk 追加到音频缓冲
        if app.audio_monitor
            app.audio_buf = [app.audio_buf, chunk];
            flush_audio();
        end

        cur_len = app.fifo_write - app.fifo_read;
        app.lbl_fifo.Text = sprintf('%d (%.1fs)', cur_len, cur_len/app.sys.fs);

        update_scope();
        update_detection_status();
        try_decode_frame();
    catch ME
        append_log(sprintf('[TIMER-ERR] %s', ME.message));
    end
end

function update_detection_status()
    win = round(0.03 * app.sys.fs);
    cur = app.fifo_write;
    if cur < win
        app.lbl_det.Text = '空闲（缓冲中）';
        app.lbl_det.FontColor = [0.3 0.3 0.3];
        return;
    end
    seg = app.fifo(cur-win+1 : cur);
    pwr = mean(abs(seg).^2);
    ratio = pwr / max(app.noise_var_pb, 1e-12);
    if ratio > 3
        app.lbl_det.Text = sprintf('检到信号 (%.1fx)', ratio);
        app.lbl_det.FontColor = [0.1 0.6 0.1];
    else
        app.lbl_det.Text = sprintf('仅噪声 (%.2fx)', ratio);
        app.lbl_det.FontColor = [0.5 0.5 0.5];
    end
end

function push_fifo(s)
    n = length(s);
    if app.fifo_write + n > app.fifo_capacity
        keep_n = round(app.fifo_capacity * 0.5);
        offset = max(0, app.fifo_write - keep_n);
        app.fifo(1:keep_n) = app.fifo(offset+1:offset+keep_n);
        app.fifo_write = keep_n;
        app.fifo_read  = max(0, app.fifo_read - offset);
        if isfield(app.tx_meta_pending, 'frame_start_write')
            app.tx_meta_pending.frame_start_write = ...
                max(1, app.tx_meta_pending.frame_start_write - offset);
        end
    end
    app.fifo(app.fifo_write+1 : app.fifo_write+n) = s;
    app.fifo_write = app.fifo_write + n;
end

function update_scope()
    ax = app.tabs.scope;
    N_show = round(app.scope_window_s * app.sys.fs);
    cur_w = app.fifo_write;
    if cur_w == 0, return; end

    y = zeros(1, N_show);
    nvalid = min(cur_w, N_show);
    seg = app.fifo(cur_w-nvalid+1 : cur_w);
    if ~isreal(seg), seg = real(seg); end
    y(end-nvalid+1:end) = seg;

    t = ((-N_show+1):0) / app.sys.fs * 1000;

    if isempty(app.scope_line) || ~isvalid(app.scope_line)
        cla(ax,'reset');
        app.scope_line = plot(ax, t, y, 'b', 'LineWidth', 0.6);
        xlabel(ax, 'time relative to now (ms)');
        ylabel(ax, 'amplitude');
        title(ax, sprintf('实时通带示波器 (%.0fms, fc=%dHz)', ...
            app.scope_window_s*1000, app.sys.fc));
        grid(ax, 'on');
        ax.XColor = 'k'; ax.YColor = 'k';
        xlim(ax, [t(1), t(end)]);
        ylim(ax, [-0.5, 0.5]);
    else
        app.scope_line.YData = y;
    end
    yl = max(abs(y)) + 1e-9;
    cur_yl = ylim(ax);
    if 1.1*yl > cur_yl(2) || 1.1*yl < 0.4*cur_yl(2)
        ylim(ax, [-1.1*yl, 1.1*yl]);
    end
end

function try_decode_frame()
    if ~app.tx_pending, return; end
    if ~isfield(app.tx_meta_pending, 'frame_start_write'), return; end
    fs_pos = app.tx_meta_pending.frame_start_write;
    fn = app.tx_meta_pending.frame_pb_samples;
    if app.fifo_write < fs_pos + fn - 1, return; end
    if app.last_decode_at >= fs_pos, return; end

    rx_seg = app.fifo(fs_pos : fs_pos + fn - 1);
    sch = app.tx_meta_pending.scheme;
    meta = app.tx_meta_pending;

    if app.bypass_rf
        body_bb_rx = rx_seg;
    else
        bb_use = downconv_bandwidth(sch);
        [body_bb_rx, ~] = downconvert(rx_seg, app.sys.fs, app.sys.fc, bb_use);
        if length(body_bb_rx) > meta.frame_pb_samples
            body_bb_rx = body_bb_rx(1:meta.frame_pb_samples);
        end
        if ~isfield(meta, 'noise_var') || isempty(meta.noise_var) || meta.noise_var <= 0
            n_noise_samp = min(round(0.1 * app.sys.fs), fs_pos - 1);
            if n_noise_samp >= round(0.02 * app.sys.fs)
                noise_pb_seg = app.fifo(fs_pos - n_noise_samp : fs_pos - 1);
                [noise_bb_seg, ~] = downconvert(noise_pb_seg, app.sys.fs, app.sys.fc, bb_use);
                skip = max(1, round(0.05 * length(noise_bb_seg)));
                nv_meas = var(noise_bb_seg(skip:end));
                meta.noise_var = max(nv_meas, 1e-12);
                append_log(sprintf('[NV] 兜底实测 bb nv=%.3e', nv_meas));
            end
        end
    end
    app.last_body_bb_rx = body_bb_rx;

    % 解调
    try
        [bits_out, info] = modem_decode(body_bb_rx, sch, app.sys, meta);
    catch ME
        append_log(sprintf('[DEC-ERR] %s', ME.message));
        if ~isempty(ME.stack)
            for si = 1:min(3, length(ME.stack))
                append_log(sprintf('  @ %s L%d', ME.stack(si).name, ME.stack(si).line));
            end
        end
        app.last_decode_at = fs_pos;
        return;
    end
    app.last_info = info;
    app.last_bits_out = bits_out;
    app.last_decode_at = fs_pos;
    app.dec_count = app.dec_count + 1;

    % BER
    n = min(length(bits_out), length(app.last_bits_in));
    n_err = sum(bits_out(1:n) ~= app.last_bits_in(1:n));
    ber = n_err / n;

    % 保存帧数据到历史 + 获取 passband 段
    pb_seg = app.fifo(fs_pos : fs_pos + fn - 1);

    % 存储历史条目
    entry = struct();
    entry.scheme    = sch;
    entry.ber       = ber;
    entry.snr_set   = app.snr_edit.Value;
    entry.iter      = info.turbo_iter;
    entry.timestamp = datestr(now, 'HH:MM:SS');
    entry.info      = info;
    entry.bits_in   = app.last_bits_in;
    entry.bits_out  = bits_out;
    entry.h_tap     = app.tx_h_tap;
    entry.meta      = meta;
    entry.pb_seg    = pb_seg;
    entry.text_bits_len = app.last_text_bits_len;

    app.history{end+1} = entry;
    if length(app.history) > 20
        app.history = app.history(end-19:end);
    end
    refresh_history_dropdown();

    update_rx_panel(sch, info, ber, n_err, n);
    update_tabs_from_entry(entry);

    append_log(sprintf('[DEC #%d] %s BER=%.3f%% (%d/%d) iter=%d', ...
        app.dec_count, sch, ber*100, n_err, n, info.turbo_iter));

    app.tx_pending = false;
    app.tx_signal  = [];
    set_status('RX 监听中（等待下一帧）', [0.1 0.5 0.7]);
end

function refresh_history_dropdown()
    items = cell(1, length(app.history));
    for k = 1:length(app.history)
        e = app.history{k};
        items{k} = sprintf('#%d %s %s BER=%.2f%%', k, e.timestamp, e.scheme, e.ber*100);
    end
    app.hist_dd.Items = items;
    app.hist_dd.Value = items{end};
end

function on_history_select()
    sel = app.hist_dd.Value;
    idx = find(strcmp(app.hist_dd.Items, sel), 1);
    if isempty(idx) || idx < 1 || idx > length(app.history), return; end
    entry = app.history{idx};
    update_tabs_from_entry(entry);
    % 也更新 info 面板
    n = min(length(entry.bits_out), length(entry.bits_in));
    n_err = sum(entry.bits_out(1:n) ~= entry.bits_in(1:n));
    update_rx_panel(entry.scheme, entry.info, entry.ber, n_err, n);
end

function bw = downconv_bandwidth(sch)
    if strcmp(sch, 'SC-FDE')
        bw = app.sys.sym_rate * (1 + app.sys.scfde.rolloff);
    elseif strcmp(sch, 'OFDM')
        bw = app.sys.sym_rate * (1 + app.sys.ofdm.rolloff);
    elseif strcmp(sch, 'SC-TDE')
        bw = app.sys.sym_rate * (1 + app.sys.sctde.rolloff);
    else
        bw = app.sys.fhmfsk.total_bw;
    end
end

function [h_tap, label] = build_channel_tap(sch)
    preset = app.preset_dd.Value;
    if ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE'})
        sps_use = app.sys.sps;
    else
        sps_use = app.sys.fhmfsk.samples_per_sym / 8;
    end
    if startsWith(preset, 'AWGN')
        h_tap = 1; label = 'AWGN'; return;
    end
    if contains(preset, '6径 标准')
        sym_d = [0, 5, 15, 40, 60, 90];
        gains = [1, 0.6*exp(1j*0.3), 0.45*exp(1j*0.9), ...
                 0.3*exp(1j*1.5), 0.2*exp(1j*2.1), 0.12*exp(1j*2.8)];
    elseif contains(preset, '6径 深衰减')
        sym_d = [0, 5, 15, 40, 60, 90];
        gains = [0.4, 0.7*exp(1j*0.5), 0.6*exp(1j*1.2), ...
                 0.5*exp(1j*1.8), 0.4*exp(1j*2.4), 0.3*exp(1j*2.9)];
    elseif contains(preset, '3径 短时延')
        sym_d = [0, 5, 15];
        gains = [1, 0.5*exp(1j*0.8), 0.3*exp(1j*1.6)];
    else
        sym_d = 0; gains = 1;
    end
    delays_samp = round(sym_d * sps_use);
    h_tap = zeros(1, max(delays_samp)+1);
    for p = 1:length(delays_samp)
        h_tap(delays_samp(p)+1) = h_tap(delays_samp(p)+1) + gains(p);
    end
    h_tap = h_tap / norm(h_tap);
    label = sprintf('%s, %d 抽头', preset, length(h_tap));
end

function update_rx_panel(sch, info, ber, n_err, n)
    bo = app.last_bits_out;
    if isfield(app, 'last_text_bits_len')
        tbl = app.last_text_bits_len;
    else
        tbl = length(bo);
    end
    n_use_bits = floor(min(tbl, length(bo)) / 8) * 8;
    if n_use_bits >= 8
        try, txt = bits_to_text(bo(1:n_use_bits));
        catch, txt = '(bits->text 失败)'; end
    else
        txt = '(bits 不足 1 字节)';
    end
    txt = regexprep(txt, '[\x00-\x08\x0E-\x1F]', '.');
    app.text_out.Value = txt;
    if ber < 1e-6
        app.text_out.FontColor = [0.1 0.5 0.1];
    elseif ber < 0.01
        app.text_out.FontColor = [0.6 0.5 0.1];
    else
        app.text_out.FontColor = [0.7 0.2 0.2];
    end

    app.lbl_ber.Text = sprintf('%.3f%%', ber*100);
    if ber < 1e-6, app.lbl_ber.FontColor = [0.1 0.6 0.1];
    elseif ber < 0.01, app.lbl_ber.FontColor = [0.6 0.5 0.1];
    else, app.lbl_ber.FontColor = [0.8 0.2 0.2]; end
    app.lbl_err.Text = sprintf('%d / %d', n_err, n);

    app.lbl_esnr.Text = sprintf('%.2f dB', info.estimated_snr);
    app.lbl_eber.Text = sprintf('%.3e', info.estimated_ber);
    app.lbl_iter_show.Text = sprintf('%d', info.turbo_iter);
    if info.convergence_flag == 1
        app.lbl_conv.Text = '1 (收敛)'; app.lbl_conv.FontColor = [0.1 0.6 0.1];
    else
        app.lbl_conv.Text = '0 (未收敛)'; app.lbl_conv.FontColor = [0.7 0.3 0.1];
    end
    if isfield(info, 'noise_var')
        app.lbl_nv.Text = sprintf('%.3e', info.noise_var);
    else
        app.lbl_nv.Text = '—';
    end
    app.lbl_dec_cnt.Text = sprintf('%d', app.dec_count);

    bi = app.last_bits_in;
    n_show = min(48, length(bi));
    app.lbl_txb.Text = sprintf('%s', sprintf('%d', bi(1:n_show)));
    app.lbl_rxb.Text = sprintf('%s', sprintf('%d', bo(1:min(n_show,length(bo)))));
end

function update_tabs_from_entry(entry)
    % 从历史条目更新所有底部 tab（除 scope 和 log）
    sch  = entry.scheme;
    info = entry.info;
    h_tap = entry.h_tap;
    meta  = entry.meta;
    fs_val = app.sys.fs;

    % --- 频谱 ---
    ax = app.tabs.spectrum; cla(ax,'reset');
    rx_seg2 = entry.pb_seg;
    Nfft = 8192;
    P = 20*log10(abs(fftshift(fft(rx_seg2, Nfft))) + 1e-9);
    f = (-Nfft/2:Nfft/2-1) * fs_val / Nfft / 1000;
    plot(ax, f, P, 'b'); grid(ax, 'on');
    xlabel(ax, 'freq (kHz)'); ylabel(ax, 'dB');
    title(ax, '通带频谱（接收信号）');
    xline(ax,  app.sys.fc/1000, 'r--', 'fc');
    xline(ax, -app.sys.fc/1000, 'r--');
    ax.XColor = 'k'; ax.YColor = 'k';

    % --- 均衡前 ---
    ax = app.tabs.pre_eq; cla(ax,'reset');
    if ismember(sch, {'SC-FDE','OFDM','SC-TDE'}) && isfield(info,'pre_eq_syms') && ~isempty(info.pre_eq_syms)
        s = info.pre_eq_syms;
        ns = min(2000, length(s));
        scatter(ax, real(s(1:ns)), imag(s(1:ns)), 8, [0.3 0.4 0.7], 'filled', ...
            'MarkerFaceAlpha', 0.4);
        axis(ax, 'equal');
        title(ax, sprintf('均衡前星座 (%d sym)', ns));
        xlabel(ax,'I'); ylabel(ax,'Q'); grid(ax,'on');
    elseif strcmp(sch,'FH-MFSK') && isfield(info,'energy_matrix')
        E = info.energy_matrix;
        imagesc(ax, 10*log10(E.' + 1e-12)); axis(ax,'tight');
        xlabel(ax,'符号 #'); ylabel(ax,'频点 #');
        title(ax,'能量矩阵 (dB)'); colorbar(ax);
    end
    ax.XColor='k'; ax.YColor='k';

    % --- 均衡后 ---
    ax = app.tabs.post_eq; cla(ax,'reset');
    if ismember(sch, {'SC-FDE','OFDM','SC-TDE'}) && isfield(info,'post_eq_syms') && ~isempty(info.post_eq_syms)
        s = info.post_eq_syms;
        ns = min(2000, length(s));
        ref = [1+1j,1-1j,-1+1j,-1-1j]/sqrt(2);
        scatter(ax, real(s(1:ns)), imag(s(1:ns)), 12, [0.7 0.2 0.3], 'filled', ...
            'MarkerFaceAlpha', 0.5); hold(ax,'on');
        plot(ax, real(ref), imag(ref), 'kx', 'MarkerSize', 14, 'LineWidth', 2);
        axis(ax,'equal');
        title(ax, sprintf('均衡后星座 (Turbo, %d sym)', ns));
        xlabel(ax,'I'); ylabel(ax,'Q'); grid(ax,'on'); hold(ax,'off');
    elseif strcmp(sch,'FH-MFSK') && isfield(info,'soft_llr')
        L = info.soft_llr;
        histogram(ax, L, 60, 'FaceColor', [0.4 0.6 0.8]);
        xlabel(ax,'LLR'); ylabel(ax,'count');
        title(ax, sprintf('软判决 LLR (median |LLR|=%.2f)', median(abs(L))));
        grid(ax,'on');
    end
    ax.XColor='k'; ax.YColor='k';

    % --- 信道(时域) ---
    ax = app.tabs.h_td; cla(ax,'reset');
    if length(h_tap) <= 1
        text(ax, 0.5, 0.5, 'AWGN — 无信道抽头', ...
            'Units','normalized','HorizontalAlignment','center','FontSize',13);
        ax.XColor='none'; ax.YColor='none';
    else
        stem(ax, 0:length(h_tap)-1, abs(h_tap), 'filled', 'LineWidth', 1.5, ...
            'Color', [0.2 0.4 0.7]);
        xlabel(ax, '抽头索引 (样本)'); ylabel(ax, '|h_{tap}|');
        title(ax, sprintf('信道冲激响应 (%d 抽头)', length(h_tap)));
        grid(ax, 'on');
        ax.XColor = 'k'; ax.YColor = 'k';
    end

    % --- 信道(频域) ---
    ax = app.tabs.h_fd; cla(ax,'reset');
    if length(h_tap) <= 1
        text(ax, 0.5, 0.5, 'AWGN — 无频响', ...
            'Units','normalized','HorizontalAlignment','center','FontSize',13);
        ax.XColor='none'; ax.YColor='none';
    else
        if ismember(sch, {'SC-FDE','OFDM','SC-TDE'}) && isfield(info,'H_est_block1')
            H = info.H_est_block1;
            Nf = length(H);
            f_norm = (0:Nf-1)/Nf - 0.5;
            plot(ax, f_norm, abs(fftshift(H)), 'r-', 'LineWidth', 1.2);
            hold(ax, 'on');
            % 叠加理想信道频响做对比
            H_true = fft(h_tap, Nf);
            plot(ax, f_norm, abs(fftshift(H_true)), 'b--', 'LineWidth', 1.0);
            hold(ax, 'off');
            xlabel(ax, '归一化频率'); ylabel(ax, '|H(f)|');
            title(ax, '信道频响: 估计(红) vs 真实(蓝虚线)');
            legend(ax, 'H_{est}', 'H_{true}', 'Location', 'best');
            grid(ax, 'on');
        else
            % 仅真实信道频响
            Nf = max(256, length(h_tap));
            H_true = fft(h_tap, Nf);
            f_norm = (0:Nf-1)/Nf - 0.5;
            plot(ax, f_norm, abs(fftshift(H_true)), 'b-', 'LineWidth', 1.2);
            xlabel(ax, '归一化频率'); ylabel(ax, '|H(f)|');
            title(ax, sprintf('信道频响 (%d 抽头)', length(h_tap)));
            grid(ax, 'on');
        end
        ax.XColor = 'k'; ax.YColor = 'k';
    end
end

function set_status(msg, color)
    app.status_lbl.Text = msg;
    app.status_lbl.FontColor = color;
end

function v = parse_lead_int(s)
    tok = regexp(s, '^(\d+)', 'tokens', 'once');
    v = str2double(tok{1});
end

function append_log(msg)
    cur = app.log_area.Value;
    if ischar(cur)
        if isempty(cur), cur = {}; else, cur = {cur}; end
    elseif ~iscell(cur), cur = cellstr(cur); end
    cur = cur(~cellfun(@isempty, cur));
    cur{end+1} = sprintf('%s %s', datestr(now,'HH:MM:SS'), msg);
    if length(cur) > 120, cur = cur(end-100:end); end
    app.log_area.Value = cur;
    try, scroll(app.log_area, 'bottom'); catch, end
end

end
