function p1_demo_ui()
% 功能：Streaming P1 交互式 demo UI
% 版本：V1.0.0
% 用法：
%   在 MATLAB 命令行执行 p1_demo_ui() 即启动 UI
%   左栏输入文本 + 信道参数 → 点"Transmit" → 右栏显示解码文本 + 指标 + 可视化
%
% 依赖：14_Streaming 全部函数；02/03/05/08/09 模块
% 布局：uifigure + uigridlayout（需 R2018b+）

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
app.session = '';
app.last_info = [];
app.last_ch_params = [];

%% ---- 主 figure（原始浅色风，简洁）----
app.fig = uifigure('Name', 'Streaming P1 — FH-MFSK Loopback Demo', ...
    'Position', [60 60 1500 900], 'Color', [0.95 0.95 0.96]);

main = uigridlayout(app.fig, [3 1]);
main.RowHeight = {90, '1x', 260};
main.ColumnWidth = {'1x'};
main.Padding = [10 10 10 10];
main.RowSpacing = 8;

% ==== 顶栏 ====
top = uigridlayout(main, [1 3]);
top.Layout.Row = 1;
top.ColumnWidth = {'1x', 350, 180};
title_lbl = uilabel(top, 'Text', 'Streaming P1 — FH-MFSK 水声通信 loopback demo', ...
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

% ---- TX Panel ----
tx_panel = uipanel(mid, 'Title', 'TX 发射端', 'FontSize', 13, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.98 0.98 1.0]);
tx_panel.Layout.Column = 1;
tx_grid = uigridlayout(tx_panel, [11 2]);
tx_grid.RowHeight = {25, 110, 25, 30, 30, 30, 30, 30, 30, 25, '1x'};
tx_grid.ColumnWidth = {130, '1x'};
tx_grid.RowSpacing = 5;

lbl_txt = uilabel(tx_grid, 'Text', '发射文本:', 'FontWeight', 'bold');
lbl_txt.Layout.Row = 1;
app.text_in = uitextarea(tx_grid, 'Value', 'Hello 水声通信 P1 demo 测试帧', ...
    'FontSize', 12, 'ValueChangedFcn', @(~,~) update_capacity_hint());
app.text_in.Layout.Row = [1 2]; app.text_in.Layout.Column = 2;

lbl_ch = uilabel(tx_grid, 'Text', '信道参数:', 'FontWeight', 'bold');
lbl_ch.Layout.Row = 3;

% SNR (dB)
lbl_snr = uilabel(tx_grid, 'Text', 'SNR (dB):');
lbl_snr.Layout.Row = 4; lbl_snr.Layout.Column = 1;
app.snr_edit = uieditfield(tx_grid, 'numeric', 'Value', 15, ...
    'Limits', [-20 40], 'ValueDisplayFormat', '%g');
app.snr_edit.Layout.Row = 4; app.snr_edit.Layout.Column = 2;

% Doppler (Hz)
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

% 帧长度
lbl_len = uilabel(tx_grid, 'Text', '帧长度:');
lbl_len.Layout.Row = 9; lbl_len.Layout.Column = 1;
app.len_dd = uidropdown(tx_grid, ...
    'Items', {'短 (~1.0s, 512 bits)', '中 (~3.0s, 2048 bits)', ...
              '长 (~5.8s, 4096 bits)', '超长 (~11.5s, 8192 bits)'}, ...
    'Value', '中 (~3.0s, 2048 bits)', ...
    'ValueChangedFcn', @(~,~) update_capacity_hint());
app.len_dd.Layout.Row = 9; app.len_dd.Layout.Column = 2;

% 容量提示
app.lbl_hint = uilabel(tx_grid, 'Text', '', ...
    'FontColor', [0.3 0.3 0.3], 'FontSize', 10);
app.lbl_hint.Layout.Row = 10; app.lbl_hint.Layout.Column = [1 2];

% Log area
log_panel = uipanel(tx_grid, 'Title', 'Log', 'FontSize', 11);
log_panel.Layout.Row = 11; log_panel.Layout.Column = [1 2];
log_grid = uigridlayout(log_panel, [1 1]);
log_grid.Padding = [5 5 5 5];
app.log_area = uitextarea(log_grid, 'Editable', 'off', ...
    'FontName', 'Consolas', 'FontSize', 10);

% ---- RX Panel ----
rx_panel = uipanel(mid, 'Title', 'RX 接收端', 'FontSize', 13, 'FontWeight', 'bold', ...
    'BackgroundColor', [1.0 0.98 0.95]);
