function p3_demo_ui()
% 功能：通信声纳 流式 Demo —— RX 持续监听 + TX 触发发送 + 实时通带示波器
% 版本：V3.1.0（2026-04-17 深色科技风重样式 + 命名改"通信声纳"）
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
addpath(fullfile(modules_root, '10_DopplerProc',   'src', 'Matlab'));
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

% 动效计数器（Step 4）
app.flash_det_count    = 0;   % 检测闪烁剩余 tick
app.flash_decode_count = 0;   % 解码成功闪烁剩余 tick
app.last_det_status    = '';  % 上次 det_status，变化时触发闪烁
app.anim_t_start       = tic; % 动效时间基准

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

%% ---- 样式（单一事实源：p3_style.m）----
S           = p3_style();
PALETTE     = S.PALETTE;
FONTS       = S.FONTS;
SIZES       = S.SIZES;
app.style   = S;
app.palette = PALETTE;

%% ---- 主 figure ----
app.fig = uifigure('Name', '通信声纳 · Streaming P3 Demo', ...
    'Position', [40 40 1500 950], 'Color', PALETTE.bg, ...
    'CloseRequestFcn', @(~,~) on_close());

main = uigridlayout(app.fig, [3 1]);
main.RowHeight   = {SIZES.top_h, '1x', SIZES.tab_h};
main.ColumnWidth = {'1x'};
main.Padding     = [12 12 12 12];
main.RowSpacing  = 10;


%% ==== UI 构建（嵌套函数）====
build_topbar(main);
build_middle_panels(main);
build_bottom_tabs(main);
start_timer_and_init();

%% ============================================================
%% 内部函数
%% ============================================================

function build_topbar(main)
    %% ==== 顶栏（驾驶舱风格：badge | title | scheme | rx | status | tx+mon）====
    top = uigridlayout(main, [1 6]);
    top.Layout.Row = 1;
    top.ColumnWidth = {62, '1x', 300, 180, 200, 250};
    top.ColumnSpacing = 14;
    top.BackgroundColor = PALETTE.surface;
    top.Padding = [14 8 14 8];

    % 声纳 badge（装饰）
    badge_wrap = uigridlayout(top, [1 1]);
    badge_wrap.Layout.Column = 1;
    badge_wrap.Padding = [0 4 0 4];
    badge_wrap.BackgroundColor = PALETTE.surface;
    app.sonar_badge = p3_sonar_badge(badge_wrap);

    % 标题组（主标题 + 英文副标题）
    title_group = uigridlayout(top, [2 1]);
    title_group.Layout.Column = 2;
    title_group.RowHeight = {'1x', 14};
    title_group.RowSpacing = 0;
    title_group.Padding = [0 6 0 6];
    title_group.BackgroundColor = PALETTE.surface;

    title_lbl = uilabel(title_group, 'Text', '通信声纳  ·  流式 Demo', ...
        'FontSize', SIZES.h1, 'FontWeight', 'bold', 'FontColor', PALETTE.primary, ...
        'FontName', FONTS.title);
    title_lbl.Layout.Row = 1;

    subtitle_lbl = uilabel(title_group, ...
        'Text', sprintf('UNDERWATER ACOUSTIC COMM  ·  fs=%dHz  fc=%dHz', ...
                        app.sys.fs, app.sys.fc), ...
        'FontSize', 10, 'FontColor', PALETTE.text_dim, ...
        'FontName', FONTS.code);
    subtitle_lbl.Layout.Row = 2;

    % scheme 下拉 + RF bypass
    sch_panel = uigridlayout(top, [2 2]);
    sch_panel.Layout.Column = 3;
    sch_panel.ColumnWidth = {48, '1x'};
    sch_panel.RowHeight = {'1x', 20};
    sch_panel.RowSpacing = 2;
    sch_panel.Padding = [0 4 0 4];
    sch_panel.BackgroundColor = PALETTE.surface;
    lbl_sch = uilabel(sch_panel, 'Text', '调制', ...
        'FontSize', SIZES.body, 'FontWeight', 'bold', ...
        'FontColor', PALETTE.text_muted, ...
        'HorizontalAlignment', 'right');
    lbl_sch.Layout.Row = 1; lbl_sch.Layout.Column = 1;
    app.scheme_dd = uidropdown(sch_panel, ...
        'Items', {'FH-MFSK (8-FSK 跳频, 非相干)', 'SC-FDE (QPSK + Turbo, 相干)', ...
                  'OFDM (QPSK + Turbo, 相干)', 'SC-TDE (QPSK + Turbo, 相干)', ...
                  'DSSS (DBPSK + Rake, 非相干)', 'OTFS (DD域 + LMMSE/MP)'}, ...
        'Value', 'SC-FDE (QPSK + Turbo, 相干)', ...
        'FontSize', SIZES.body_sm, ...
        'ValueChangedFcn', @(~,~) on_scheme_changed());
    % OTFS 采样率桥接 2026-04-19 完成（modem_encode/decode_otfs V2.0.0），
    % body_bb @ fs 与其他 5 体制接口统一，可在 P3 passband UI 直接使用
    app.scheme_dd.Layout.Row = 1; app.scheme_dd.Layout.Column = 2;
    app.bypass_chk = uicheckbox(sch_panel, ...
        'Text', 'Bypass RF (复基带直通, 调试用)', ...
        'Value', false, 'FontSize', 9, ...
        'FontColor', PALETTE.text_dim, ...
        'ValueChangedFcn', @(~,~) on_bypass_changed());
    app.bypass_chk.Layout.Row = 2; app.bypass_chk.Layout.Column = [1 2];

    % RX 开关
    rx_sw_panel = uigridlayout(top, [1 2]);
    rx_sw_panel.Layout.Column = 4;
    rx_sw_panel.ColumnWidth = {'fit', '1x'};
    rx_sw_panel.Padding = [0 4 0 4];
    rx_sw_panel.BackgroundColor = PALETTE.surface;
    lbl_rx = uilabel(rx_sw_panel, 'Text', 'RX 监听', ...
        'FontSize', SIZES.body, 'FontWeight', 'bold', ...
        'FontColor', PALETTE.text_muted, ...
        'HorizontalAlignment', 'right');
    lbl_rx.Layout.Column = 1;
    app.rx_switch = uiswitch(rx_sw_panel, 'slider', 'Items', {'OFF', 'ON'}, ...
        'Value', 'OFF', 'FontSize', SIZES.body_sm, ...
        'ValueChangedFcn', @(~,~) on_rx_switch());
    app.rx_switch.Layout.Column = 2;

    % status（驾驶舱灯）
    app.status_lbl = uilabel(top, 'Text', '  ●  Ready', ...
        'FontSize', SIZES.h3, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'center', ...
        'BackgroundColor', PALETTE.success_bg, 'FontColor', PALETTE.success, ...
        'FontName', FONTS.code);
    app.status_lbl.Layout.Column = 5;

    % Transmit + Mon（合成右栏）
    action_grid = uigridlayout(top, [1 2]);
    action_grid.Layout.Column = 6;
    action_grid.ColumnWidth = {'1x', 64};
    action_grid.ColumnSpacing = 6;
    action_grid.Padding = [0 6 0 6];
    action_grid.BackgroundColor = PALETTE.surface;

    app.tx_btn = uibutton(action_grid, 'push', 'Text', 'Transmit  ▶', ...
        'FontSize', SIZES.h2, 'FontWeight', 'bold', ...
        'BackgroundColor', PALETTE.accent, 'FontColor', 'white', ...
        'FontName', FONTS.title, ...
        'ButtonPushedFcn', @(~,~) on_transmit());
    app.tx_btn.Layout.Column = 1;

    app.monitor_btn = uibutton(action_grid, 'state', 'Text', 'Mon', ...
        'FontSize', SIZES.body_sm, 'FontWeight', 'bold', ...
        'BackgroundColor', PALETTE.divider, 'FontColor', PALETTE.text, ...
        'ValueChangedFcn', @(src,~) on_monitor_toggle(src));
    app.monitor_btn.Layout.Column = 2;
    app.audio_monitor = false;
    app.audio_buf = [];
    app.audio_play_until = 0;
