function p2_demo_ui()
% 功能：Streaming P2 多帧流式检测交互式 demo UI
% 版本：V1.0.0
% 用法：在 MATLAB 命令行执行 p2_demo_ui()
%
% 与 P1 demo 的区别：
%   - 文本输入支持任意长度（自动按帧切分）
%   - 容量提示显示"预计 N 帧 / 总时长 X 秒"
%   - RX 显示帧明细 uitable（每帧 idx / 文本 / CRC / sync_peak）
%   - 7 viz tab 含新增"帧检测"面板（匹配滤波 + 阈值 + 检测峰）

%% ---- 路径注册 ----
this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));
streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(streaming_root, 'channel'));
addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '09_Waveform', 'src', 'Matlab'));

%% ---- 初始化 app state ----
app = struct();
app.proj_root = proj_root;
app.sys = sys_params_default();
% P2 默认 payload_bits 改小，便于演示多帧切分
app.sys.frame.payload_bits = 256;
app.sys.frame.body_bits = app.sys.frame.header_bits + ...
    app.sys.frame.payload_bits + app.sys.frame.payload_crc_bits;
app.session = '';
app.last_info = [];
app.last_ch_params = [];

%% ---- 主 figure ----
app.fig = uifigure('Name', 'Streaming P2 — 多帧流式检测 Demo', ...
    'Position', [60 60 1500 950], 'Color', [0.95 0.95 0.96]);

main = uigridlayout(app.fig, [3 1]);
main.RowHeight = {90, '1x', 280};
main.ColumnWidth = {'1x'};
main.Padding = [10 10 10 10];
main.RowSpacing = 8;

% ==== 顶栏 ====
top = uigridlayout(main, [1 3]);
top.Layout.Row = 1;
top.ColumnWidth = {'1x', 380, 200};
title_lbl = uilabel(top, 'Text', 'Streaming P2 — 多帧流式检测 Demo', ...
    'FontSize', 18, 'FontWeight', 'bold', 'FontColor', [0.1 0.3 0.6]);
title_lbl.Layout.Column = 1;
app.status_lbl = uilabel(top, 'Text', 'Ready', ...
    'FontSize', 13, 'HorizontalAlignment', 'center', ...
    'BackgroundColor', [0.90 0.95 0.90], 'FontColor', [0.1 0.5 0.1]);
app.status_lbl.Layout.Column = 2;
app.tx_btn = uibutton(top, 'push', 'Text', '▶  Transmit', ...
    'FontSize', 15, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.2 0.6 0.3], 'FontColor', 'white', ...
    'ButtonPushedFcn', @(~,~) on_transmit());
app.tx_btn.Layout.Column = 3;

% ==== 中部：TX | RX ====
mid = uigridlayout(main, [1 2]);
mid.Layout.Row = 2;
mid.ColumnWidth = {'1x', '1x'};
mid.ColumnSpacing = 10;

%% ---- TX Panel ----
tx_panel = uipanel(mid, 'Title', 'TX 发射端（多帧）', 'FontSize', 13, ...
    'FontWeight', 'bold', 'BackgroundColor', [0.98 0.98 1.0]);
tx_panel.Layout.Column = 1;
tx_grid = uigridlayout(tx_panel, [11 2]);
tx_grid.RowHeight = {25, 160, 25, 30, 30, 30, 30, 30, 30, 25, '1x'};
tx_grid.ColumnWidth = {130, '1x'};
tx_grid.RowSpacing = 5;

lbl_txt = uilabel(tx_grid, 'Text', '发射文本（任意长度）:', 'FontWeight', 'bold');
lbl_txt.Layout.Row = 1;
app.text_in = uitextarea(tx_grid, ...
    'Value', sprintf(['这是一段较长的水声通信测试文本，用于演示流式多帧检测。\n' ...
                      '系统会自动按 UTF-8 字节边界切分为多个帧，每帧通过\n' ...
                      'HFM+ 前导码独立同步，RX 端用滑动匹配滤波自动发现。']), ...
    'FontSize', 12, 'ValueChangedFcn', @(~,~) update_capacity_hint());
app.text_in.Layout.Row = [1 2]; app.text_in.Layout.Column = 2;

lbl_ch = uilabel(tx_grid, 'Text', '信道参数:', 'FontWeight', 'bold');
lbl_ch.Layout.Row = 3;

