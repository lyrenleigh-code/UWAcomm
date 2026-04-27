function tx_stream_p4(payloads, schemes, session, sys, opts)
%TX_STREAM_P4 Mixed-scheme Streaming P4 transmitter.
%
% Each physical frame uses FH-MFSK for the 16-byte header and routes the
% payload modem by header.scheme:
%   [HFM/LFM preamble | Header(FH-MFSK) | guard | Payload(scheme)]

if nargin < 5 || ~isstruct(opts), opts = struct(); end
frame_idx_outer = getfield_def(opts, 'frame_idx', 1);

payloads = normalize_cellstr(payloads);
schemes = normalize_cellstr(schemes);
if length(schemes) == 1 && length(payloads) > 1
    schemes = repmat(schemes, 1, length(payloads));
end
assert(length(payloads) == length(schemes), ...
    'tx_stream_p4: payloads and schemes must have the same length');

N_frames = length(payloads);
assert(N_frames >= 1, 'tx_stream_p4: no payloads');
assert(N_frames <= 255, 'tx_stream_p4: frame count %d exceeds header idx limit', N_frames);

raw_dir = fullfile(session, 'raw_frames');
if ~exist(raw_dir, 'dir'), mkdir(raw_dir); end

frame_cells = cell(1, N_frames);
frame_metas = cell(1, N_frames);
payload_records = cell(1, N_frames);
header_meta_ref = [];
header_samples = 0;

fprintf('[TX-P4] building %d mixed-scheme frames\n', N_frames);

for fi = 1:N_frames
    modem_params = modem_params_for_frame(opts, fi);
    sys_frame = streaming_apply_modem_params(sys, modem_params);
    scheme_name = streaming_scheme_codec('name', schemes{fi}, sys_frame);
    scheme_code = streaming_scheme_codec('code', scheme_name, sys_frame);
    payload_capacity = streaming_scheme_codec('payload_capacity_bits', scheme_name, sys_frame);
    payload_info_bits = payload_capacity + sys_frame.frame.payload_crc_bits;

    payload_raw = text_to_bits(payloads{fi});
    assert(length(payload_raw) <= payload_capacity, ...
        'tx_stream_p4: frame %d payload has %d bits, capacity for %s is %d bits', ...
        fi, length(payload_raw), scheme_name, payload_capacity);

    payload_crc = crc16(payload_raw);
    payload_pad = zeros(1, payload_capacity - length(payload_raw));
    payload_bits = [payload_raw, payload_pad, payload_crc];
    assert(length(payload_bits) == payload_info_bits);

    hdr_input = struct();
    hdr_input.scheme    = scheme_code;
    hdr_input.idx       = fi;
    hdr_input.len       = length(payload_raw);
    hdr_input.mod_level = 1;
    hdr_input.flags     = double(fi == N_frames);
    hdr_input.src       = 0;
    hdr_input.dst       = 0;
    hdr_bits = frame_header('pack', hdr_input, sys_frame);

    [header_bb, header_meta] = modem_encode(hdr_bits, 'FH-MFSK', sys_frame);
    [payload_bb, payload_meta] = modem_encode(payload_bits, scheme_name, sys_frame);
    [frame_bb, frame_meta] = assemble_routed_physical_frame(header_bb, payload_bb, sys_frame);
    [frame_pb, ~] = upconvert(frame_bb, sys_frame.fs, sys_frame.fc);

    if fi == 1
        header_meta_ref = header_meta;
        header_samples = length(header_bb);
    end

    frame_cells{fi} = frame_pb;
    frame_metas{fi} = frame_meta;
    payload_records{fi} = struct( ...
        'idx', fi, ...
        'scheme', scheme_name, ...
        'scheme_code', scheme_code, ...
        'text', payloads{fi}, ...
        'len_bits', length(payload_raw), ...
        'payload_capacity_bits', payload_capacity, ...
        'payload_info_bits', payload_info_bits, ...
        'payload_samples', length(payload_bb), ...
        'payload_meta', payload_meta, ...
        'modem_params', modem_params, ...
        'frame_samples', length(frame_pb));

    fprintf('[TX-P4] frame %d/%d scheme=%s text="%s" len=%d/%d bits samples=%d\n', ...
        fi, N_frames, scheme_name, payloads{fi}, length(payload_raw), ...
        payload_capacity, length(frame_pb));
end

multi_frame_pb = [frame_cells{:}];
wav_write_frame(multi_frame_pb, raw_dir, frame_idx_outer, sys);

meta_full = struct();
meta_full.N_frames = N_frames;
meta_full.frame_metas = {frame_metas};
meta_full.payload_records = {payload_records};
meta_full.schemes = schemes;
meta_full.payloads = payloads;
meta_full.modem_params = getfield_def(opts, 'modem_params', ...
    getfield_def(opts, 'profile_params', struct()));
meta_full.input_text = strjoin(payloads, '');
meta_full.frame_lengths = cellfun(@length, frame_cells);
meta_full.single_frame_samples = max(meta_full.frame_lengths);
meta_full.min_frame_samples = min(meta_full.frame_lengths);
meta_full.total_samples = length(multi_frame_pb);
meta_full.header_meta = header_meta_ref;
meta_full.header_samples = header_samples;

save(fullfile(raw_dir, sprintf('%04d.meta.mat', frame_idx_outer)), '-struct', 'meta_full');

fprintf('[TX-P4] wrote %d samples (%.2f s) to %s\n', ...
    length(multi_frame_pb), length(multi_frame_pb)/sys.fs, raw_dir);

end

% -------------------------------------------------------------------------
function modem_params = modem_params_for_frame(opts, idx)

modem_params = getfield_def(opts, 'modem_params', ...
    getfield_def(opts, 'profile_params', struct()));
if iscell(modem_params)
    if isempty(modem_params)
        modem_params = struct();
    elseif length(modem_params) == 1
        modem_params = modem_params{1};
    elseif idx <= length(modem_params)
        modem_params = modem_params{idx};
    else
        modem_params = struct();
    end
end
if ~isstruct(modem_params)
    modem_params = struct();
end

end

% -------------------------------------------------------------------------
function out = normalize_cellstr(in)

if ischar(in)
    out = {in};
elseif isstring(in)
    out = cellstr(in);
elseif iscell(in)
    out = in;
else
    error('tx_stream_p4: expected char, string, or cell array');
end

out = out(:).';
for k = 1:length(out)
    if isstring(out{k}), out{k} = char(out{k}); end
end

end

% -------------------------------------------------------------------------
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
end

end