end

function build_middle_panels(main)
    %% ==== 中部：TX | RX ====
    mid = uigridlayout(main, [1 2]);
    mid.Layout.Row = 2;
    mid.ColumnWidth = {'1x', '1x'};
    mid.ColumnSpacing = 10;

    %% ---- TX panel ----
    tx_panel = uipanel(mid, 'Title', '  ▲  TX 发射端   ·   TRANSMITTER', ...
        'FontSize', SIZES.h2, 'FontWeight', 'bold', ...
        'BackgroundColor', PALETTE.panel_tx_bg, ...
        'ForegroundColor', PALETTE.primary, 'BorderType', 'line');
    if isprop(tx_panel, 'BorderColor'),  tx_panel.BorderColor = PALETTE.border_subtle; end
    if isprop(tx_panel, 'BorderWidth'),  tx_panel.BorderWidth = 1; end
    tx_panel.Layout.Column = 1;
    app.tx_panel = tx_panel;
    tx_grid = uigridlayout(tx_panel, [14 2]);
    tx_grid.RowHeight = {25, 55, 25, 28, 28, 28, 28, 28, 28, 28, 28, 28, 25, '1x'};
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

    % OTFS 导频模式（row 12，仅 OTFS 可见）
    app.lbl_pilot = uilabel(tx_grid, 'Text', 'OTFS 导频:');
    app.lbl_pilot.Layout.Row = 12; app.lbl_pilot.Layout.Column = 1;
    app.pilot_dd = uidropdown(tx_grid, ...
        'Items', {'impulse (冲激，高 SNR 最优，PAPR 20dB)', ...
                  'sequence (ZC，PAPR ↓9dB，5dB 轻微误码)', ...
                  'superimposed (叠加，能效最优)'}, ...
        'Value', 'impulse (冲激，高 SNR 最优，PAPR 20dB)', ...
        'ValueChangedFcn', @(~,~) on_pilot_mode_changed());
    app.pilot_dd.Layout.Row = 12; app.pilot_dd.Layout.Column = 2;

    % TX 信号信息面板（替换原 Log 区域）
    txinfo_panel = uipanel(tx_grid, 'Title', '  TX 信号信息', 'FontSize', SIZES.body, ...
        'FontWeight', 'bold', 'BackgroundColor', PALETTE.surface, ...
        'ForegroundColor', PALETTE.text_muted, 'BorderType', 'line');
    if isprop(txinfo_panel, 'BorderColor'), txinfo_panel.BorderColor = PALETTE.border_subtle; end
    if isprop(txinfo_panel, 'BorderWidth'), txinfo_panel.BorderWidth = 1; end
    txinfo_panel.Layout.Row = [13 14]; txinfo_panel.Layout.Column = [1 2];
    txinfo_grid = uigridlayout(txinfo_panel, [1 1]); txinfo_grid.Padding = [5 5 5 5];
    txinfo_grid.BackgroundColor = PALETTE.surface;
    app.txinfo_area = uitextarea(txinfo_grid, 'Editable', 'off', ...
        'FontName', FONTS.code, 'FontSize', 10, ...
        'Value', '(Transmit 后显示信号统计)');

    %% ---- RX panel ----
    rx_rpanel = uipanel(mid, 'Title', '  ▼  RX 接收端   ·   RECEIVER', ...
        'FontSize', SIZES.h2, 'FontWeight', 'bold', ...
        'BackgroundColor', PALETTE.panel_rx_bg, ...
        'ForegroundColor', PALETTE.accent_hi, 'BorderType', 'line');
    if isprop(rx_rpanel, 'BorderColor'),  rx_rpanel.BorderColor = PALETTE.border_subtle; end
    if isprop(rx_rpanel, 'BorderWidth'),  rx_rpanel.BorderWidth = 1; end
    rx_rpanel.Layout.Column = 2;
    app.rx_panel = rx_rpanel;

    rx_grid = uigridlayout(rx_rpanel, [5 1]);
    rx_grid.RowHeight = {25, 95, 134, 28, '1x'};
    rx_grid.RowSpacing = 6;

    % 解码文本 header（带 Clear 按钮）
    hdr_grid = uigridlayout(rx_grid, [1 2]);
    hdr_grid.ColumnWidth = {'1x', 100};
    hdr_grid.Padding = [0 0 0 0];
    uilabel(hdr_grid, 'Text', '解码文本（自动）:', 'FontWeight', 'bold');
    app.clear_btn = uibutton(hdr_grid, 'push', 'Text', 'Clear', ...
        'BackgroundColor', PALETTE.divider, ...
        'FontColor', PALETTE.text_muted, ...
        'ButtonPushedFcn', @(~,~) on_clear());
    app.text_out = uitextarea(rx_grid, 'Editable', 'off', ...
        'Value', '(打开 RX 监听 → 点 Transmit → 检测+解码)', ...
        'FontSize', 12);

    % BER 关键指标（4 张 metric card，单行 bento）
    ber_panel = uipanel(rx_grid, 'Title', '  监听状态', 'FontSize', SIZES.body, ...
        'FontWeight', 'bold', 'BackgroundColor', PALETTE.surface, ...
        'ForegroundColor', PALETTE.text_muted, 'BorderType', 'line');
    if isprop(ber_panel, 'BorderColor'), ber_panel.BorderColor = PALETTE.border_subtle; end
    if isprop(ber_panel, 'BorderWidth'), ber_panel.BorderWidth = 1; end
    ber_grid = uigridlayout(ber_panel, [1 4]);
    ber_grid.ColumnWidth = {'1x', '1x', '1x', '1x'};
    ber_grid.ColumnSpacing = 8;
    ber_grid.Padding = [10 6 10 6];
    ber_grid.BackgroundColor = PALETTE.surface;

    card_ber  = p3_metric_card(ber_grid, '比特 BER',   '—',     '',      'primary');
    card_err  = p3_metric_card(ber_grid, '错误 / 总',  '—',     'bits',  'muted');
    card_fifo = p3_metric_card(ber_grid, 'FIFO',       '0',     '样本',   'accent');
    card_det  = p3_metric_card(ber_grid, '检测状态',    '空闲',  '',      'muted');
    % 长文本字段：降小字号避免溢出
    card_err.value.FontSize  = 14;
    card_fifo.value.FontSize = 14;
    card_det.value.FontSize  = 13;
    % 保留旧句柄名（回调零改动）
    app.lbl_ber  = card_ber.value;
    app.lbl_err  = card_err.value;
    app.lbl_fifo = card_fifo.value;
    app.lbl_det  = card_det.value;
    % 保存卡片句柄（动效/语义色调用）
    app.card_ber  = card_ber;
    app.card_err  = card_err;
    app.card_fifo = card_fifo;
    app.card_det  = card_det;

    % 解码历史下拉
    hist_grid = uigridlayout(rx_grid, [1 2]);
    hist_grid.ColumnWidth = {100, '1x'};
    hist_grid.Padding = [0 0 0 0];
    uilabel(hist_grid, 'Text', '解码历史:', 'FontWeight', 'bold');
    app.hist_dd = uidropdown(hist_grid, ...
        'Items', {'(无)'}, 'Value', '(无)', ...
        'ValueChangedFcn', @(~,~) on_history_select());

    % info 紧凑网格（label/value 成对，4 行 × 4 列 = 8 对字段）
    info_panel = uipanel(rx_grid, 'Title', '  解码 info', 'FontSize', SIZES.body, ...
        'FontWeight', 'bold', 'BackgroundColor', PALETTE.surface, ...
        'ForegroundColor', PALETTE.text_muted, 'BorderType', 'line');
    if isprop(info_panel, 'BorderColor'), info_panel.BorderColor = PALETTE.border_subtle; end
    if isprop(info_panel, 'BorderWidth'), info_panel.BorderWidth = 1; end
    info_grid = uigridlayout(info_panel, [4 4]);
    info_grid.RowHeight = {'1x', '1x', '1x', '1x'};
    info_grid.ColumnWidth = {130, '1x', 130, '1x'};
    info_grid.ColumnSpacing = 6;
    info_grid.RowSpacing = 2;
    info_grid.Padding = [12 6 12 6];
    info_grid.BackgroundColor = PALETTE.surface;

    % 统一 label / value 构造器
    make_lbl = @(txt) uilabel(info_grid, 'Text', txt, ...
        'FontName', FONTS.code, 'FontSize', 11, ...
        'FontColor', PALETTE.text_muted);
    make_val = @(txt, color) uilabel(info_grid, 'Text', txt, ...
        'FontName', FONTS.code, 'FontSize', 13, 'FontWeight', 'bold', ...
        'FontColor', color);

    make_lbl('estimated_snr:');
    app.lbl_esnr      = make_val('—', PALETTE.primary);
    make_lbl('estimated_ber:');
    app.lbl_eber      = make_val('—', PALETTE.primary);
    make_lbl('turbo_iter:');
    app.lbl_iter_show = make_val('—', PALETTE.accent_hi);
    make_lbl('convergence:');
    app.lbl_conv      = make_val('—', PALETTE.text_muted);
    make_lbl('noise_var:');
    app.lbl_nv        = make_val('—', PALETTE.text_muted);
    make_lbl('解码次数:');
    app.lbl_dec_cnt   = make_val('0', PALETTE.success);
    make_lbl('TX bits:');
    app.lbl_txb       = make_val('—', PALETTE.text_dim);
    app.lbl_txb.FontSize = 10;
    make_lbl('RX bits:');
    app.lbl_rxb       = make_val('—', PALETTE.text_dim);
    app.lbl_rxb.FontSize = 10;

    % 兼容动效 / 语义色代码：建哑 card 句柄
    app.card_conv = struct('value', app.lbl_conv, 'panel', info_panel);