% SNR
lbl_snr = uilabel(tx_grid, 'Text', 'SNR (dB):');
lbl_snr.Layout.Row = 4; lbl_snr.Layout.Column = 1;
app.snr_edit = uieditfield(tx_grid, 'numeric', 'Value', 15, ...
    'Limits', [-20 40], 'ValueDisplayFormat', '%g');
app.snr_edit.Layout.Row = 4; app.snr_edit.Layout.Column = 2;

% Doppler
lbl_dop = uilabel(tx_grid, 'Text', '多普勒 (Hz):');
lbl_dop.Layout.Row = 5; lbl_dop.Layout.Column = 1;
app.doppler_edit = uieditfield(tx_grid, 'numeric', 'Value', 0, ...
    'Limits', [-50 50], 'ValueDisplayFormat', '%g');
app.doppler_edit.Layout.Row = 5; app.doppler_edit.Layout.Column = 2;

% 衰落类型
lbl_fad = uilabel(tx_grid, 'Text', '衰落类型:');
lbl_fad.Layout.Row = 6; lbl_fad.Layout.Column = 1;
app.fading_dd = uidropdown(tx_grid, ...
    'Items', {'static (恒定)', 'slow (Jakes 慢衰落)', 'fast (Jakes 快衰落)'}, ...
    'Value', 'static (恒定)');
app.fading_dd.Layout.Row = 6; app.fading_dd.Layout.Column = 2;

% Jakes fd
lbl_jkfd = uilabel(tx_grid, 'Text', 'Jakes fd (Hz):');
lbl_jkfd.Layout.Row = 7; lbl_jkfd.Layout.Column = 1;
app.jakes_fd_edit = uieditfield(tx_grid, 'numeric', 'Value', 2, ...
    'Limits', [0 20], 'ValueDisplayFormat', '%g');
app.jakes_fd_edit.Layout.Row = 7; app.jakes_fd_edit.Layout.Column = 2;

% Preset
lbl_pre = uilabel(tx_grid, 'Text', '信道预设:');
lbl_pre.Layout.Row = 8; lbl_pre.Layout.Column = 1;
app.preset_dd = uidropdown(tx_grid, ...
    'Items', {'5径 标准水声', '5径 深衰减', '3径 短时延', '单径 理想'}, ...
    'Value', '5径 标准水声');
app.preset_dd.Layout.Row = 8; app.preset_dd.Layout.Column = 2;

% 单帧大小（决定切几帧）
lbl_pl = uilabel(tx_grid, 'Text', '单帧 payload:');
lbl_pl.Layout.Row = 9; lbl_pl.Layout.Column = 1;
app.payload_dd = uidropdown(tx_grid, ...
    'Items', {'128 bits (16 字节，~5 汉字)', ...
              '256 bits (32 字节，~10 汉字)', ...
              '512 bits (64 字节，~21 汉字)', ...
              '1024 bits (128 字节，~42 汉字)', ...
              '2048 bits (256 字节，~85 汉字)'}, ...
    'Value', '256 bits (32 字节，~10 汉字)', ...
    'ValueChangedFcn', @(~,~) update_capacity_hint());
app.payload_dd.Layout.Row = 9; app.payload_dd.Layout.Column = 2;

% 容量/帧数提示
app.lbl_hint = uilabel(tx_grid, 'Text', '', ...
    'FontColor', [0.3 0.3 0.3], 'FontSize', 10);
app.lbl_hint.Layout.Row = 10; app.lbl_hint.Layout.Column = [1 2];

% Log
log_panel = uipanel(tx_grid, 'Title', 'Log', 'FontSize', 11);
log_panel.Layout.Row = 11; log_panel.Layout.Column = [1 2];
log_grid = uigridlayout(log_panel, [1 1]);
log_grid.Padding = [5 5 5 5];
app.log_area = uitextarea(log_grid, 'Editable', 'off', ...
    'FontName', 'Consolas', 'FontSize', 10);

%% ---- RX Panel ----
rx_panel = uipanel(mid, 'Title', 'RX 接收端（多帧解码）', 'FontSize', 13, ...
    'FontWeight', 'bold', 'BackgroundColor', [1.0 0.98 0.95]);
rx_panel.Layout.Column = 2;
rx_grid = uigridlayout(rx_panel, [4 1]);
rx_grid.RowHeight = {25, 160, 80, '1x'};
rx_grid.RowSpacing = 5;