rx_panel.Layout.Column = 2;
rx_grid = uigridlayout(rx_panel, [4 2]);
rx_grid.RowHeight = {25, 120, 25, '1x'};
rx_grid.ColumnWidth = {130, '1x'};
rx_grid.RowSpacing = 5;

lbl_out = uilabel(rx_grid, 'Text', '解码文本:', 'FontWeight', 'bold');
lbl_out.Layout.Row = 1;
app.text_out = uitextarea(rx_grid, 'Editable', 'off', 'Value', '(等待发射...)', ...
    'FontSize', 12);
app.text_out.Layout.Row = [1 2]; app.text_out.Layout.Column = 2;

lbl_met = uilabel(rx_grid, 'Text', '同步/校验指标:', 'FontWeight', 'bold');
lbl_met.Layout.Row = 3;

met_panel = uipanel(rx_grid, 'FontSize', 10);
met_panel.Layout.Row = 4; met_panel.Layout.Column = [1 2];
met_grid = uigridlayout(met_panel, [8 2]);
met_grid.RowHeight = repmat({22}, 1, 8);
met_grid.ColumnWidth = {130, '1x'};
met_grid.Padding = [8 8 8 8];
met_grid.RowSpacing = 2;

labels = {'Header CRC', 'Header MAGIC', 'Payload CRC', ...
          'LFM pos (sample)', 'Sync peak', ...
          'Header.scheme', 'Header.idx / len', 'Header.src/dst'};
app.metric_lbls = cell(1, length(labels));
for i = 1:length(labels)
    uilabel(met_grid, 'Text', [labels{i} ':'], 'FontName', 'Consolas');
    app.metric_lbls{i} = uilabel(met_grid, 'Text', '—', ...
        'FontName', 'Consolas', 'FontWeight', 'bold');
end

% ==== 底部：Tab 可视化 ====
bot = uitabgroup(main);
bot.Layout.Row = 3;

app.tabs = struct();
tab_specs = {
    'tx_wave',   'TX 波形+帧结构';
    'rx_wave',   'RX 波形+同步';
    'spectrum',  '频谱对比';
    'time_zoom', '数据段时域对比';
    'lfm_sync',  'LFM 同步峰';
    'energy',    'FSK 能量矩阵';
    'cir',       '信道 CIR'};
for ti = 1:size(tab_specs, 1)
    tabname = tab_specs{ti, 1};
    tabtitle = tab_specs{ti, 2};
    tab = uitab(bot, 'Title', tabtitle);
    tab_grid = uigridlayout(tab, [1 1]);
    tab_grid.Padding = [8 8 8 8];
    ax_i = uiaxes(tab_grid);
    % 启动占位
    text(ax_i, 0.5, 0.5, '请按 "▶ Transmit" 生成数据', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'FontSize', 14, 'Color', [0.5 0.5 0.5]);
    ax_i.XColor = 'none'; ax_i.YColor = 'none';
    app.tabs.(tabname) = ax_i;
end

%% ---- 初始 log ----
append_log('[UI] p1_demo_ui 启动完毕');
append_log(sprintf('[UI] fs=%d, fc=%d, FH-MFSK %d-FSK', ...
    app.sys.fs, app.sys.fc, app.sys.fhmfsk.M));

% 初始化容量提示
update_capacity_hint();

%% ============================================================
%% 内部函数
%% ============================================================