end

function build_bottom_tabs(main)
    %% ==== 底部 7 tab ====
    bot = uitabgroup(main); bot.Layout.Row = 3;
    app.tabs = struct();

    % 单 axes tab（Unicode 前缀增强识别）
    ax_tab_specs = {
        'scope',    '◉ 实时通带示波器';
        'spectrum', '≋ 通带频谱'};
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
    eq_tab = uitab(bot, 'Title', '◈ 均衡分析');
    eq_grid = uigridlayout(eq_tab, [1 4]); eq_grid.Padding = [6 6 6 6]; eq_grid.ColumnSpacing = 6;
    app.tabs.pre_eq = uiaxes(eq_grid);  app.tabs.pre_eq.Layout.Column = 1;
    app.tabs.eq_it1 = uiaxes(eq_grid);  app.tabs.eq_it1.Layout.Column = 2;
    app.tabs.eq_mid = uiaxes(eq_grid);  app.tabs.eq_mid.Layout.Column = 3;
    app.tabs.post_eq = uiaxes(eq_grid); app.tabs.post_eq.Layout.Column = 4;

    % TX/RX 对比 tab（双行：上 TX，下 RX）
    cmp_tab = uitab(bot, 'Title', '⇄ TX/RX 对比');
    cmp_grid = uigridlayout(cmp_tab, [2 1]); cmp_grid.Padding = [8 8 8 8]; cmp_grid.RowSpacing = 6;
    app.tabs.compare_tx = uiaxes(cmp_grid);
    app.tabs.compare_tx.Toolbar.Visible = 'on';
    app.tabs.compare_tx.Layout.Row = 1;
    app.tabs.compare_rx = uiaxes(cmp_grid);
    app.tabs.compare_rx.Toolbar.Visible = 'on';
    app.tabs.compare_rx.Layout.Row = 2;

    % 信道 tab（两列：左时域 右频域，估计 vs 真实对比）
    ch_tab = uitab(bot, 'Title', '◣ 信道');
    ch_grid = uigridlayout(ch_tab, [1 2]); ch_grid.Padding = [8 8 8 8]; ch_grid.ColumnSpacing = 10;
    app.tabs.h_td = uiaxes(ch_grid);
    app.tabs.h_td.Toolbar.Visible = 'on';
    app.tabs.h_td.Layout.Column = 1;
    app.tabs.h_fd = uiaxes(ch_grid);
    app.tabs.h_fd.Toolbar.Visible = 'on';
    app.tabs.h_fd.Layout.Column = 2;

    % 同步/多普勒 tab（2×2：HFM+ corr / HFM- corr / 符号定时 / 多普勒占位）
    sync_tab = uitab(bot, 'Title', '◎ 同步/多普勒');
    sync_grid = uigridlayout(sync_tab, [2 2]);
    sync_grid.Padding = [6 6 6 6]; sync_grid.ColumnSpacing = 6; sync_grid.RowSpacing = 6;
    app.tabs.sync_hfm_pos = uiaxes(sync_grid);
    app.tabs.sync_hfm_pos.Layout.Row = 1; app.tabs.sync_hfm_pos.Layout.Column = 1;
    app.tabs.sync_sym_off = uiaxes(sync_grid);
    app.tabs.sync_sym_off.Layout.Row = 1; app.tabs.sync_sym_off.Layout.Column = 2;
    app.tabs.sync_hfm_neg = uiaxes(sync_grid);
    app.tabs.sync_hfm_neg.Layout.Row = 2; app.tabs.sync_hfm_neg.Layout.Column = 1;
    app.tabs.sync_doppler = uiaxes(sync_grid);
    app.tabs.sync_doppler.Layout.Row = 2; app.tabs.sync_doppler.Layout.Column = 2;

    % 质量历史 tab（2 行：上 BER 散点，下 SNR+iter 双 Y 轴）
    quality_tab = uitab(bot, 'Title', '📊 质量历史');
    quality_grid = uigridlayout(quality_tab, [2 1]);
    quality_grid.Padding = [8 8 8 8]; quality_grid.RowSpacing = 6;
    app.tabs.quality_ber = uiaxes(quality_grid);
    app.tabs.quality_ber.Toolbar.Visible = 'on';
    app.tabs.quality_ber.Layout.Row = 1;
    app.tabs.quality_snr = uiaxes(quality_grid);
    app.tabs.quality_snr.Toolbar.Visible = 'on';
    app.tabs.quality_snr.Layout.Row = 2;

    % 日志 tab（uitextarea, 无 axes）
    log_tab = uitab(bot, 'Title', '≡ 日志');
    log_tg = uigridlayout(log_tab, [1 1]); log_tg.Padding = [8 8 8 8];
    app.log_area = uitextarea(log_tg, 'Editable', 'off', ...
        'FontName', FONTS.code, 'FontSize', 10, ...
        'BackgroundColor', PALETTE.surface_alt, 'FontColor', PALETTE.text);

    %% ---- 统一深色样式应用到所有 axes ----
    axes_all = {app.tabs.scope, app.tabs.spectrum, ...
                app.tabs.pre_eq, app.tabs.eq_it1, app.tabs.eq_mid, app.tabs.post_eq, ...
                app.tabs.compare_tx, app.tabs.compare_rx, ...
                app.tabs.h_td, app.tabs.h_fd, ...
                app.tabs.sync_hfm_pos, app.tabs.sync_hfm_neg, ...
                app.tabs.sync_sym_off, app.tabs.sync_doppler, ...
                app.tabs.quality_ber, app.tabs.quality_snr};
    for k = 1:length(axes_all)
        style_dark_axes(axes_all{k});
    end
    % scope 初始占位文字颜色调亮（之前用 [0.5 0.5 0.5] 深灰在深色背景不可见）
    app.tabs.scope.Children(1).Color = PALETTE.text_muted;

    %% ---- 扫默认色控件统一上深色主题 ----
    apply_dark_defaults(app.fig, PALETTE);
