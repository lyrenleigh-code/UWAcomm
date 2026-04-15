function tx_stream_p2(text, session, sys)
% 功能：多帧 TX —— text → 切分 N 帧 → 串联 → 单 wav
% 版本：V1.0.0（P2）
% 输入：
%   text    - UTF-8 字符串（任意长度，自动按 sys.frame.payload_bits/8 字节切分）
%   session - 会话目录
%   sys     - 系统参数
% 产出：
%   <session>/raw_frames/0001.wav      多帧串联通带 wav
%   <session>/raw_frames/0001.ready    完成标记
%   <session>/raw_frames/0001.scale.mat 归一化因子
%   <session>/raw_frames/0001.meta.mat  含 N_frames + 各帧 modem/frame meta + 切分 chunks

frame_idx_outer = 1;

% ---- 1. 文本切分 ----
max_bytes = floor(sys.frame.payload_bits / 8);
chunks = text_chunker(text, max_bytes);
N_frames = length(chunks);
assert(N_frames >= 1, 'tx_stream_p2: 文本切分后无帧');
assert(N_frames <= 255, 'tx_stream_p2: 帧数 %d 超过 idx 字段上限 255', N_frames);
fprintf('[TX-P2] 文本切为 %d 帧（每帧最多 %d 字节 = ~%d ASCII / ~%d 汉字）\n', ...
    N_frames, max_bytes, max_bytes, floor(max_bytes/3));

% ---- 2. 预生成第一帧以确定单帧样本数（用于预分配） ----
[probe_pb, meta_modem_probe, meta_frame_probe] = build_one_frame(chunks{1}, 1, ...
    (N_frames == 1), sys);
single_frame_samples = length(probe_pb);

% ---- 3. 预分配多帧 wav ----
multi_frame_pb = zeros(1, N_frames * single_frame_samples);
modem_metas = cell(1, N_frames);
frame_metas = cell(1, N_frames);

% 第一帧已生成
multi_frame_pb(1:single_frame_samples) = probe_pb;
modem_metas{1} = meta_modem_probe;
frame_metas{1} = meta_frame_probe;
fprintf('[TX-P2] 帧 1/%d: "%s" (%d bits, last=%d)\n', ...
    N_frames, chunks{1}, length(text_to_bits(chunks{1})), N_frames == 1);

% ---- 4. 生成剩余帧 ----
for fi = 2:N_frames
    is_last = (fi == N_frames);
    [frame_pb, mm, fm] = build_one_frame(chunks{fi}, fi, is_last, sys);

    % 长度校验（理论上所有帧应等长）
    if length(frame_pb) ~= single_frame_samples
        warning('tx_stream_p2: 帧 %d 长度 %d 不等于第 1 帧长度 %d，截断/补零', ...
            fi, length(frame_pb), single_frame_samples);
        if length(frame_pb) > single_frame_samples
            frame_pb = frame_pb(1:single_frame_samples);
        else
            frame_pb = [frame_pb, zeros(1, single_frame_samples - length(frame_pb))];
        end
    end

    offset = (fi - 1) * single_frame_samples;
    multi_frame_pb(offset+1 : offset+single_frame_samples) = frame_pb;
    modem_metas{fi} = mm;
    frame_metas{fi} = fm;

    fprintf('[TX-P2] 帧 %d/%d: "%s" (%d bits, last=%d)\n', ...
        fi, N_frames, chunks{fi}, length(text_to_bits(chunks{fi})), is_last);
end

% ---- 5. 写多帧 wav ----
subdir = fullfile(session, 'raw_frames');
wav_write_frame(multi_frame_pb, subdir, frame_idx_outer, sys);

% ---- 6. 写 meta ----
meta_full = struct();
meta_full.N_frames             = N_frames;
meta_full.modem_metas          = {modem_metas};
meta_full.frame_metas          = {frame_metas};
meta_full.input_text           = text;
meta_full.chunks               = {chunks};
meta_full.single_frame_samples = single_frame_samples;
meta_full.total_samples        = length(multi_frame_pb);
save(fullfile(subdir, sprintf('%04d.meta.mat', frame_idx_outer)), '-struct', 'meta_full');

fprintf('[TX-P2] 总 wav %d 样本 (%.2f s, %d 帧 × %.2f s/帧)\n', ...
    length(multi_frame_pb), length(multi_frame_pb)/sys.fs, N_frames, ...
    single_frame_samples/sys.fs);

end

% ================================================================
function [frame_pb, meta_modem, meta_frame] = build_one_frame(chunk_text, idx, is_last, sys)
% 单帧构造（封装 P1 的 TX 逻辑）
payload_raw = text_to_bits(chunk_text);
assert(length(payload_raw) <= sys.frame.payload_bits, ...
    'build_one_frame: chunk %d 文本字节超出 payload_bits', idx);

pad = zeros(1, sys.frame.payload_bits - length(payload_raw));
crc_p = crc16(payload_raw);
payload_full = [payload_raw, pad, crc_p];

hdr_input = struct();
hdr_input.scheme    = sys.frame.scheme_fhmfsk;
hdr_input.idx       = idx;
hdr_input.len       = length(payload_raw);
hdr_input.mod_level = 1;
hdr_input.flags     = double(is_last);   % bit0 = last_frame
hdr_input.src       = 0;
hdr_input.dst       = 0;
hdr_bits = frame_header('pack', hdr_input, sys);

body_bits = [hdr_bits, payload_full];
[body_bb, meta_modem] = modem_encode_fhmfsk(body_bits, sys);
[frame_bb, meta_frame] = assemble_physical_frame(body_bb, sys);
[frame_pb, ~] = upconvert(frame_bb, sys.fs, sys.fc);
end
