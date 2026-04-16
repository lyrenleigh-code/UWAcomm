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
addpath(fullfile(modules_root, '08_Sync',          'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform',      'src', 'Matlab'));
addpath(fullfile(modules_root, '12_IterativeProc', 'src', 'Matlab'));

%% ---- 全局状态 ----
app = struct();
app.proj_root = proj_root;
app.sys = sys_params_default();

% FIFO（passband real 样本 ring buffer）
app.fifo_capacity = round(16 * app.sys.fs);   % 16 秒缓冲（DSSS 低速率信号需要更长）
app.fifo = zeros(1, app.fifo_capacity);
app.fifo_write = 0;
app.fifo_read  = 0;

% TX 待叠加的信号（passband real）+ 起始绝对位置
app.tx_signal       = [];
app.tx_signal_start = 0;
app.tx_meta_pending = struct();
app.tx_h_tap        = [];
app.tx_pending      = false;

% 噪声底（由 ref_sig_pwr 和当前 SNR 滑块实时计算）
app.ref_sig_pwr  = 0.1;          % 参考信号功率（首次 Transmit 后更新为实际值）
app.noise_var_pb = app.ref_sig_pwr * 10^(-15/10);  % 默认 SNR=15dB

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
app.tx_body_bb_clean = [];    % TX 干净基带（用于 TX/RX 对比 tab）

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
              'OFDM (QPSK + Turbo, 相干)', 'SC-TDE (QPSK + Turbo, 相干)', ...
              'DSSS (DBPSK + Rake, 非相干)'}, ...
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