end

function start_timer_and_init()
    %% ---- 启动定时器 ----
    app.timer = timer('ExecutionMode','fixedSpacing', 'Period', app.tick_ms/1000, ...
        'TimerFcn', @(~,~) on_tick(), 'BusyMode', 'drop');
    start(app.timer);

    %% ---- 初始化 ----
    append_log('[UI] p3_demo_ui 启动');
    append_log(sprintf('[UI] fs=%dHz fc=%dHz tick=%dms chunk=%dms (%.1fx 加速)', ...
        app.sys.fs, app.sys.fc, app.tick_ms, app.chunk_ms, app.tick_ms/app.chunk_ms));
    on_scheme_changed();
end

function [lbl, edt] = mk_row(g, row, label, type, val, lim)
    lbl = uilabel(g, 'Text', label, 'FontColor', PALETTE.text);
    lbl.Layout.Row = row; lbl.Layout.Column = 1;
    edt = uieditfield(g, type, 'Value', val, 'Limits', lim, ...
        'ValueDisplayFormat', '%g', ...
        'BackgroundColor', PALETTE.surface_alt, 'FontColor', PALETTE.text);
    edt.Layout.Row = row; edt.Layout.Column = 2;
end

function style_dark_axes(ax)
% 深色科技风 axes 样式（与 PALETTE 对齐）
    ax.BackgroundColor = PALETTE.surface;
    ax.Color = PALETTE.surface;
    ax.XColor = PALETTE.text_muted;
    ax.YColor = PALETTE.text_muted;
    ax.GridColor = PALETTE.divider;
    ax.GridAlpha = 0.4;
    ax.MinorGridColor = PALETTE.divider;
    if ~isempty(ax.Title),  ax.Title.Color  = PALETTE.text; end
    if ~isempty(ax.XLabel), ax.XLabel.Color = PALETTE.text_muted; end
    if ~isempty(ax.YLabel), ax.YLabel.Color = PALETTE.text_muted; end
