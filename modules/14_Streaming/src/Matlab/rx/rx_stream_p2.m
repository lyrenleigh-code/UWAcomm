function [text, info] = rx_stream_p2(session, sys)
% 功能：多帧流式 RX —— channel.wav → 滑动检测 → 逐帧解 → text_assembler
% 版本：V1.0.0（P2）
% 输入：
%   session - 会话目录
%   sys     - 系统参数
% 输出：
%   text - 拼接后的 UTF-8 文本
%   info - struct
%       .detected_starts  检测到的帧起点列表（HFM+ 头位置）
%       .peaks_info       frame_detector 返回的诊断信息
%       .decoded          cell{各帧解码 struct}
%       .N_detected       检测帧数
%       .N_expected       TX 实际帧数（来自 meta_tx）

frame_idx_outer = 1;

% ---- 1. 读 channel.wav ----
chan_subdir = fullfile(session, 'channel_frames');
[rx_pb, fs] = wav_read_frame(chan_subdir, frame_idx_outer);
assert(fs == sys.fs);

% ---- 2. 读 TX meta（拿 single_frame_samples + 各帧 modem/frame meta）----
meta_tx_path = fullfile(session, 'raw_frames', sprintf('%04d.meta.mat', frame_idx_outer));
assert(exist(meta_tx_path, 'file') == 2, ...
    'rx_stream_p2: 缺少 TX meta %s', meta_tx_path);
meta_tx = load(meta_tx_path);

