function [text, info] = rx_stream_p1(session, sys, opts)
% 功能：RX 接收链（P1 单帧 FH-MFSK）
% 版本：V1.1.0（2026-04-23：去 oracle α，默认盲估 estimate_alpha_dual_hfm；
%                opts.use_oracle_alpha=true 回退 chinfo.mat 读 α）
%       V1.0.0
% 输入：
%   session - 会话目录
%   sys     - 系统参数
%   opts    - optional struct:
%     .use_oracle_alpha - bool (default false) 回退到 chinfo.mat oracle α
% 输出：
%   text - 解码出的 UTF-8 字符串
%   info - struct
%       .hdr             解析的帧头（含 crc_ok, magic_ok）
%       .payload_crc_ok  payload CRC 校验结果
%       .lfm_pos         LFM2 定时位置
%       .sync_peak       LFM 匹配滤波归一化峰值
%       .decode_info     modem_decode 的 info
% 产出：
%   <session>/rx_out/0001.meta.mat    RX 解码详情
%   <session>/rx_out/session_text.log 累积文本（追加）

if nargin < 3 || ~isstruct(opts), opts = struct(); end

frame_idx = 1;

% ---- 1. 读 channel_frames/0001.wav + TX meta 桥接 ----
chan_subdir = fullfile(session, 'channel_frames');
[rx_pb, fs] = wav_read_frame(chan_subdir, frame_idx);
assert(fs == sys.fs);

meta_tx_path = fullfile(session, 'raw_frames', sprintf('%04d.meta.mat', frame_idx));
assert(exist(meta_tx_path, 'file') == 2, ...
    'rx_stream_p1: 缺少 TX meta %s（P1 临时桥接，P3/P4 去掉）', meta_tx_path);
meta_tx = load(meta_tx_path);

% ---- 2. 下变频 ----
[bb_raw, ~] = downconvert(rx_pb, sys.fs, sys.fc, sys.fhmfsk.total_bw);

% ---- 2b. Doppler 补偿（2026-04-23 P1 去 oracle：default estimate_alpha_dual_hfm 盲估）----
% 可选 opts.use_oracle_alpha=true 回退到 chinfo.mat 读 α（backwards-compat）
use_oracle_alpha = isfield(opts, 'use_oracle_alpha') && opts.use_oracle_alpha;
alpha = 0;
if use_oracle_alpha
    chinfo_path = fullfile(session, 'channel_frames', sprintf('%04d.chinfo.mat', frame_idx));
    if exist(chinfo_path, 'file')
        ci = load(chinfo_path);
        if isfield(ci, 'doppler_rate'), alpha = ci.doppler_rate; end
    end
else
    % 盲估计：双 HFM 时延差（等价 13_SourceCode 各 runner 的 cascade stage 1）
    try
        [alpha, conf] = estimate_alpha_dual_hfm(bb_raw, sys);
        fprintf('[RX] α 盲估 (dual-HFM): α=%.3e, conf=%.2f\n', alpha, conf);
    catch ME
        fprintf('[RX] α 盲估失败 (%s)，fallback α=0\n', ME.message);
        alpha = 0;
    end
end
if abs(alpha) > 1e-10
    % 反向 resample：把 RX 时间轴拉回 TX 时间轴
    % 信道做的是 rx(t) = tx(t·(1+α))；反向 = 在 t·(1-α)/(1+α) 重采样
    N_rx = length(bb_raw);
    t_rx_orig = (0:N_rx-1) / sys.fs;
    t_rx_resampled = t_rx_orig / (1 + alpha);
    bb_raw = interp1(t_rx_orig, bb_raw, t_rx_resampled, 'spline', 0);
    fprintf('[RX] Doppler 补偿: α=%.3e (fd@fc=%gHz)\n', alpha, alpha*sys.fc);
end

% ---- 3. LFM 匹配滤波定位 ----
[lfm_pos, sync_peak, ~] = detect_lfm_start(bb_raw, sys, meta_tx.frame);

% ---- 4. 提取 body 基带段 ----
ds = lfm_pos + meta_tx.frame.data_offset_from_lfm_head;
N_body = meta_tx.modem.N_sym * meta_tx.modem.samples_per_sym;
de = ds + N_body - 1;
if de > length(bb_raw)
    body_bb = [bb_raw(ds:end), zeros(1, de - length(bb_raw))];
else
    body_bb = bb_raw(ds:de);
end

% ---- 5. FH-MFSK 解 ----
[body_bits, decode_info] = modem_decode_fhmfsk(body_bb, sys, meta_tx.modem);

% body_bits 应该 = sys.frame.body_bits = 656
assert(length(body_bits) == sys.frame.body_bits, ...
    'rx_stream_p1: body_bits 长度错配 (got %d, expect %d)', ...
    length(body_bits), sys.frame.body_bits);

% ---- 6. 解帧头 ----
hdr_bits = body_bits(1 : sys.frame.header_bits);
hdr = frame_header('unpack', hdr_bits, sys);

% ---- 7. 取 payload + CRC 校验 ----
p_start = sys.frame.header_bits + 1;
p_end   = sys.frame.header_bits + sys.frame.payload_bits;
c_start = p_end + 1;
c_end   = p_end + sys.frame.payload_crc_bits;

payload_all = body_bits(p_start : p_end);
payload_crc_recv = body_bits(c_start : c_end);

% 只取前 hdr.len 位作为有效 payload
if hdr.len > 0 && hdr.len <= sys.frame.payload_bits
    payload_real = payload_all(1:hdr.len);
else
    payload_real = payload_all;   % len 字段损坏，仍输出
end

crc_calc = crc16(payload_real);
payload_crc_ok = isequal(payload_crc_recv(:).', crc_calc(:).');

% ---- 8. bits → text ----
% 需要 8 对齐，hdr.len 应该是 8 的倍数（UTF-8 byte 边界）
if mod(length(payload_real), 8) ~= 0
    warning('rx_stream_p1: payload 长度 %d 不是 8 的倍数，截断到最近倍数', length(payload_real));
    payload_real = payload_real(1 : floor(length(payload_real)/8)*8);
end

try
    text = bits_to_text(payload_real);
catch ME
    warning('rx_stream_p1: UTF-8 解码失败 (%s)，输出 hex', ME.message);
    text = sprintf('<decode_err:%s>', ME.message);
end

% ---- 9. info + 写 rx_out ----
info = struct();
info.hdr            = hdr;
info.payload_crc_ok = payload_crc_ok;
info.lfm_pos        = lfm_pos;
info.sync_peak      = sync_peak;
info.decode_info    = decode_info;

rx_out_dir = fullfile(session, 'rx_out');
rx_meta = struct('text_out', text, 'info', info, 'frame_idx', frame_idx);
save(fullfile(rx_out_dir, sprintf('%04d.meta.mat', frame_idx)), '-struct', 'rx_meta');

% 追加到 session_text.log
log_path = fullfile(rx_out_dir, 'session_text.log');
fid = fopen(log_path, 'a');
fprintf(fid, '[%s] frame %04d: crc_ok=%d text="%s"\n', ...
    datestr(now, 'yyyy-mm-dd HH:MM:SS'), frame_idx, payload_crc_ok, text);
fclose(fid);

fprintf('[RX] frame %04d: "%s" | hdr.crc=%d magic=%d payload.crc=%d | lfm_pos=%d peak=%.3f\n', ...
    frame_idx, text, hdr.crc_ok, hdr.magic_ok, payload_crc_ok, lfm_pos, sync_peak);

end
