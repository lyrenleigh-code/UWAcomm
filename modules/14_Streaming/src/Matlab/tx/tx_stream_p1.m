function tx_stream_p1(text, session, sys)
% 功能：TX 发射链（P1 单帧 FH-MFSK）
% 版本：V1.0.0
% 输入：
%   text    - 输入文本字符串（UTF-8）
%   session - 会话目录（由 create_session_dir 创建）
%   sys     - 系统参数
% 产出：
%   <session>/raw_frames/0001.wav       TX 原始通带信号
%   <session>/raw_frames/0001.ready     完成标记
%   <session>/raw_frames/0001.scale.mat 归一化因子
%   <session>/raw_frames/0001.meta.mat  TX 侧 meta（P1 临时桥接，P3/P4 去掉）

frame_idx = 1;

% ---- 1. 文本 → bits ----
payload_raw = text_to_bits(text);
payload_bits_limit = sys.frame.payload_bits;
assert(length(payload_raw) <= payload_bits_limit, ...
    'tx_stream_p1: P1 单帧 payload 限制 %d bits，输入 %d bits', ...
    payload_bits_limit, length(payload_raw));

% ---- 2. Payload = [raw | pad(zeros) | CRC16(raw)] ----
pad_bits = zeros(1, payload_bits_limit - length(payload_raw));
crc_payload = crc16(payload_raw);
payload_full = [payload_raw, pad_bits, crc_payload];   % 512 + 16 = 528

% ---- 3. 构 header ----
hdr_input = struct();
hdr_input.scheme    = sys.frame.scheme_fhmfsk;
hdr_input.idx       = 1;
hdr_input.len       = length(payload_raw);
hdr_input.mod_level = 1;
hdr_input.flags     = 1;   % bit0=last_frame
hdr_input.src       = 0;
hdr_input.dst       = 0;
hdr_bits = frame_header('pack', hdr_input, sys);   % 128

% ---- 4. 完整 body bits ----
body_bits = [hdr_bits, payload_full];   % 128 + 528 = 656
assert(length(body_bits) == sys.frame.body_bits, ...
    'tx_stream_p1: body_bits 长度错配 (got %d, expect %d)', ...
    length(body_bits), sys.frame.body_bits);

% ---- 5. FH-MFSK 调制 ----
[body_bb, meta_modem] = modem_encode_fhmfsk(body_bits, sys);

% ---- 6. 组装物理帧 ----
[frame_bb, meta_frame] = assemble_physical_frame(body_bb, sys);

% ---- 7. 上变频到 passband ----
[frame_pb, ~] = upconvert(frame_bb, sys.fs, sys.fc);

% ---- 8. 写 wav + .ready + .scale.mat ----
subdir = fullfile(session, 'raw_frames');
wav_write_frame(frame_pb, subdir, frame_idx, sys);

% ---- 9. 写 meta（P1 临时桥接，供 RX 端免解析 header 即可）----
meta_full = struct();
meta_full.modem      = meta_modem;
meta_full.frame      = meta_frame;
meta_full.hdr_input  = hdr_input;
meta_full.input_text = text;
meta_full.input_bits_len = length(payload_raw);
save(fullfile(subdir, sprintf('%04d.meta.mat', frame_idx)), '-struct', 'meta_full');

fprintf('[TX] frame %04d: "%s" (%d chars, %d bits) → %d samples wav (%.2f s)\n', ...
    frame_idx, text, length(text), length(payload_raw), ...
    length(frame_pb), length(frame_pb)/sys.fs);

end