% ---- 3. 下变频（预填零 LPF 暖机，防止首帧 HFM 被边界损坏）----
% downconvert 内部 LPF 是 64 阶 FIR，前 ~64 样本是瞬态。
% 预填零让暖机区域落在填充段，trim 掉后 bb_raw 从样本 1 起干净
N_lpf_warmup = 200;
rx_pb_padded = [zeros(1, N_lpf_warmup), rx_pb(:).'];
[bb_padded, ~] = downconvert(rx_pb_padded, sys.fs, sys.fc, sys.fhmfsk.total_bw);
bb_raw = bb_padded(N_lpf_warmup+1 : end);

% ---- 4. Doppler 补偿（oracle）----
chinfo_path = fullfile(session, 'channel_frames', sprintf('%04d.chinfo.mat', frame_idx_outer));
if exist(chinfo_path, 'file')
    ci = load(chinfo_path);
    if isfield(ci, 'doppler_rate') && abs(ci.doppler_rate) > 1e-10
        alpha = ci.doppler_rate;
        N_rx = length(bb_raw);
        t_orig = (0:N_rx-1) / sys.fs;
        t_query = t_orig / (1 + alpha);
        bb_raw = interp1(t_orig, bb_raw, t_query, 'spline', 0);
        fprintf('[RX-P2] Doppler 补偿 α=%.3e (fd@fc=%gHz)\n', alpha, alpha*sys.fc);
    end
end

% ---- 5. 流式帧检测 ----
det_opts = struct('frame_len_samples', meta_tx.single_frame_samples);
[starts, peaks_info] = frame_detector(bb_raw, sys, det_opts);
fprintf('[RX-P2] 检测到 %d 帧（TX 实际 %d 帧），阈值=%.3f, 噪底=%.3f, 峰max=%.3f\n', ...
    length(starts), meta_tx.N_frames, peaks_info.threshold, ...
    peaks_info.noise_floor, peaks_info.peak_max);

% ---- 6. 逐帧解码 ----
modem_metas = meta_tx.modem_metas{1};
frame_metas = meta_tx.frame_metas{1};
fm_template = frame_metas{1};   % 所有帧结构相同
mm_template = modem_metas{1};

decoded = {};
for ki = 1:length(starts)
    k = starts(ki);
    % 截取本帧窗口（多取一帧时长防边界）
    win_end = min(k + meta_tx.single_frame_samples + 200, length(bb_raw));
    if win_end - k + 1 < meta_tx.single_frame_samples * 0.5
        fprintf('[RX-P2] 检测帧 %d 在 k=%d 但剩余样本不足，跳过\n', ki, k);
        continue;
    end
    frame_win = bb_raw(k:win_end);

    % 帧内 LFM2 精确定位
    try
        [lfm_pos_local, sync_peak, ~] = detect_lfm_start(frame_win, sys, fm_template);
    catch ME
        fprintf('[RX-P2] 检测帧 %d LFM 定位失败: %s\n', ki, ME.message);
        continue;
    end

    ds = lfm_pos_local + fm_template.data_offset_from_lfm_head;
    N_body = mm_template.N_sym * mm_template.samples_per_sym;
    de = ds + N_body - 1;

    if de > length(frame_win)
        body_bb = [frame_win(ds:end), zeros(1, de - length(frame_win))];
    else
        body_bb = frame_win(ds:de);
    end

    % FH-MFSK 解
    [body_bits, ~] = modem_decode_fhmfsk(body_bb, sys, mm_template);
    if length(body_bits) ~= sys.frame.body_bits
        fprintf('[RX-P2] 检测帧 %d body_bits 长度异常 (%d vs %d)，跳过\n', ...
            ki, length(body_bits), sys.frame.body_bits);
        continue;
    end

    % 解 header
    hdr_bits = body_bits(1:sys.frame.header_bits);
    hdr = frame_header('unpack', hdr_bits, sys);

    if ~hdr.crc_ok || ~hdr.magic_ok
        decoded{end+1} = struct('idx', ki, 'text', '', ...
            'ok', false, 'last', false, ...
            'hdr_crc_ok', hdr.crc_ok, 'magic_ok', hdr.magic_ok, ...
            'sync_peak', sync_peak, 'k', k); %#ok<AGROW>
        fprintf('[RX-P2] 检测帧 %d k=%d header 失败 (crc=%d magic=%d)，标 missing\n', ...
            ki, k, hdr.crc_ok, hdr.magic_ok);
        continue;
    end

    % payload 范围
    p_start = sys.frame.header_bits + 1;
    p_end   = p_start + sys.frame.payload_bits - 1;
    c_start = p_end + 1;
    c_end   = p_end + sys.frame.payload_crc_bits;
    payload_all = body_bits(p_start:p_end);
    payload_crc_recv = body_bits(c_start:c_end);

    if hdr.len <= 0 || hdr.len > sys.frame.payload_bits
        decoded{end+1} = struct('idx', hdr.idx, 'text', '', ...
            'ok', false, 'last', false, ...
            'hdr_crc_ok', true, 'magic_ok', true, ...
            'sync_peak', sync_peak, 'k', k); %#ok<AGROW>
        fprintf('[RX-P2] 检测帧 %d idx=%d hdr.len=%d 异常，标 missing\n', ...
            ki, hdr.idx, hdr.len);
        continue;
    end

    payload_real = payload_all(1:hdr.len);
    crc_calc = crc16(payload_real);
    pl_crc_ok = isequal(payload_crc_recv(:).', crc_calc(:).');

    chunk_text = '';
    if pl_crc_ok && mod(length(payload_real), 8) == 0
        try
            chunk_text = bits_to_text(payload_real);
        catch
            pl_crc_ok = false;
        end
    else
        pl_crc_ok = false;
    end

    is_last = bitand(hdr.flags, 1) == 1;
    decoded{end+1} = struct('idx', hdr.idx, 'text', chunk_text, ...
        'ok', pl_crc_ok, 'last', is_last, ...
        'hdr_crc_ok', true, 'magic_ok', true, ...
        'sync_peak', sync_peak, 'k', k); %#ok<AGROW>

    fprintf('[RX-P2] 检测帧 %d k=%d → idx=%d "%s" (crc=%d, last=%d, sync=%.3f)\n', ...
        ki, k, hdr.idx, chunk_text, pl_crc_ok, is_last, sync_peak);
end

% ---- 7. 拼接 ----
text = text_assembler(decoded);

% ---- 8. info + 写 rx_out ----
info = struct();
info.detected_starts = starts;
info.peaks_info      = peaks_info;
info.decoded         = {decoded};
info.N_detected      = length(starts);
info.N_expected      = meta_tx.N_frames;

rx_out_dir = fullfile(session, 'rx_out');
rx_meta = struct('text_out', text, 'info', info, 'frame_idx', frame_idx_outer);
save(fullfile(rx_out_dir, sprintf('%04d.meta.mat', frame_idx_outer)), '-struct', 'rx_meta');

% session_text.log
log_path = fullfile(rx_out_dir, 'session_text.log');
fid = fopen(log_path, 'a');
fprintf(fid, '[%s] P2 detect=%d/expected=%d text="%s"\n', ...
    datestr(now, 'yyyy-mm-dd HH:MM:SS'), info.N_detected, info.N_expected, text);
fclose(fid);

fprintf('[RX-P2] 输出: "%s"\n', text);

end