lbl_out = uilabel(rx_grid, 'Text', '解码文本（自动拼接）:', 'FontWeight', 'bold');
lbl_out.Layout.Row = 1;
app.text_out = uitextarea(rx_grid, 'Editable', 'off', 'Value', '(等待发射...)', ...
    'FontSize', 12);
app.text_out.Layout.Row = 2;

% 总体统计区
stat_panel = uipanel(rx_grid, 'Title', '统计', 'FontSize', 11);
stat_panel.Layout.Row = 3;
stat_grid = uigridlayout(stat_panel, [2 4]);
stat_grid.RowHeight = {22, 22};
stat_grid.ColumnWidth = {120, '1x', 120, '1x'};
stat_grid.Padding = [8 6 8 6];
stat_grid.RowSpacing = 2;

uilabel(stat_grid, 'Text', '检测帧数:', 'FontName', 'Consolas');
app.lbl_det = uilabel(stat_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');
uilabel(stat_grid, 'Text', '预期帧数:', 'FontName', 'Consolas');
app.lbl_exp = uilabel(stat_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');
uilabel(stat_grid, 'Text', '文本一致:', 'FontName', 'Consolas');
app.lbl_match = uilabel(stat_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');
uilabel(stat_grid, 'Text', '阈值/噪底:', 'FontName', 'Consolas');
app.lbl_thresh = uilabel(stat_grid, 'Text', '—', 'FontName','Consolas','FontWeight','bold');

% 帧明细 table
table_panel = uipanel(rx_grid, 'Title', '帧明细', 'FontSize', 11);
table_panel.Layout.Row = 4;
tg = uigridlayout(table_panel, [1 1]);
tg.Padding = [5 5 5 5];
app.tbl = uitable(tg, ...
    'ColumnName', {'#', 'idx', '内容预览', 'CRC', 'sync', 'k(样本)'}, ...
    'ColumnWidth', {30, 40, '1x', 60, 60, 80}, ...
    'ColumnEditable', false, ...
    'Data', {});

%% ==== 底部：Tab 可视化 ====
bot = uitabgroup(main);
bot.Layout.Row = 3;

app.tabs = struct();
tab_specs = {
    'tx_wave',   'TX 多帧波形';
    'rx_wave',   'RX 多帧+检测';
    'detection', '帧检测匹配滤波';
    'spectrum',  '频谱对比';
    'data_zoom', '数据段放大';
    'energy',    '第1帧解码';
    'cir',       '信道 CIR'};
for ti = 1:size(tab_specs, 1)
    tabname = tab_specs{ti, 1};
    tab = uitab(bot, 'Title', tab_specs{ti, 2});
    tg2 = uigridlayout(tab, [1 1]);
    tg2.Padding = [8 8 8 8];
    ax_i = uiaxes(tg2);
    text(ax_i, 0.5, 0.5, '请按 "▶ Transmit" 生成数据', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'FontSize', 14, 'Color', [0.5 0.5 0.5]);
    ax_i.XColor = 'none'; ax_i.YColor = 'none';
    app.tabs.(tabname) = ax_i;
end

%% ---- 初始化 log ----
append_log('[UI] p2_demo_ui 启动完毕');
append_log(sprintf('[UI] fs=%d, fc=%d, FH-MFSK %d-FSK, 默认 payload=%d bits', ...
    app.sys.fs, app.sys.fc, app.sys.fhmfsk.M, app.sys.frame.payload_bits));
update_capacity_hint();

%% ============================================================
%% 内部函数
%% ============================================================

function on_transmit()
    app.tx_btn.Enable = 'off';
    cleanup_obj = onCleanup(@() set_status('Ready', [0.1 0.5 0.1], 'on'));
    try
        % 1. 读输入
        text_lines = app.text_in.Value;
        if iscell(text_lines), text_in_str = strjoin(text_lines, newline);
        else, text_in_str = text_lines; end
        text_in_str = strtrim(text_in_str);
        if isempty(text_in_str)
            set_status('Error: 文本为空', [0.7 0.2 0.2], 'on');
            return;
        end

        append_log(sprintf('── 新任务 [%s] ──', datestr(now, 'HH:MM:SS')));
        append_log(sprintf('[IN] (%d 字符 / %d UTF-8 字节)', ...
            length(text_in_str), length(unicode2native(text_in_str,'UTF-8'))));

        % 1b. 应用 payload 选择
        sel = app.payload_dd.Value;
        pl_match = regexp(sel, '^(\d+)', 'tokens', 'once');
        if ~isempty(pl_match)
            pl = str2double(pl_match{1});
            app.sys.frame.payload_bits = pl;
            app.sys.frame.body_bits = app.sys.frame.header_bits + pl + ...
                app.sys.frame.payload_crc_bits;
        end
        append_log(sprintf('[CFG] payload_bits=%d', app.sys.frame.payload_bits));

        % 2. session
        set_status('Creating session...', [0.2 0.4 0.7], 'off'); drawnow;
        session_root = fullfile(app.proj_root, 'modules', '14_Streaming', 'sessions');
        app.session = create_session_dir(session_root);
        append_log(sprintf('[SESSION] %s', app.session));

        % 3. TX (多帧)
        set_status('TX 多帧发射中...', [0.2 0.4 0.7], 'off'); drawnow;
        tx_stream_p2(text_in_str, app.session, app.sys);
        append_log('[TX] raw_frames/0001.wav 完成');

        % 4. Channel
        set_status('Channel 仿真中...', [0.4 0.3 0.7], 'off'); drawnow;
        app.last_ch_params = build_channel_params();
        channel_simulator_p1(app.session, app.last_ch_params, app.sys);
        fd_eq = app.last_ch_params.doppler_rate * app.sys.fc;
        append_log(sprintf('[CHAN] SNR=%.1fdB, Doppler=%.2fHz, fading=%s/fd=%gHz', ...
            app.last_ch_params.snr_db, fd_eq, ...
            app.last_ch_params.fading_type, app.last_ch_params.fading_fd_hz));

        % 5. RX (多帧)
        set_status('RX 流式解码中...', [0.7 0.4 0.1], 'off'); drawnow;
        [text_out_str, info] = rx_stream_p2(app.session, app.sys);
        app.last_info = info;
        append_log(sprintf('[RX] det/exp = %d/%d', info.N_detected, info.N_expected));

        % 6. 更新 RX 面板
        update_rx_panel(text_in_str, text_out_str, info);

        % 7. 可视化
        set_status('生成可视化...', [0.2 0.4 0.7], 'off'); drawnow;
        ax_s = struct();
        fn = fieldnames(app.tabs);
        for ii = 1:numel(fn), ax_s.(fn{ii}) = app.tabs.(fn{ii}); end
        visualize_p2_frames(app.session, app.sys, info, ...
            'Axes', ax_s, 'ChParams', app.last_ch_params);

        % 8. 状态
        if strcmp(text_in_str, text_out_str) && info.N_detected == info.N_expected
            set_status(sprintf('✓ 完美：%d 帧全检测全解码', info.N_expected), ...
                [0.1 0.5 0.1], 'on');
        elseif strcmp(text_in_str, text_out_str)
            set_status('✓ 文本复原（帧数有差异）', [0.7 0.5 0.1], 'on');
        else
            set_status('⚠ 文本不一致，见明细', [0.7 0.5 0.1], 'on');
        end
        append_log('[DONE]');

    catch ME
        append_log(sprintf('[ERROR] %s', ME.message));
        if ~isempty(ME.stack)
            append_log(sprintf('  @ %s line %d', ME.stack(1).name, ME.stack(1).line));
        end
        set_status(sprintf('Error: %s', ME.message), [0.7 0.2 0.2], 'on');
    end
end

function cp = build_channel_params()
    preset = app.preset_dd.Value;
    cp = struct();
    cp.fs = app.sys.fs;
    cp.snr_db = app.snr_edit.Value;
    fad_sel = app.fading_dd.Value;
    if startsWith(fad_sel, 'slow'),     cp.fading_type = 'slow';
    elseif startsWith(fad_sel, 'fast'), cp.fading_type = 'fast';
    else,                                cp.fading_type = 'static';
    end
    cp.fading_fd_hz = app.jakes_fd_edit.Value;
    fd_hz = app.doppler_edit.Value;
    cp.doppler_rate = fd_hz / app.sys.fc;
    cp.seed = 42;

    if contains(preset, '5径 标准')
        cp.delays_s = [0, 0.167, 0.5, 0.833, 1.333] * 1e-3;
        cp.gains    = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), ...
                       0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
    elseif contains(preset, '5径 深衰减')
        % 适度深衰减：直达径弱但仍占主导，多径展宽 ≤ 30% 符号时长（防 ISI）
        cp.delays_s = [0, 0.15, 0.3, 0.45, 0.6] * 1e-3;
        cp.gains    = [0.5, 0.7*exp(1j*1.0), 0.5*exp(1j*2.0), ...
                       0.35*exp(1j*2.8), 0.25*exp(1j*1.5)];
    elseif contains(preset, '3径 短时延')
        cp.delays_s = [0, 0.2, 0.5] * 1e-3;
        cp.gains    = [1, 0.4*exp(1j*0.8), 0.2*exp(1j*1.6)];
    elseif contains(preset, '单径 理想')
        cp.delays_s = 0; cp.gains = 1;
    else
        cp.delays_s = [0, 0.167, 0.5, 0.833, 1.333] * 1e-3;
        cp.gains    = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), ...
                       0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
    end
    cp.num_paths = length(cp.delays_s);
end

function update_rx_panel(t_in, t_out, info)
    if strcmp(t_in, t_out)
        app.text_out.Value = t_out;
        app.text_out.FontColor = [0.1 0.5 0.1];
    else
        app.text_out.Value = sprintf('%s\n[期望] %s', t_out, t_in);
        app.text_out.FontColor = [0.7 0.2 0.2];
    end

    app.lbl_det.Text = sprintf('%d', info.N_detected);
    app.lbl_exp.Text = sprintf('%d', info.N_expected);
    app.lbl_match.Text = tern(strcmp(t_in, t_out), '✓ 一致', '✗ 不一致');
    app.lbl_thresh.Text = sprintf('%.0f / %.0f', ...
        info.peaks_info.threshold, info.peaks_info.noise_floor);

    % uitable 数据
    decoded = info.decoded{1};
    rows = cell(length(decoded), 6);
    for i = 1:length(decoded)
        d = decoded{i};
        preview = d.text;
        if length(preview) > 30, preview = [preview(1:27) '...']; end
        rows{i, 1} = i;
        rows{i, 2} = d.idx;
        rows{i, 3} = preview;
        rows{i, 4} = tern(d.ok, 'PASS', 'FAIL');
        rows{i, 5} = sprintf('%.3f', d.sync_peak);
        rows{i, 6} = d.k;
    end
    app.tbl.Data = rows;
end

function s = tern(cond, a, b)
    if cond, s = a; else, s = b; end
end

function set_status(msg, color, enable_btn)
    app.status_lbl.Text = msg;
    app.status_lbl.FontColor = color;
    if strcmp(enable_btn, 'on'), app.tx_btn.Enable = 'on'; end
    drawnow;
end

function update_capacity_hint()
    sel = app.payload_dd.Value;
    pl_match = regexp(sel, '^(\d+)', 'tokens', 'once');
    if ~isempty(pl_match), pl_bits = str2double(pl_match{1}); else, pl_bits = 256; end
    max_bytes = floor(pl_bits / 8);

    txt = app.text_in.Value;
    if iscell(txt), txt = strjoin(txt, newline); end
    try, used_bytes = length(unicode2native(strtrim(txt), 'UTF-8'));
    catch, used_bytes = 0; end
    est_frames = max(1, ceil(used_bytes / max_bytes));

    % 帧时长 ~ payload_bits / 750 bps + 0.2s preamble
    % 简化：1 帧 ≈ 0.2 + bits/750 秒
    est_dur = est_frames * (0.2 + pl_bits / 750);

    if est_frames > 255
        marker = sprintf('  ⚠ 超过 255 帧上限！');
        color = [0.85 0.10 0.10];
    elseif est_frames > 30
        marker = sprintf('  (帧数较多，wav 较长)');
        color = [0.85 0.50 0.10];
    else
        marker = '';
        color = [0.3 0.3 0.3];
    end

    app.lbl_hint.Text = sprintf( ...
        '当前文本: %d 字节 → 切分为 %d 帧（每帧 ≤ %d 字节）│ 总 wav ≈ %.1fs%s', ...
        used_bytes, est_frames, max_bytes, est_dur, marker);
    app.lbl_hint.FontColor = color;
end

function append_log(msg)
    cur = app.log_area.Value;
    if ischar(cur)
        if isempty(cur), cur = {}; else, cur = {cur}; end
    elseif ~iscell(cur)
        cur = cellstr(cur);
    end
    cur = cur(~cellfun(@isempty, cur));
    cur{end+1} = sprintf('%s %s', datestr(now, 'HH:MM:SS'), msg);
    if length(cur) > 120, cur = cur(end-100:end); end
    app.log_area.Value = cur;
    try, scroll(app.log_area, 'bottom'); catch, end
end

end