% 文本输入 + 容量提示
app.lbl_txt = uilabel(tx_grid, 'Text', '发射文本 (max ~512B):', 'FontWeight', 'bold');
app.lbl_txt.Layout.Row = 1;
app.text_in = uitextarea(tx_grid, ...
    'Value', 'Hello UWAcomm', ...
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

% 单 axes tab
ax_tab_specs = {
    'scope',    '实时通带示波器';
    'spectrum', '通带频谱'};
for ti = 1:size(ax_tab_specs,1)
    tab = uitab(bot, 'Title', ax_tab_specs{ti,2});
    tg = uigridlayout(tab, [1 1]); tg.Padding = [8 8 8 8];
    ax = uiaxes(tg);
    ax.Toolbar.Visible = 'on';
    if ti == 1
        text(ax, 0.5, 0.5, '打开 RX 监听并点 Transmit', ...
            'Units','normalized','HorizontalAlignment','center', ...
            'FontSize', 14, 'Color', [0.5 0.5 0.5]);
    end
    ax.XColor = 'none'; ax.YColor = 'none';
    app.tabs.(ax_tab_specs{ti,1}) = ax;
end

% 均衡/解调 tab（4 列：Turbo 体制显示迭代星座，非 Turbo 体制显示 LLR/能量等）
eq_tab = uitab(bot, 'Title', '均衡分析');
eq_grid = uigridlayout(eq_tab, [1 4]); eq_grid.Padding = [6 6 6 6]; eq_grid.ColumnSpacing = 6;
app.tabs.pre_eq = uiaxes(eq_grid);  app.tabs.pre_eq.Layout.Column = 1;
app.tabs.eq_it1 = uiaxes(eq_grid);  app.tabs.eq_it1.Layout.Column = 2;
app.tabs.eq_mid = uiaxes(eq_grid);  app.tabs.eq_mid.Layout.Column = 3;
app.tabs.post_eq = uiaxes(eq_grid); app.tabs.post_eq.Layout.Column = 4;

% TX/RX 对比 tab（双行：上 TX，下 RX）
cmp_tab = uitab(bot, 'Title', 'TX/RX 对比');
cmp_grid = uigridlayout(cmp_tab, [2 1]); cmp_grid.Padding = [8 8 8 8]; cmp_grid.RowSpacing = 6;
app.tabs.compare_tx = uiaxes(cmp_grid);
app.tabs.compare_tx.Toolbar.Visible = 'on';
app.tabs.compare_tx.Layout.Row = 1;
app.tabs.compare_rx = uiaxes(cmp_grid);
app.tabs.compare_rx.Toolbar.Visible = 'on';
app.tabs.compare_rx.Layout.Row = 2;

% 信道 tab（两列：左时域 右频域，估计 vs 真实对比）
ch_tab = uitab(bot, 'Title', '信道');
ch_grid = uigridlayout(ch_tab, [1 2]); ch_grid.Padding = [8 8 8 8]; ch_grid.ColumnSpacing = 10;
app.tabs.h_td = uiaxes(ch_grid);
app.tabs.h_td.Toolbar.Visible = 'on';
app.tabs.h_td.Layout.Column = 1;
app.tabs.h_fd = uiaxes(ch_grid);
app.tabs.h_fd.Toolbar.Visible = 'on';
app.tabs.h_fd.Layout.Column = 2;

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
    is_turbo = ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE', 'OTFS'});
    is_fhmfsk = strcmp(sch, 'FH-MFSK');
    show(app.lbl_blk,  ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE'}));
    show(app.blk_dd,   ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE'}));
    show(app.lbl_iter, is_turbo); show(app.iter_edit, is_turbo);
    show(app.lbl_pl,   is_fhmfsk); show(app.pl_dd,    is_fhmfsk);
    % 更新文本容量提示
    switch sch
        case 'SC-FDE',  nb = floor((128*32-2)/8);
        case 'OFDM',    nb = floor(((256-8)*16-2)/8);
        case 'SC-TDE',  nb = floor((2000-2)/8);
        case 'DSSS',    nb = floor((1200-2)/8);
        case 'FH-MFSK', nb = floor(2192/8);
        otherwise,       nb = 200;
    end
    app.lbl_txt.Text = sprintf('发射文本 (max ~%dB):', nb);
    append_log(sprintf('[UI] scheme -> %s (max %d bytes)', sch, nb));
end

function s = current_scheme()
    sel = app.scheme_dd.Value;
    if startsWith(sel, 'SC-FDE'), s = 'SC-FDE';
    elseif startsWith(sel, 'OFDM'), s = 'OFDM';
    elseif startsWith(sel, 'SC-TDE'), s = 'SC-TDE';
    elseif startsWith(sel, 'DSSS'), s = 'DSSS';
    elseif startsWith(sel, 'OTFS'), s = 'OTFS';
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
    cla(app.tabs.compare_tx, 'reset');
    cla(app.tabs.compare_rx, 'reset');
    cla(app.tabs.spectrum, 'reset');
    cla(app.tabs.pre_eq, 'reset');
    cla(app.tabs.eq_it1, 'reset');
    cla(app.tabs.eq_mid, 'reset');
    cla(app.tabs.post_eq, 'reset');
    cla(app.tabs.h_td, 'reset');
    cla(app.tabs.h_fd, 'reset');
    app.tx_body_bb_clean = [];
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
        elseif strcmp(sch, 'DSSS')
            app.sys.dsss.fading_type = 'static';
            app.sys.dsss.fd_hz       = 0;
            N_info = 1200;  % ~150 字节(~50 汉字), Gold31@12kchip/s 信号≈6.3s
        elseif strcmp(sch, 'OTFS')
            app.sys.otfs.turbo_iter = app.iter_edit.Value;
            app.sys.otfs.fading_type = 'static';
            app.sys.otfs.fd_hz       = 0;
            % OTFS N_info 由数据格点决定
            pc_tmp = struct('mode', app.sys.otfs.pilot_mode, ...
                'guard_k', 4, 'guard_l', max(app.sys.otfs.sym_delays)+2, ...
                'pilot_value', 1);
            [~,~,~,di_tmp] = otfs_pilot_embed(zeros(1,1), ...
                app.sys.otfs.N, app.sys.otfs.M, pc_tmp);
            N_info = length(di_tmp) * 2 / 2 - mem;  % QPSK, R=1/2
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

        % --- 组装完整物理帧（加 HFM/LFM 前导码）---
        [frame_bb, frame_meta] = assemble_physical_frame(body_bb, app.sys);
        body_offset = length(frame_bb) - length(body_bb);  % 前导码占用样本数

        % --- 基带信道（对完整帧施加）---
        [h_tap, ch_label] = build_channel_tap(sch);
        frame_ch = conv(frame_bb, h_tap);
        frame_ch = frame_ch(1:length(frame_bb));

        snr_db = app.snr_edit.Value;
        app.tx_meta_pending = meta_tx;
        app.tx_meta_pending.scheme = sch;
        app.tx_meta_pending.body_offset = body_offset;
        app.tx_h_tap = h_tap;
        app.tx_body_bb_clean = frame_bb;  % 保存原始帧（无信道无噪声）用于 TX/RX 对比

        % --- FIFO 溢出保护 ---
        signal_len = length(frame_ch);
        if ~app.bypass_rf
            signal_len = round(signal_len * 1.1);
        end
        remaining = app.fifo_capacity - app.fifo_write;
        if remaining < signal_len + round(0.5 * app.sys.fs)
            app.fifo(:) = 0;
            if app.bypass_rf, app.fifo = complex(app.fifo); end
            app.fifo_write = 0;
            app.fifo_read  = 0;
            app.last_decode_at = 0;
            append_log('[FIFO] 容量不足，已重置 FIFO');
        end

        if app.bypass_rf
            sig_pwr_bb = mean(abs(frame_ch).^2);
            nv_bb = sig_pwr_bb * 10^(-snr_db/10);
            app.ref_sig_pwr = sig_pwr_bb;
            app.tx_signal = frame_ch;   % FIFO 推入的是信道后信号
            app.tx_signal_start = app.fifo_write + 1;
            app.tx_pending = true;
            app.tx_meta_pending.noise_var = nv_bb;
            app.tx_meta_pending.frame_start_write = app.tx_signal_start;
            app.tx_meta_pending.frame_pb_samples  = length(frame_ch);
            append_log(sprintf('[TX-BYPASS] %s %s frame=%d(pre=%d+body=%d), nv=%.3e (SNR=%gdB)', ...
                sch, ch_label, length(frame_ch), body_offset, length(body_bb), nv_bb, snr_db));
        else
            [tx_pb, ~] = upconvert(frame_ch, app.sys.fs, app.sys.fc);
            tx_pb = real(tx_pb);
            sig_pwr_pb = mean(tx_pb.^2);
            app.ref_sig_pwr = sig_pwr_pb;
            app.tx_signal       = tx_pb;
            app.tx_signal_start = app.fifo_write + 1;
            app.tx_pending      = true;
            bw_tx = downconv_bandwidth(sch);
            nv_pb = sig_pwr_pb * 10^(-snr_db/10);
            app.tx_meta_pending.noise_var = 8 * nv_pb * bw_tx / app.sys.fs;
            app.tx_meta_pending.frame_start_write = app.tx_signal_start;
            app.tx_meta_pending.frame_pb_samples  = length(tx_pb);
            append_log(sprintf('[TX] %s %s frame=%d(pre=%d+body=%d) pb=%d, nv=%.3e (SNR=%gdB)', ...
                sch, ch_label, length(frame_ch), body_offset, length(body_bb), ...
                length(tx_pb), nv_pb, snr_db));
        end

        % --- 更新 TX 信号信息面板 ---
        update_txinfo_panel(sch, body_bb, frame_bb, body_offset, h_tap, ch_label, snr_db, N_info);
        set_status('信号注入中...', [0.2 0.5 0.7]);
    catch ME
        append_log(sprintf('[TX-ERR] %s', ME.message));
        if ~isempty(ME.stack)
            append_log(sprintf('  @ %s line %d', ME.stack(1).name, ME.stack(1).line));
        end
    end
end

function update_txinfo_panel(sch, body_bb, frame_bb, body_offset, h_tap, ch_label, snr_db, N_info)
    if strcmp(sch, 'OTFS')
        bb_fs = app.sys.sym_rate;
    else
        bb_fs = app.sys.fs;
    end
    frame_dur = length(frame_bb) / bb_fs;
    body_dur  = length(body_bb) / bb_fs;
    pre_dur   = body_offset / bb_fs;
    data_rate = N_info / body_dur;

    if strcmp(sch, 'SC-FDE')
        bw_hz = app.sys.sym_rate * (1 + app.sys.scfde.rolloff);
        sym_count = sprintf('%d blk x %d sym', ...
            app.sys.scfde.N_blocks, app.sys.scfde.blk_fft);
    elseif strcmp(sch, 'OFDM')
        bw_hz = app.sys.sym_rate * (1 + app.sys.ofdm.rolloff);
        sym_count = sprintf('%d blk x %d FFT', ...
            app.sys.ofdm.N_blocks, app.sys.ofdm.blk_fft);
    elseif strcmp(sch, 'SC-TDE')
        bw_hz = app.sys.sym_rate * (1 + app.sys.sctde.rolloff);
        sym_count = sprintf('train=%d + data', app.sys.sctde.train_len);
    elseif strcmp(sch, 'DSSS')
        bw_hz = app.sys.dsss.total_bw;
        sym_count = sprintf('train=%d + data, Gold(%d)', ...
            app.sys.dsss.train_len, app.sys.dsss.code_len);
    elseif strcmp(sch, 'OTFS')
        bw_hz = app.sys.otfs.total_bw;
        sym_count = sprintf('N=%d x M=%d', app.sys.otfs.N, app.sys.otfs.M);
    else
        bw_hz = app.sys.fhmfsk.total_bw;
        sym_count = sprintf('%d hops', floor(length(body_bb)/app.sys.fhmfsk.samples_per_sym));
    end
    lines = {
        sprintf('体制:     %s', sch);
        sprintf('帧时长:   %.2fs (前导%.2fs + 数据%.2fs)', frame_dur, pre_dur, body_dur);
        sprintf('帧结构:   [HFM+|g|HFM-|g|LFM|g|LFM|g|body]');
        sprintf('数据速率: %.1f bps  (%.1f Bytes/s)', data_rate, data_rate/8);
        sprintf('带宽:     %.0f Hz', bw_hz);
        sprintf('符号:     %s', sym_count);
        sprintf('信息比特: %d (max %d Bytes)', N_info, floor(N_info/8));
        sprintf('SNR:      %g dB', snr_db);
        sprintf('信道:     %s (%d 抽头)', ch_label, length(h_tap));
    };
    app.txinfo_area.Value = lines;
end

function on_tick()
    try
        if ~app.rx_running, return; end

        % --- 实时 SNR → 噪声底（滑块改变立即生效）---
        app.noise_var_pb = app.ref_sig_pwr * 10^(-app.snr_edit.Value / 10);

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
    body_offset = meta.body_offset;  % 前导码样本数

    if app.bypass_rf
        % 剥离前导码，只取 body 部分给 decoder
        body_bb_rx = rx_seg(body_offset+1 : end);
    else
        bb_use = downconv_bandwidth(sch);
        [full_bb_rx, ~] = downconvert(rx_seg, app.sys.fs, app.sys.fc, bb_use);
        % 剥离前导码（下变频后样本对齐）
        body_bb_rx = full_bb_rx(body_offset+1 : end);
        if ~isfield(meta, 'noise_var') || isempty(meta.noise_var) || meta.noise_var <= 0
            n_noise_samp = min(round(0.1 * app.sys.fs), fs_pos - 1);
            if n_noise_samp >= round(0.02 * app.sys.fs)
                noise_pb_seg = app.fifo(fs_pos - n_noise_samp : fs_pos - 1);
                [noise_bb_seg, ~] = downconvert(noise_pb_seg, app.sys.fs, app.sys.fc, bb_use);
                skip = max(1, round(0.05 * length(noise_bb_seg)));
                nv_meas = var(noise_bb_seg(skip:end));
                meta.noise_var = max(nv_meas, 1e-12);
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
    entry.tx_body_bb_clean = app.tx_body_bb_clean;  % TX 干净基带（对比用）
    entry.tx_signal = app.tx_signal;                 % TX 通带信号（对比用）
    entry.bypass_rf = app.bypass_rf;                 % 记录当时的旁路模式
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
    elseif strcmp(sch, 'DSSS')
        bw = app.sys.dsss.total_bw;
    elseif strcmp(sch, 'OTFS')
        bw = app.sys.otfs.total_bw;
    else
        bw = app.sys.fhmfsk.total_bw;
    end
end

function [h_tap, label] = build_channel_tap(sch)
    preset = app.preset_dd.Value;
    if startsWith(preset, 'AWGN')
        h_tap = 1; label = 'AWGN'; return;
    end

    % DSSS 使用码片时延，OTFS 使用 DD 域格点时延，其余使用符号时延
    if strcmp(sch, 'DSSS')
        % DSSS: body_bb 采样率 = chip_rate * sps
        % 信道时延以码片为单位，映射到样本 = chip_delays * sps
        chip_d = app.sys.dsss.chip_delays;
        gains  = app.sys.dsss.gains_raw;
        gains  = gains / sqrt(sum(abs(gains).^2));
        delays_samp = chip_d * app.sys.dsss.sps;
        h_tap = zeros(1, max(delays_samp) + 1);
        for p = 1:length(delays_samp)
            h_tap(delays_samp(p)+1) = gains(p);
        end
        label = sprintf('DSSS 5径, %d 抽头', length(h_tap));
        return;
    elseif strcmp(sch, 'OTFS')
        % OTFS: body_bb 采样率 = sym_rate, 时延以 DD 格点（=1/sym_rate 样本）为单位
        sym_d = app.sys.otfs.sym_delays;
        gains = app.sys.otfs.gains_raw;
        delays_samp = sym_d;  % 1:1 映射
        h_tap = zeros(1, max(delays_samp) + 1);
        for p = 1:length(delays_samp)
            h_tap(delays_samp(p)+1) = gains(p);
        end
        h_tap = h_tap / norm(h_tap);
        label = sprintf('OTFS 5径, %d 抽头', length(h_tap));
        return;
    elseif ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE'})
        sps_use = app.sys.sps;
    else
        sps_use = app.sys.fhmfsk.samples_per_sym / 8;
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
    if info.turbo_iter <= 1
        app.lbl_iter_show.Text = '—';
    else
        app.lbl_iter_show.Text = sprintf('%d', info.turbo_iter);
    end
    if info.convergence_flag == 1
        if info.turbo_iter <= 1
            app.lbl_conv.Text = 'OK'; app.lbl_conv.FontColor = [0.1 0.6 0.1];
        else
            app.lbl_conv.Text = sprintf('收敛 (iter %d)', info.turbo_iter);
            app.lbl_conv.FontColor = [0.1 0.6 0.1];
        end
    else
        app.lbl_conv.Text = '未收敛'; app.lbl_conv.FontColor = [0.7 0.3 0.1];
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

    % --- TX/RX 对比（双行：上 TX 原始，下 RX 含信道+噪声）---
    ax_tx = app.tabs.compare_tx; cla(ax_tx,'reset');
    ax_rx = app.tabs.compare_rx; cla(ax_rx,'reset');
    try
        % TX 始终用原始帧（无信道无噪声）
        tx_clean = entry.tx_body_bb_clean;  % = frame_bb
        rx_cmp   = entry.pb_seg;            % FIFO 提取（信道+噪声）
        if isfield(entry, 'bypass_rf') && entry.bypass_rf
            tx_cmp = real(tx_clean);
            rx_cmp = real(rx_cmp);
            sr = app.sys.fs;
            if strcmp(sch, 'OTFS'), sr = app.sys.sym_rate; end
            lbl_mode = '基带 Re';
        else
            % 非 bypass：TX 原始帧上变频到通带（无信道）
            [tx_pb_clean, ~] = upconvert(tx_clean, app.sys.fs, app.sys.fc);
            tx_cmp = real(tx_pb_clean);
            rx_cmp = rx_cmp;   % 已是通带实信号
            sr = fs_val;
            lbl_mode = '通带';
        end
        if ~isempty(tx_cmp) && ~isempty(rx_cmp)
            n_show = min(length(tx_cmp), length(rx_cmp));
            t_s = (0:n_show-1) / sr;
            plot(ax_tx, t_s, tx_cmp(1:n_show), 'b-', 'LineWidth', 0.5);
            title(ax_tx, sprintf('TX %s（%.2fs, %d 样本）', lbl_mode, t_s(end), n_show));
            xlabel(ax_tx, 's'); ylabel(ax_tx, 'amplitude');
            grid(ax_tx, 'on'); ax_tx.XColor='k'; ax_tx.YColor='k';
            plot(ax_rx, t_s, rx_cmp(1:n_show), 'Color', [0.8 0.2 0.2], 'LineWidth', 0.5);
            title(ax_rx, sprintf('RX %s（含噪声+信道）', lbl_mode));
            xlabel(ax_rx, 's'); ylabel(ax_rx, 'amplitude');
            grid(ax_rx, 'on'); ax_rx.XColor='k'; ax_rx.YColor='k';
            linkaxes([ax_tx, ax_rx], 'x');
        end
    catch
    end

    % --- 频谱（仅正频率）---
    ax = app.tabs.spectrum; cla(ax,'reset');
    rx_seg2 = entry.pb_seg;
    Nfft = 8192;
    Pf = abs(fft(rx_seg2, Nfft));
    f_khz = (0:Nfft/2) / Nfft * fs_val / 1000;
    P_pos = 20*log10(Pf(1:Nfft/2+1) + 1e-9);
    plot(ax, f_khz, P_pos, 'b', 'LineWidth', 0.8); grid(ax, 'on');
    xlabel(ax, '频率 (kHz)'); ylabel(ax, 'dB');
    title(ax, '通带频谱（接收信号）');
    xline(ax, app.sys.fc/1000, 'r--', 'fc');
    bw_rx = downconv_bandwidth(sch);
    xline(ax, (app.sys.fc - bw_rx/2)/1000, 'g:', 'f_L');
    xline(ax, (app.sys.fc + bw_rx/2)/1000, 'g:', 'f_H');
    xlim(ax, [0, fs_val/2/1000]);
    ax.XColor = 'k'; ax.YColor = 'k';

    % --- 均衡分析（4 列，按体制类型分派）---
    ax_cells = {app.tabs.pre_eq, app.tabs.eq_it1, app.tabs.eq_mid, app.tabs.post_eq};
    for k = 1:4, cla(ax_cells{k}, 'reset'); end
    ref_qpsk = [1+1j,1-1j,-1+1j,-1-1j]/sqrt(2);
    ns_max = 3000;
    has_iters = isfield(info, 'eq_syms_iters') && ~isempty(info.eq_syms_iters);

    if strcmp(sch, 'FH-MFSK')
        % ---- FH-MFSK：能量矩阵 | 软 LLR 直方图 | LLR 散点 | 判决结果 ----
        if isfield(info, 'energy_matrix')
            ax = ax_cells{1};
            imagesc(ax, 10*log10(info.energy_matrix.' + 1e-12)); axis(ax,'tight');
            xlabel(ax,'符号 #'); ylabel(ax,'频点 #');
            title(ax,'能量矩阵 (dB)'); colorbar(ax);
            ax.XColor='k'; ax.YColor='k';
        end
        if isfield(info, 'soft_llr')
            L = info.soft_llr;
            ax = ax_cells{2};
            histogram(ax, L, 60, 'FaceColor', [0.4 0.6 0.8]);
            xlabel(ax,'LLR'); ylabel(ax,'count');
            title(ax, sprintf('软判决 LLR (med=%.1f)', median(abs(L))));
            grid(ax,'on'); ax.XColor='k'; ax.YColor='k';

            ax = ax_cells{3};
            plot(ax, 1:length(L), L, '.', 'MarkerSize', 3, 'Color', [0.3 0.5 0.7]);
            xlabel(ax,'bit #'); ylabel(ax,'LLR');
            title(ax,'LLR 序列'); grid(ax,'on');
            ax.XColor='k'; ax.YColor='k';
        end
        ax = ax_cells{4};
        text(ax, 0.5, 0.5, sprintf('FH-MFSK\n无星座图\nBER=%.3f%%', entry.ber*100), ...
            'Units','normalized','HorizontalAlignment','center','FontSize',12);
        ax.XColor='none'; ax.YColor='none';

    elseif strcmp(sch, 'DSSS')
        % ---- DSSS：Rake 输出(BPSK) | 差分相关 | LLR | 判决 ----
        if isfield(info, 'pre_eq_syms') && ~isempty(info.pre_eq_syms)
            ax = ax_cells{1};
            s = info.pre_eq_syms; ns = min(ns_max, length(s));
            plot(ax, real(s(1:ns)), imag(s(1:ns)), '.', 'MarkerSize', 4, 'Color', [0.3 0.4 0.7]);
            hold(ax,'on'); plot(ax, [-1 1], [0 0], 'rx', 'MarkerSize', 12, 'LineWidth', 2); hold(ax,'off');
            axis(ax, 'equal'); title(ax, 'Rake 输出(DBPSK)');
            xlabel(ax,'I'); ylabel(ax,'Q'); grid(ax,'on');
            ax.XColor='k'; ax.YColor='k';
        end
        if isfield(info, 'post_eq_syms') && ~isempty(info.post_eq_syms)
            ax = ax_cells{2};
            s = info.post_eq_syms; ns = min(ns_max, length(s));
            plot(ax, real(s(1:ns)), imag(s(1:ns)), '.', 'MarkerSize', 4, 'Color', [0.5 0.3 0.6]);
            hold(ax,'on'); plot(ax, [-1 1], [0 0], 'rx', 'MarkerSize', 12, 'LineWidth', 2); hold(ax,'off');
            axis(ax, 'equal'); title(ax, '差分检测后');
            xlabel(ax,'I'); ylabel(ax,'Q'); grid(ax,'on');
            ax.XColor='k'; ax.YColor='k';
        end
        ax = ax_cells{3};
        text(ax, 0.5, 0.5, sprintf('DSSS Gold31\n无Turbo迭代\n单次 Rake+DCD'), ...
            'Units','normalized','HorizontalAlignment','center','FontSize',11);
        ax.XColor='none'; ax.YColor='none';
        ax = ax_cells{4};
        text(ax, 0.5, 0.5, sprintf('BER=%.3f%%\nSNR=%.1fdB', entry.ber*100, info.estimated_snr), ...
            'Units','normalized','HorizontalAlignment','center','FontSize',13, ...
            'FontWeight','bold', 'Color', [0.1 0.5 0.1]);
        ax.XColor='none'; ax.YColor='none';

    else
        % ---- Turbo 体制（SC-FDE/OFDM/SC-TDE/OTFS）：迭代星座 ----
        if has_iters
            n_it = length(info.eq_syms_iters);
            if n_it >= 4
                sel = [1, round(n_it/3), round(2*n_it/3), n_it];
            elseif n_it == 3
                sel = [1, 2, 2, 3];
            elseif n_it == 2
                sel = [1, 1, 2, 2];
            else
                sel = [1, 1, 1, 1];
            end
        end

        % 列 1：均衡前
        ax = ax_cells{1};
        if isfield(info,'pre_eq_syms') && ~isempty(info.pre_eq_syms)
            s = info.pre_eq_syms; ns = min(ns_max, length(s));
            scatter(ax, real(s(1:ns)), imag(s(1:ns)), 5, [0.3 0.4 0.7], 'filled', 'MarkerFaceAlpha', 0.3);
            hold(ax,'on'); plot(ax, real(ref_qpsk), imag(ref_qpsk), 'kx', 'MarkerSize', 10, 'LineWidth', 2); hold(ax,'off');
            axis(ax, 'equal'); title(ax, '均衡前'); xlabel(ax,'I'); ylabel(ax,'Q'); grid(ax,'on');
        end
        ax.XColor='k'; ax.YColor='k';

        % 列 2/3/4：迭代过程
        for ci = 2:4
            ax = ax_cells{ci};
            if has_iters && sel(ci) <= length(info.eq_syms_iters)
                it_idx = sel(ci);
                s = info.eq_syms_iters{it_idx}; ns = min(ns_max, length(s));
                scatter(ax, real(s(1:ns)), imag(s(1:ns)), 5, [0.3 0.4 0.7], 'filled', 'MarkerFaceAlpha', 0.4);
                hold(ax,'on'); plot(ax, real(ref_qpsk), imag(ref_qpsk), 'kx', 'MarkerSize', 10, 'LineWidth', 2); hold(ax,'off');
                axis(ax, 'equal');
                if ci == 4
                    title(ax, sprintf('iter %d (末)', it_idx));
                else
                    title(ax, sprintf('iter %d', it_idx));
                end
                xlabel(ax,'I'); grid(ax,'on');
            elseif isfield(info,'post_eq_syms') && ~isempty(info.post_eq_syms)
                s = info.post_eq_syms; ns = min(ns_max, length(s));
                scatter(ax, real(s(1:ns)), imag(s(1:ns)), 5, [0.3 0.4 0.7], 'filled', 'MarkerFaceAlpha', 0.4);
                hold(ax,'on'); plot(ax, real(ref_qpsk), imag(ref_qpsk), 'kx', 'MarkerSize', 10, 'LineWidth', 2); hold(ax,'off');
                axis(ax, 'equal'); title(ax, '均衡后'); xlabel(ax,'I'); grid(ax,'on');
            end
            ax.XColor='k'; ax.YColor='k';
        end
    end

    % --- 信道（左：时域 CIR，右：频响，均含估计 vs 真实对比）---
    ax_td = app.tabs.h_td; cla(ax_td,'reset');
    ax_fd = app.tabs.h_fd; cla(ax_fd,'reset');
    if length(h_tap) <= 1
        text(ax_td, 0.5, 0.5, 'AWGN', 'Units','normalized', ...
            'HorizontalAlignment','center','FontSize',13);
        text(ax_fd, 0.5, 0.5, 'AWGN', 'Units','normalized', ...
            'HorizontalAlignment','center','FontSize',13);
        ax_td.XColor='none'; ax_td.YColor='none';
        ax_fd.XColor='none'; ax_fd.YColor='none';
    else
        % ===== 确定采样率（h_tap 在哪个速率）=====
        if strcmp(sch, 'DSSS')
            h_fs = app.sys.fs;  % DSSS h_tap at sample rate (chip_rate * sps)
        elseif strcmp(sch, 'OTFS')
            h_fs = app.sys.sym_rate;
        else
            h_fs = app.sys.fs;  % SC-FDE/OFDM/SC-TDE h_tap at sample rate
        end

        % ===== 左列：时域 CIR（x 轴 = 时间 ms）=====
        t_true_ms = (0:length(h_tap)-1) / h_fs * 1000;
        stem(ax_td, t_true_ms, abs(h_tap), 'filled', 'LineWidth', 1.5, ...
            'Color', [0.2 0.5 0.8], 'MarkerSize', 5);
        hold(ax_td, 'on');
        has_est_td = false;
        if strcmp(sch, 'DSSS') && isfield(info, 'h_est') && isfield(info, 'chip_delays')
            t_est_ms = info.chip_delays * app.sys.dsss.sps / h_fs * 1000;
            stem(ax_td, t_est_ms, abs(info.h_est), 'LineWidth', 1.2, ...
                'Color', [0.8 0.2 0.2], 'MarkerSize', 6);
            has_est_td = true;
        elseif ismember(sch, {'SC-FDE','OFDM','SC-TDE'}) && isfield(info, 'H_est_block1')
            h_est_td = ifft(info.H_est_block1);
            t_est_ms = (0:length(h_est_td)-1) / app.sys.sym_rate * 1000;
            stem(ax_td, t_est_ms, abs(h_est_td), 'LineWidth', 1.2, ...
                'Color', [0.8 0.2 0.2], 'MarkerSize', 4);
            has_est_td = true;
        end
        hold(ax_td, 'off');
        xlabel(ax_td, '时延 (ms)'); ylabel(ax_td, '|h|');
        title(ax_td, '时域 CIR');
        if has_est_td
            legend(ax_td, '真实', '估计', 'Location', 'best');
        end
        grid(ax_td, 'on'); ax_td.XColor='k'; ax_td.YColor='k';

        % ===== 右列：频域响应（以接收端带宽为窗口）=====
        bw_rx = downconv_bandwidth(sch);  % 接收端信号带宽 (Hz)
        Nf = 512;
        % 真实信道在信号带宽范围画
        H_true = fft(h_tap, Nf);
        f_hz = (0:Nf-1)/Nf * h_fs - h_fs/2;
        plot(ax_fd, f_hz/1000, 20*log10(abs(fftshift(H_true))+1e-9), 'b-', 'LineWidth', 1.2);
        hold(ax_fd, 'on');
        has_est_fd = false;
        if ismember(sch, {'SC-FDE','OFDM','SC-TDE'}) && isfield(info, 'H_est_block1')
            H_est = info.H_est_block1;
            Nf_est = length(H_est);
            f_est_hz = (0:Nf_est-1)/Nf_est * app.sys.sym_rate - app.sys.sym_rate/2;
            plot(ax_fd, f_est_hz/1000, 20*log10(abs(fftshift(H_est))+1e-9), 'r--', 'LineWidth', 1.0);
            has_est_fd = true;
        elseif strcmp(sch, 'DSSS') && isfield(info, 'h_est') && isfield(info, 'chip_delays')
            h_est_full = zeros(1, Nf);
            est_samp = info.chip_delays * app.sys.dsss.sps;
            for p = 1:length(est_samp)
                if est_samp(p)+1 <= Nf
                    h_est_full(est_samp(p)+1) = info.h_est(p);
                end
            end
            H_est_d = fft(h_est_full, Nf);
            plot(ax_fd, f_hz/1000, 20*log10(abs(fftshift(H_est_d))+1e-9), 'r--', 'LineWidth', 1.0);
            has_est_fd = true;
        end
        hold(ax_fd, 'off');
        xlim(ax_fd, [-bw_rx/2/1000 * 1.1, bw_rx/2/1000 * 1.1]);
        xlabel(ax_fd, '频率 (kHz)'); ylabel(ax_fd, '|H(f)| (dB)');
        title(ax_fd, sprintf('频域响应 (BW=%.1fkHz)', bw_rx/1000));
        if has_est_fd
            legend(ax_fd, '真实', '估计', 'Location', 'best');
        end
        grid(ax_fd, 'on'); ax_fd.XColor='k'; ax_fd.YColor='k';
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
