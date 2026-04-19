function app = p3_animate_tick(app, t_sec)
% P3_ANIMATE_TICK  on_tick 内的动效更新
%
% 功能：处理呼吸灯、检测闪烁、解码闪烁、FIFO 进度的 per-tick 更新。
%       调用方（on_tick）应在每次 tick 末把更新后的 app 写回外层 workspace。
% 版本：V1.0.0（2026-04-17 视觉升级 Step 4）
% 输入：
%   app    — 主 UI 状态 struct（含句柄）
%   t_sec  — 启动后秒数（用于周期动效）
% 输出：
%   app    — 更新后的 app（动效计数器可能变）

if ~isstruct(app) || ~isfield(app, 'style')
    return;
end
P = app.style.PALETTE;
G = app.style.GLOW;

%% 1. RX 呼吸灯（RX ON 时 status_lbl 字色做 ±15% 亮度插值）
if isfield(app, 'rx_running') && app.rx_running && isgraphics(app.status_lbl)
    phase = 0.5 + 0.5 * sin(2*pi * t_sec / 2.0);  % [0,1]，周期 2s
    brightness = 0.85 + 0.30 * phase;              % [0.85, 1.15]
    base = P.success;
    c = min(1, base .* brightness);
    try
        app.status_lbl.FontColor = c;
    catch
    end
end

%% 2. 检测闪烁（状态从 "空闲" → "检测中" 切换瞬间触发）
if isfield(app, 'flash_det_count') && app.flash_det_count > 0 && isgraphics(app.status_lbl)
    if mod(app.flash_det_count, 2) == 0
        app.status_lbl.BackgroundColor = P.warning_bg;
    else
        app.status_lbl.BackgroundColor = P.success_bg;
    end
    app.flash_det_count = app.flash_det_count - 1;
    if app.flash_det_count == 0
        app.status_lbl.BackgroundColor = P.success_bg;
    end
end

%% 3. 解码成功 flash（text_out 边框短暂切青色）
if isfield(app, 'flash_decode_count') && app.flash_decode_count > 0 && isgraphics(app.text_out)
    if mod(app.flash_decode_count, 2) == 0
        % flash on
        try
            app.text_out.BackgroundColor = G.cyan_soft;
        catch
        end
    else
        try
            app.text_out.BackgroundColor = P.surface_alt;
        catch
        end
    end
    app.flash_decode_count = app.flash_decode_count - 1;
    if app.flash_decode_count == 0
        try
            app.text_out.BackgroundColor = P.surface_alt;
        catch
        end
    end
end

%% 4. FIFO 进度（写到 card_fifo tone 上：< 50% muted / 50-80% accent / > 80% warning）
if isfield(app, 'card_fifo') && isstruct(app.card_fifo) && ...
   isfield(app.card_fifo, 'value') && isgraphics(app.card_fifo.value)
    try
        if isfield(app, 'fifo_capacity') && app.fifo_capacity > 0
            cur = app.fifo_write - app.fifo_read;
            ratio = max(0, min(1, cur / app.fifo_capacity));
            if ratio < 0.5
                app.card_fifo.value.FontColor = P.accent_hi;
            elseif ratio < 0.8
                app.card_fifo.value.FontColor = P.warning;
            else
                app.card_fifo.value.FontColor = P.danger;
            end
        end
    catch
    end
end

%% 5. RX 面板边框：ON 切 active（青），OFF 切 subtle（灰）
if isfield(app, 'rx_panel') && isgraphics(app.rx_panel) && ...
   isprop(app.rx_panel, 'BorderColor')
    if isfield(app, 'rx_running') && app.rx_running
        target = P.border_active;
    else
        target = P.border_subtle;
    end
    try
        if ~isequal(app.rx_panel.BorderColor, target)
            app.rx_panel.BorderColor = target;
        end
    catch
    end
end

end