end

function apply_dark_defaults(root, P)
% 扫描所有控件，把仍在默认（白/浅灰/黑）的色值改为深色主题对应色
    DEFAULT_WHITE = [1 1 1];
    DEFAULT_BLACK = [0 0 0];
    DEFAULT_GRID_GRAY = [0.94 0.94 0.94];

    % uilabel 黑字 → 主文字色
    hs = findall(root, 'Type', 'uilabel');
    for h = hs'
        if isequal(h.FontColor, DEFAULT_BLACK)
            h.FontColor = P.text;
        end
    end

    % uieditfield 白底黑字 → surface_alt + text
    hs = findall(root, 'Type', 'uieditfield');
    for h = hs'
        if isequal(h.BackgroundColor, DEFAULT_WHITE)
            h.BackgroundColor = P.surface_alt;
        end
        if isequal(h.FontColor, DEFAULT_BLACK)
            h.FontColor = P.text;
        end
    end

    % uitextarea 同理
    hs = findall(root, 'Type', 'uitextarea');
    for h = hs'
        if isequal(h.BackgroundColor, DEFAULT_WHITE)
            h.BackgroundColor = P.surface_alt;
        end
        if isequal(h.FontColor, DEFAULT_BLACK)
            h.FontColor = P.text;
        end
    end

    % uidropdown 同理
    hs = findall(root, 'Type', 'uidropdown');
    for h = hs'
        if isequal(h.BackgroundColor, DEFAULT_WHITE)
            h.BackgroundColor = P.surface_alt;
        end
        if isequal(h.FontColor, DEFAULT_BLACK)
            h.FontColor = P.text;
        end
    end

    % uicheckbox 黑字 → text
    hs = findall(root, 'Type', 'uicheckbox');
    for h = hs'
        if isequal(h.FontColor, DEFAULT_BLACK)
            h.FontColor = P.text;
        end
    end

    % uigridlayout 默认浅灰 → bg 色
    hs = findall(root, 'Type', 'uigridlayout');
    for h = hs'
        if isequal(h.BackgroundColor, DEFAULT_GRID_GRAY)
            h.BackgroundColor = P.bg;
        end
    end

    % uitab 默认灰底 → surface + 文字色
    hs = findall(root, 'Type', 'uitab');
    for h = hs'
        h.BackgroundColor = P.surface;
        if isprop(h, 'ForegroundColor')
            h.ForegroundColor = P.text;
        end
    end

    % uipanel 若仍是默认灰 → surface
    hs = findall(root, 'Type', 'uipanel');
    for h = hs'
        if isequal(h.BackgroundColor, DEFAULT_GRID_GRAY)
            h.BackgroundColor = P.surface;
        end
        if isprop(h, 'ForegroundColor') && isequal(h.ForegroundColor, DEFAULT_BLACK)
            h.ForegroundColor = P.text_muted;
        end
    end