% ---- 发送按钮回调 ----
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
        append_log(sprintf('[IN] "%s" (%d chars)', text_in_str, length(text_in_str)));

        % 1b. 根据帧长度下拉覆盖 sys.frame.payload_bits
        len_sel = app.len_dd.Value;
        if contains(len_sel, '512'),       app.sys.frame.payload_bits = 512;
        elseif contains(len_sel, '2048'),  app.sys.frame.payload_bits = 2048;
        elseif contains(len_sel, '4096'),  app.sys.frame.payload_bits = 4096;
        elseif contains(len_sel, '8192'),  app.sys.frame.payload_bits = 8192;
        end
        app.sys.frame.body_bits = app.sys.frame.header_bits + ...
            app.sys.frame.payload_bits + app.sys.frame.payload_crc_bits;
        append_log(sprintf('[CFG] payload_bits=%d, body_bits=%d', ...
            app.sys.frame.payload_bits, app.sys.frame.body_bits));

        % 容量预检
        max_bytes = floor(app.sys.frame.payload_bits / 8);
        used_bytes = length(unicode2native(text_in_str, 'UTF-8'));
        if used_bytes > max_bytes
            err_msg = sprintf('文本 %d 字节超出帧容量 %d 字节，请加大"帧长度"或缩短文本', ...
                used_bytes, max_bytes);
            append_log(['[ABORT] ' err_msg]);
            set_status(['Error: ' err_msg], [0.7 0.2 0.2], 'on');
            return;
        end

        % 2. 创建 session
        set_status('Creating session...', [0.2 0.4 0.7], 'off');
        drawnow;
        session_root = fullfile(app.proj_root, 'modules', '14_Streaming', 'sessions');
        app.session = create_session_dir(session_root);
        append_log(sprintf('[SESSION] %s', app.session));

        % 3. TX
        set_status('TX 发射中...', [0.2 0.4 0.7], 'off'); drawnow;
        tx_stream_p1(text_in_str, app.session, app.sys);
        append_log('[TX] raw_frames/0001.wav 完成');

        % 4. Channel
        set_status('Channel 仿真中...', [0.7 0.4 0.1], 'off'); drawnow;
        app.last_ch_params = build_channel_params();
        channel_simulator_p1(app.session, app.last_ch_params, app.sys);
        fd_eq = app.last_ch_params.doppler_rate * app.sys.fc;
        append_log(sprintf('[CHAN] SNR=%.1fdB, Doppler=%.2fHz, fading=%s/fd=%gHz, %d径, 最大时延=%.2fms', ...
            app.last_ch_params.snr_db, fd_eq, ...
            app.last_ch_params.fading_type, app.last_ch_params.fading_fd_hz, ...
            app.last_ch_params.num_paths, max(app.last_ch_params.delays_s)*1000));

        % 5. RX
        set_status('RX 解码中...', [0.7 0.4 0.1], 'off'); drawnow;
        [text_out_str, info] = rx_stream_p1(app.session, app.sys);
        app.last_info = info;
        append_log(sprintf('[RX] "%s"', text_out_str));
        append_log(sprintf('[RX] hdr.crc=%d payload.crc=%d sync_peak=%.3f', ...
            info.hdr.crc_ok, info.payload_crc_ok, info.sync_peak));

        % 6. 更新 RX 面板
        update_rx_panel(text_in_str, text_out_str, info);

        % 7. 可视化
        set_status('生成可视化...', [0.2 0.4 0.7], 'off'); drawnow;
        ax_s = struct();
        fn = fieldnames(app.tabs);
        for ii = 1:numel(fn)
            ax_s.(fn{ii}) = app.tabs.(fn{ii});
        end
        visualize_p1_frame(app.session, app.sys, info, ...
            'Axes', ax_s, 'ChParams', app.last_ch_params);

        % 8. 结果
        if strcmp(text_in_str, text_out_str)
            set_status('✓ 成功：文本完全复原', [0.1 0.5 0.1], 'on');
        else
            set_status('⚠ 文本不一致（见 log）', [0.7 0.5 0.1], 'on');
        end
        append_log('[DONE]');

    catch ME
        append_log(sprintf('[ERROR] %s', ME.message));
        append_log(sprintf('  @ %s line %d', ...
            ME.stack(1).name, ME.stack(1).line));
        set_status(sprintf('Error: %s', ME.message), [0.7 0.2 0.2], 'on');
    end
end

% ---- 根据 preset + SNR + Doppler + 衰落类型字段构造信道参数 ----
function cp = build_channel_params()
    preset = app.preset_dd.Value;
    cp = struct();
    cp.fs = app.sys.fs;
    cp.snr_db = app.snr_edit.Value;

    % 衰落类型
    fad_sel = app.fading_dd.Value;
    if startsWith(fad_sel, 'slow'),      cp.fading_type = 'slow';
    elseif startsWith(fad_sel, 'fast'),  cp.fading_type = 'fast';
    else,                                 cp.fading_type = 'static';
    end
    cp.fading_fd_hz = app.jakes_fd_edit.Value;

    % 宽带多普勒：UI 输入 Hz @ fc，转为伸缩率 α = fd / fc
    fd_hz = app.doppler_edit.Value;
    cp.doppler_rate = fd_hz / app.sys.fc;

    cp.seed = 42;

    % Preset 只决定 delays + gains（CIR 形状）
    if contains(preset, '5径 标准')
        cp.delays_s = [0, 0.167, 0.5, 0.833, 1.333] * 1e-3;
        cp.gains    = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), ...
                       0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
    elseif contains(preset, '5径 深衰减')
        cp.delays_s = [0, 0.3, 0.7, 1.1, 1.5] * 1e-3;
        cp.gains    = [0.4, 0.9*exp(1j*1.0), 0.7*exp(1j*2.0), ...
                       0.5*exp(1j*2.8), 0.3*exp(1j*1.5)];
    elseif contains(preset, '3径 短时延')
        cp.delays_s = [0, 0.2, 0.5] * 1e-3;
        cp.gains    = [1, 0.4*exp(1j*0.8), 0.2*exp(1j*1.6)];
    elseif contains(preset, '单径 理想')
        cp.delays_s = 0;
        cp.gains    = 1;
    else
        % fallback
        cp.delays_s = [0, 0.167, 0.5, 0.833, 1.333] * 1e-3;
        cp.gains    = [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), ...
                       0.2*exp(1j*2.0), 0.1*exp(1j*0.8)];
    end
    cp.num_paths = length(cp.delays_s);
