function [text, info] = rx_stream_p4(session, sys, opts)
%RX_STREAM_P4 Mixed-scheme Streaming P4 receiver.
%
% RX first decodes the FH-MFSK header, then dispatches the payload segment
% to modem_decode according to header.scheme.

if nargin < 3 || ~isstruct(opts), opts = struct(); end

frame_idx_outer = getfield_def(opts, 'frame_idx', 1);

chan_dir = fullfile(session, 'channel_frames');
[rx_pb, fs] = wav_read_frame(chan_dir, frame_idx_outer);
assert(fs == sys.fs);

meta_tx_path = fullfile(session, 'raw_frames', sprintf('%04d.meta.mat', frame_idx_outer));
assert(exist(meta_tx_path, 'file') == 2, 'rx_stream_p4: missing TX meta %s', meta_tx_path);
meta_tx = load(meta_tx_path);

rx_bw = streaming_rx_bandwidth(sys);
N_lpf_warmup = 200;
rx_pb_padded = [zeros(1, N_lpf_warmup), rx_pb(:).'];
[bb_padded, ~] = downconvert(rx_pb_padded, sys.fs, sys.fc, rx_bw);
bb_raw = bb_padded(N_lpf_warmup+1:end);

alpha = 0;
use_oracle_alpha = isfield(opts, 'use_oracle_alpha') && opts.use_oracle_alpha;
if use_oracle_alpha
    chinfo_path = fullfile(session, 'channel_frames', sprintf('%04d.chinfo.mat', frame_idx_outer));
    if exist(chinfo_path, 'file')
        ci = load(chinfo_path);
        if isfield(ci, 'doppler_rate'), alpha = ci.doppler_rate; end
    end
else
    try
        [alpha, conf] = estimate_alpha_dual_hfm(bb_raw, sys);
        fprintf('[RX-P4] alpha estimate: alpha=%.3e, conf=%.2f\n', alpha, conf);
    catch ME
        fprintf('[RX-P4] alpha estimate failed (%s), fallback alpha=0\n', ME.message);
        alpha = 0;
    end
end
alpha_abs_max = getfield_def(opts, 'alpha_abs_max', 1e-2);
if abs(alpha) > alpha_abs_max
    fprintf('[RX-P4] alpha %.3e outside gate %.3e, fallback alpha=0\n', ...
        alpha, alpha_abs_max);
    alpha = 0;
end
if abs(alpha) > 1e-10
    N_rx = length(bb_raw);
    t_orig = (0:N_rx-1) / sys.fs;
    t_query = t_orig / (1 + alpha);
    bb_raw = interp1(t_orig, bb_raw, t_query, 'spline', 0);
    fprintf('[RX-P4] Doppler compensation alpha=%.3e\n', alpha);
end

det_opts = struct();
det_opts.frame_len_samples = getfield_def(meta_tx, 'min_frame_samples', meta_tx.single_frame_samples);
det_opts.use_predict = false;
det_opts.threshold_K = getfield_def(opts, 'threshold_K', 3);
det_opts.threshold_ratio = getfield_def(opts, 'threshold_ratio', 0.08);
det_opts.min_sep_factor = getfield_def(opts, 'min_sep_factor', 0.65);
[starts, peaks_info] = frame_detector(bb_raw, sys, det_opts);
fprintf('[RX-P4] detected %d frame candidates (TX expected %d)\n', ...
    length(starts), meta_tx.N_frames);

frame_metas = meta_tx.frame_metas{1};
fm_template = frame_metas{1};
[~, header_meta] = modem_encode(zeros(1, sys.frame.header_bits), 'FH-MFSK', sys);
header_samples = header_meta.N_sym * header_meta.samples_per_sym;
if isfield(meta_tx, 'header_samples') && meta_tx.header_samples > 0
    header_samples = meta_tx.header_samples;
end
if isfield(sys.frame, 'header_payload_guard_samp')
    hp_guard = sys.frame.header_payload_guard_samp;
else
    hp_guard = sys.preamble.guard_samp;
end

scheme_names = streaming_scheme_codec('list', [], sys);
dispatch_counts = struct();
for si = 1:length(scheme_names)
    dispatch_counts.(matlab.lang.makeValidName(scheme_names{si})) = 0;
end

decoded = {};
for ki = 1:length(starts)
    k = starts(ki);
    win_end = min(k + meta_tx.single_frame_samples + 500, length(bb_raw));
    if win_end <= k
        continue;
    end
    frame_win = bb_raw(k:win_end);

    try
        [lfm_pos_local, sync_peak, ~] = detect_lfm_start(frame_win, sys, fm_template);
    catch ME
        fprintf('[RX-P4] candidate %d k=%d LFM locate failed: %s\n', ki, k, ME.message);
        continue;
    end

    ds = lfm_pos_local + fm_template.data_offset_from_lfm_head;
    hdr_start = ds;
    hdr_end = hdr_start + header_samples - 1;
    header_bb = slice_or_pad(frame_win, hdr_start, hdr_end);

    try
        [hdr_bits, hdr_info] = modem_decode(header_bb, 'FH-MFSK', sys, header_meta);
        hdr = frame_header('unpack', hdr_bits(1:sys.frame.header_bits), sys);
    catch ME
        fprintf('[RX-P4] candidate %d k=%d header decode error: %s\n', ki, k, ME.message);
        continue;
    end

    if ~hdr.crc_ok || ~hdr.magic_ok
        fprintf('[RX-P4] candidate %d k=%d header failed (crc=%d magic=%d)\n', ...
            ki, k, hdr.crc_ok, hdr.magic_ok);
        continue;
    end

    try
        scheme_name = streaming_scheme_codec('name', hdr.scheme, sys);
    catch ME
        decoded{end+1} = make_fail_record(hdr.idx, '', true, true, sync_peak, k, ...
            sprintf('bad_scheme:%s', ME.message)); %#ok<AGROW>
        fprintf('[RX-P4] frame idx=%d bad scheme code=%d\n', hdr.idx, hdr.scheme);
        continue;
    end

    field_name = matlab.lang.makeValidName(scheme_name);
    dispatch_counts.(field_name) = dispatch_counts.(field_name) + 1;

    tx_record = payload_record_for_idx(meta_tx, hdr.idx);
    modem_params = getfield_def(tx_record, 'modem_params', struct());
    sys_frame = streaming_apply_modem_params(sys, modem_params);

    payload_capacity = streaming_scheme_codec('payload_capacity_bits', scheme_name, sys_frame);
    payload_info_bits = payload_capacity + sys_frame.frame.payload_crc_bits;
    if hdr.len < 0 || hdr.len > payload_capacity
        decoded{end+1} = make_fail_record(hdr.idx, scheme_name, true, true, sync_peak, k, ...
            'payload_len_out_of_range'); %#ok<AGROW>
        fprintf('[RX-P4] frame idx=%d scheme=%s invalid len=%d capacity=%d\n', ...
            hdr.idx, scheme_name, hdr.len, payload_capacity);
        continue;
    end

    payload_meta = getfield_def(tx_record, 'payload_meta', []);
    payload_samples = getfield_def(tx_record, 'payload_samples', 0);
    if ~isstruct(payload_meta) || payload_samples <= 0
        [payload_probe, payload_meta] = modem_encode(zeros(1, payload_info_bits), ...
            scheme_name, sys_frame);
        payload_samples = length(payload_probe);
    end
    payload_start = hdr_end + hp_guard + 1;
    payload_end = payload_start + payload_samples - 1;
    payload_bb = slice_or_pad(frame_win, payload_start, payload_end);

    try
        [payload_bits, payload_info] = modem_decode(payload_bb, scheme_name, sys_frame, payload_meta);
        if length(payload_bits) < payload_info_bits
            payload_bits = [payload_bits(:).', zeros(1, payload_info_bits - length(payload_bits))];
        else
            payload_bits = payload_bits(1:payload_info_bits);
        end
    catch ME
        decoded{end+1} = make_fail_record(hdr.idx, scheme_name, true, true, sync_peak, k, ...
            sprintf('payload_decode_error:%s', ME.message)); %#ok<AGROW>
        fprintf('[RX-P4] frame idx=%d scheme=%s payload decode error: %s\n', ...
            hdr.idx, scheme_name, ME.message);
        continue;
    end

    payload_all = payload_bits(1:payload_capacity);
    payload_crc_recv = payload_bits(payload_capacity+1:payload_capacity+sys_frame.frame.payload_crc_bits);
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
        'scheme', scheme_name, ...
        'hdr_crc_ok', true, 'magic_ok', true, ...
        'payload_crc_ok', pl_crc_ok, ...
        'modem_params', modem_params, ...
        'sync_peak', sync_peak, 'k', k, ...
        'header_info', hdr_info, 'payload_info', payload_info); %#ok<AGROW>

    fprintf('[RX-P4] candidate %d k=%d -> idx=%d scheme=%s text="%s" crc=%d sync=%.3f\n', ...
        ki, k, hdr.idx, scheme_name, chunk_text, pl_crc_ok, sync_peak);
end

text = text_assembler(decoded);

info = struct();
info.detected_starts = starts;
info.peaks_info = peaks_info;
info.decoded = {decoded};
info.N_detected = length(starts);
info.N_expected = meta_tx.N_frames;
info.dispatch_counts = dispatch_counts;
info.alpha = alpha;

rx_out_dir = fullfile(session, 'rx_out');
if ~exist(rx_out_dir, 'dir'), mkdir(rx_out_dir); end
rx_meta = struct('text_out', text, 'info', info, 'frame_idx', frame_idx_outer);
save(fullfile(rx_out_dir, sprintf('%04d.meta.mat', frame_idx_outer)), '-struct', 'rx_meta');
write_rx_json(fullfile(rx_out_dir, sprintf('%04d.meta.json', frame_idx_outer)), ...
    text, info, frame_idx_outer);

ready_path = fullfile(rx_out_dir, sprintf('%04d.ready', frame_idx_outer));
fid_ready = fopen(ready_path, 'w');
fprintf(fid_ready, '%s frame=%04d text_len=%d\n', ...
    datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'), frame_idx_outer, length(text));
fclose(fid_ready);

log_path = fullfile(rx_out_dir, 'session_text.log');
fid = fopen(log_path, 'a');
fprintf(fid, '[%s] P4 detect=%d/expected=%d text="%s"\n', ...
    datestr(now, 'yyyy-mm-dd HH:MM:SS'), info.N_detected, info.N_expected, text);
fclose(fid);

fprintf('[RX-P4] output: "%s"\n', text);

end

% -------------------------------------------------------------------------
function x = slice_or_pad(v, first_idx, last_idx)

if first_idx < 1
    prefix = zeros(1, 1 - first_idx);
    first_idx = 1;
else
    prefix = [];
end

if first_idx > length(v)
    x = zeros(1, last_idx - first_idx + 1 + length(prefix));
    return;
end

last_in = min(last_idx, length(v));
x = [prefix, v(first_idx:last_in)];
need = last_idx - first_idx + 1 + length(prefix);
if length(x) < need
    x = [x, zeros(1, need - length(x))];
end

end

% -------------------------------------------------------------------------
function rec = make_fail_record(idx, scheme, hdr_crc_ok, magic_ok, sync_peak, k, reason)

rec = struct('idx', idx, 'text', '', 'ok', false, 'last', false, ...
    'scheme', scheme, 'hdr_crc_ok', hdr_crc_ok, 'magic_ok', magic_ok, ...
    'payload_crc_ok', false, 'sync_peak', sync_peak, 'k', k, ...
    'reason', reason);

end

% -------------------------------------------------------------------------
function rec = payload_record_for_idx(meta_tx, idx)

rec = struct();
if ~isstruct(meta_tx) || ~isfield(meta_tx, 'payload_records')
    return;
end

records = meta_tx.payload_records;
if iscell(records) && numel(records) == 1 && iscell(records{1})
    records = records{1};
end

if iscell(records)
    if idx >= 1 && idx <= numel(records) && isstruct(records{idx})
        rec = records{idx};
    end
elseif isstruct(records) && idx >= 1 && idx <= numel(records)
    rec = records(idx);
end

end

% -------------------------------------------------------------------------
function bw = streaming_rx_bandwidth(sys)

vals = [sys.preamble.bw_lfm, sys.fhmfsk.total_bw, sys.scfde.total_bw, ...
    sys.ofdm.total_bw, sys.sctde.total_bw, sys.dsss.total_bw, sys.otfs.total_bw];
bw = min(max(vals) * 1.1, 0.95 * (sys.fs / 2));

end

% -------------------------------------------------------------------------
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
end

end

% -------------------------------------------------------------------------
function write_rx_json(path, text, info, frame_idx)

try
    decoded = info.decoded{1};
    frames = cell(1, length(decoded));
    for k = 1:length(decoded)
        d = decoded{k};
        item = struct();
        item.idx = d.idx;
        item.ok = d.ok;
        item.text = d.text;
        item.scheme = getfield_def(d, 'scheme', '');
        item.hdr_crc_ok = getfield_def(d, 'hdr_crc_ok', false);
        item.magic_ok = getfield_def(d, 'magic_ok', false);
        item.payload_crc_ok = getfield_def(d, 'payload_crc_ok', false);
        item.sync_peak = getfield_def(d, 'sync_peak', NaN);
        frames{k} = item;
    end

    payload = struct();
    payload.frame_idx = frame_idx;
    payload.text_out = text;
    payload.N_detected = info.N_detected;
    payload.N_expected = info.N_expected;
    payload.dispatch_counts = info.dispatch_counts;
    payload.frames = frames;

    fid = fopen(path, 'w');
    fprintf(fid, '%s\n', jsonencode(payload));
    fclose(fid);
catch ME
    warning('rx_stream_p4:jsonWriteFailed', ...
        'failed to write %s (%s)', path, ME.message);
end

end