end

function on_scheme_changed()
    sch = current_scheme();
    is_turbo = ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE', 'OTFS'});
    is_fhmfsk = strcmp(sch, 'FH-MFSK');
    show(app.lbl_blk,  ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE'}));
    show(app.blk_dd,   ismember(sch, {'SC-FDE', 'OFDM', 'SC-TDE'}));
    show(app.lbl_iter, is_turbo); show(app.iter_edit, is_turbo);
    show(app.lbl_pl,   is_fhmfsk); show(app.pl_dd,    is_fhmfsk);
    is_otfs = strcmp(sch, 'OTFS');
    show(app.lbl_pilot, is_otfs); show(app.pilot_dd, is_otfs);
    % 更新文本容量提示（单一事实源：p3_text_capacity）
    nb = p3_text_capacity(sch, app.sys);
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

function on_pilot_mode_changed()
    sel = app.pilot_dd.Value;
    if     startsWith(sel, 'impulse'),      app.sys.otfs.pilot_mode = 'impulse';
    elseif startsWith(sel, 'sequence'),     app.sys.otfs.pilot_mode = 'sequence';
    elseif startsWith(sel, 'superimposed'), app.sys.otfs.pilot_mode = 'superimposed';
    end
    append_log(sprintf('[OTFS] pilot_mode → %s', app.sys.otfs.pilot_mode));
    on_scheme_changed();
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
        set_status('RX 监听中', 'busy');
    else
        app.rx_running = false;
        append_log('[RX] 监听 OFF');
        set_status('Ready', 'ready');
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
    app.text_out.FontColor = app.palette.text_muted;
    app.lbl_ber.Text = '—'; app.lbl_ber.FontColor = app.palette.primary;
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
    cla(app.tabs.scope);
    cla(app.tabs.compare_tx);
    cla(app.tabs.compare_rx);
    cla(app.tabs.spectrum);
    cla(app.tabs.pre_eq);
    cla(app.tabs.eq_it1);
    cla(app.tabs.eq_mid);
    cla(app.tabs.post_eq);
    cla(app.tabs.h_td);
    cla(app.tabs.h_fd);
    app.tx_body_bb_clean = [];
    append_log('[CLEAR] RX + FIFO + 历史 已清空');
end

function on_monitor_toggle(src)
    app.audio_monitor = logical(src.Value);
    P = app.palette;
    if app.audio_monitor
        app.audio_buf = [];
        app.audio_play_until = 0;
        src.Text = 'Mon ON';
        src.BackgroundColor = P.success;
        src.FontColor = 'white';
        append_log('[MON] 音频监听 ON');
    else
        app.audio_buf = [];
        src.Text = 'Mon';
        src.BackgroundColor = P.divider;
        src.FontColor = P.text;
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
            set_status('请先打开 RX 监听', 'warning');
            return;
        end

        % --- 应用参数 ---
        ui_vals = struct( ...
            'blk_fft',    parse_lead_int(app.blk_dd.Value), ...
            'turbo_iter', app.iter_edit.Value, ...
            'payload',    parse_lead_int(app.pl_dd.Value) );
        [N_info, app.sys] = p3_apply_scheme_params(sch, app.sys, ui_vals);

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
        [h_tap, ch_label] = p3_channel_tap(sch, app.sys, app.preset_dd.Value);
        frame_ch = conv(frame_bb, h_tap);
        frame_ch = frame_ch(1:length(frame_bb));

        % --- 多普勒注入（真实水声模型 y(t) = x((1+α)·t)·exp(j·2π·fc·α·t)）---
        % RX 若无 α 反补偿 + 时变信道估计 → 高 Doppler BER 崩溃（已知限制）
        % 完整处理见 spec 2026-04-19-p3-decoder-timevarying-branch.md (Level 2)
        dop_hz = app.doppler_edit.Value;
        if abs(dop_hz) > 1e-3
            alpha = dop_hz / app.sys.fc;
            frame_ch_r = comp_resample_spline(frame_ch, alpha);
            if length(frame_ch_r) > length(frame_ch)
                frame_ch = frame_ch_r(1:length(frame_ch));
            else
                frame_ch = [frame_ch_r, zeros(1, length(frame_ch)-length(frame_ch_r))]; %#ok<AGROW>
            end
            t_vec = (0:length(frame_ch)-1) / app.sys.fs;
            frame_ch = frame_ch .* exp(1j * 2*pi * dop_hz * t_vec);
            ch_label = sprintf('%s + Doppler %+gHz (α=%.2e)', ch_label, dop_hz, alpha);
        end

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
            bw_tx = p3_downconv_bw(sch, app.sys);
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
        set_status('信号注入中...', 'busy');
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
    % 动效更新（无论 RX 是否 ON 都要跑，保证边框/进度条可见）
    try
        t_sec = toc(app.anim_t_start);
        app = p3_animate_tick(app, t_sec);
    catch
    end
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
    P = app.palette;
    if cur < win
        app.lbl_det.Text = '空闲（缓冲中）';
        app.lbl_det.FontColor = P.text_muted;
        return;
    end
    seg = app.fifo(cur-win+1 : cur);
    pwr = mean(abs(seg).^2);
    ratio = pwr / max(app.noise_var_pb, 1e-12);
    if ratio > 3
        new_txt = sprintf('检到信号 (%.1fx)', ratio);
        % 状态切换瞬间触发闪烁
        if ~startsWith(app.lbl_det.Text, '检到')
            app.flash_det_count = 4;   % 闪 2 个周期（on/off × 2）
        end
        app.lbl_det.Text = new_txt;
        app.lbl_det.FontColor = P.success;
    else
        app.lbl_det.Text = sprintf('仅噪声 (%.2fx)', ratio);
        app.lbl_det.FontColor = P.text_muted;
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
        cla(ax);
        app.scope_line = plot(ax, t, y, 'b', 'LineWidth', 0.6);
        xlabel(ax, 'time relative to now (ms)');
        ylabel(ax, 'amplitude');
        title(ax, sprintf('实时通带示波器 (%.0fms, fc=%dHz)', ...
            app.scope_window_s*1000, app.sys.fc));
        grid(ax, 'on');
        ax.XColor = PALETTE.text_muted; ax.YColor = PALETTE.text_muted;
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
    if ~isfield(app.tx_meta_pending, 'frame_pb_samples'), return; end
    fn = app.tx_meta_pending.frame_pb_samples;

    % 真同步：HFM+ 匹配滤波检测帧起点（替代 frame_start_write 捷径）
    sync_det = detect_frame_stream(app.fifo, app.fifo_write, ...
                                    app.last_decode_at, app.sys, ...
                                    struct('frame_len_hint', fn));
    if ~sync_det.found, return; end
    fs_pos = sync_det.fs_pos;

    if app.fifo_write < fs_pos + fn - 1, return; end
    if app.last_decode_at >= fs_pos, return; end

    % Ground truth 对比（frame_start_write 仅做 debug 偏差 log，不驱动解码）
    fs_pos_gt = 0;
    if isfield(app.tx_meta_pending, 'frame_start_write')
        fs_pos_gt = app.tx_meta_pending.frame_start_write;
    end
    sync_diff = fs_pos - fs_pos_gt;
    append_log(sprintf('[SYNC] fs=%d gt=%d diff=%+d peak=%.1f ratio=%.1f conf=%.2f', ...
        fs_pos, fs_pos_gt, sync_diff, sync_det.peak_val, ...
        sync_det.peak_ratio, sync_det.confidence));

    rx_seg = app.fifo(fs_pos : fs_pos + fn - 1);
    sch = app.tx_meta_pending.scheme;
    meta = app.tx_meta_pending;
    body_offset = meta.body_offset;  % 前导码样本数

    if app.bypass_rf
        % 剥离前导码，只取 body 部分给 decoder
        body_bb_rx = rx_seg(body_offset+1 : end);
    else
        bb_use = p3_downconv_bw(sch, app.sys);
        [full_bb_rx, ~] = downconvert(rx_seg, app.sys.fs, app.sys.fc, bb_use);

        % 剥离前导码（下变频后样本对齐）
        body_bb_rx = full_bb_rx(body_offset+1 : min(body_offset+meta.N_shaped, length(full_bb_rx)));
        % 去oracle：噪声方差由 decoder 内部盲估计，不再外部注入
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
    app.flash_decode_count = 4;   % 触发 text_out 闪烁（2 个周期）

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
    entry.sync_det  = sync_det;                      % 真同步检测结果（sync tab 用）
    entry.sync_diff = sync_diff;                     % 检测位置 - ground truth

    app.history{end+1} = entry;
    if length(app.history) > 20
        app.history = app.history(end-19:end);
    end
    refresh_history_dropdown();

    update_rx_panel(sch, info, ber, n_err, n);
    p3_render_tabs(sch, entry, app.tabs, app.sys, app.history, app.style);

    append_log(sprintf('[DEC #%d] %s BER=%.3f%% (%d/%d) iter=%d', ...
        app.dec_count, sch, ber*100, n_err, n, info.turbo_iter));

    app.tx_pending = false;
    app.tx_signal  = [];
    set_status('RX 监听中（等待下一帧）', 'busy');
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
    p3_render_tabs(entry.scheme, entry, app.tabs, app.sys, app.history, app.style);
    % 也更新 info 面板
    n = min(length(entry.bits_out), length(entry.bits_in));
    n_err = sum(entry.bits_out(1:n) ~= entry.bits_in(1:n));
    update_rx_panel(entry.scheme, entry.info, entry.ber, n_err, n);
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
    P = app.palette;
    if ber < 1e-6
        app.text_out.FontColor = P.success;
    elseif ber < 0.01
        app.text_out.FontColor = P.warning;
    else
        app.text_out.FontColor = P.danger;
    end

    app.lbl_ber.Text = sprintf('%.3f%%', ber*100);
    if ber < 1e-6, app.lbl_ber.FontColor = P.success;
    elseif ber < 0.01, app.lbl_ber.FontColor = P.warning;
    else, app.lbl_ber.FontColor = P.danger; end
    app.lbl_err.Text = sprintf('%d / %d', n_err, n);

    app.lbl_esnr.Text = sprintf('%.2f', info.estimated_snr);
    app.lbl_eber.Text = sprintf('%.3e', info.estimated_ber);
    if info.turbo_iter <= 1
        app.lbl_iter_show.Text = '—';
    else
        app.lbl_iter_show.Text = sprintf('%d', info.turbo_iter);
    end
    if info.convergence_flag == 1
        c_ok = p3_semantic_color('收敛');
        if info.turbo_iter <= 1
            app.lbl_conv.Text = 'OK';
        else
            app.lbl_conv.Text = sprintf('收敛 (iter %d)', info.turbo_iter);
        end
        app.lbl_conv.FontColor = c_ok.fg;
    else
        c_bad = p3_semantic_color('未收敛');
        app.lbl_conv.Text = '未收敛';
        app.lbl_conv.FontColor = c_bad.fg;
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

function set_status(msg, state)
% state 取值：'ready' | 'busy' | 'warning' | 'error'
    P = app.palette;
    switch state
        case 'ready'
            bg = P.success_bg; fg = P.success;     dot = '●';
        case 'busy'
            bg = P.info_bg;    fg = P.primary;     dot = '◐';
        case 'warning'
            bg = P.warning_bg; fg = P.warning;     dot = '▲';
        case 'error'
            bg = [1.0 0.92 0.92]; fg = P.danger;   dot = '✕';
        otherwise
            bg = P.surface; fg = P.text;           dot = '·';
    end
    app.status_lbl.Text = sprintf('  %s  %s', dot, msg);
    app.status_lbl.FontColor = fg;
    app.status_lbl.BackgroundColor = bg;
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