end

% ---- 更新 RX 面板指标 ----
function update_rx_panel(t_in, t_out, info)
    if strcmp(t_in, t_out)
        app.text_out.Value = t_out;
        app.text_out.FontColor = [0.1 0.5 0.1];
    else
        app.text_out.Value = sprintf('%s\n[差异] 期望: %s', t_out, t_in);
        app.text_out.FontColor = [0.7 0.2 0.2];
    end

    hdr = info.hdr;
    check = @(ok) tern(ok, '✓', '✗');
    vals = { ...
        check(hdr.crc_ok), ...
        check(hdr.magic_ok), ...
        check(info.payload_crc_ok), ...
        sprintf('%d', info.lfm_pos), ...
        sprintf('%.3f', info.sync_peak), ...
        sprintf('%d', hdr.scheme), ...
        sprintf('%d / %d bits', hdr.idx, hdr.len), ...
        sprintf('%d / %d', hdr.src, hdr.dst)};
    for i = 1:length(vals)
        app.metric_lbls{i}.Text = vals{i};
    end
end

function s = tern(cond, a, b)
    if cond, s = a; else, s = b; end
end

% ---- 设置状态 ----
function set_status(msg, color, enable_btn)
    app.status_lbl.Text = msg;
    app.status_lbl.FontColor = color;
    if strcmp(enable_btn, 'on')
        app.tx_btn.Enable = 'on';
    end
    drawnow;
end

% ---- 更新容量提示（最大可发字节数 + 当前已用）----
function update_capacity_hint()
    % 从下拉解析 payload_bits
    sel = app.len_dd.Value;
    if contains(sel, '512'),       pl_bits = 512;
    elseif contains(sel, '2048'),  pl_bits = 2048;
    elseif contains(sel, '4096'),  pl_bits = 4096;
    elseif contains(sel, '8192'),  pl_bits = 8192;
    else,                          pl_bits = 2048;
    end
    max_bytes = floor(pl_bits / 8);

    % 计算当前文本字节数（UTF-8）
    txt = app.text_in.Value;
    if iscell(txt), txt = strjoin(txt, newline); end
    try
        used_bytes = length(unicode2native(txt, 'UTF-8'));
    catch
        used_bytes = 0;
    end

    % 估算汉字数（UTF-8 一个汉字 3 字节）
    max_chinese = floor(max_bytes / 3);

    % 颜色：超出红色，>=80% 橙色，否则灰色
    if used_bytes > max_bytes
        color = [0.85 0.10 0.10];
        marker = ' ⚠ 超出！';
    elseif used_bytes > max_bytes * 0.8
        color = [0.85 0.50 0.10];
        marker = '';
    else
        color = [0.3 0.3 0.3];
        marker = '';
    end

    app.lbl_hint.Text = sprintf( ...
        '容量: 最多 %d 字节（≈%d ASCII 或 ≈%d 汉字） │ 当前: %d 字节%s', ...
        max_bytes, max_bytes, max_chinese, used_bytes, marker);
    app.lbl_hint.FontColor = color;
end

% ---- 追加 log ----
function append_log(msg)
    cur = app.log_area.Value;
    if ischar(cur)
        if isempty(cur), cur = {}; else, cur = {cur}; end
    elseif ~iscell(cur)
        cur = cellstr(cur);
    end
    % 移除空字符串行（防止首次空 Value 产生空白头）
    cur = cur(~cellfun(@isempty, cur));

    newline_msg = sprintf('%s %s', datestr(now, 'HH:MM:SS'), msg);
    cur{end+1} = newline_msg;

    if length(cur) > 120
        cur = cur(end-100:end);
    end
    app.log_area.Value = cur;
    try
        scroll(app.log_area, 'bottom');
    catch
        % 某些 MATLAB 版本 scroll 在 textarea 上不可用，忽略
    end
end

end
