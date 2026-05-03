function session = start_tx(session, text_or_file, schemes, opts)
%START_TX Streaming P5 TX entry point.
%
% Example:
%   start_tx('D:\path\session', 'hello', {'FH-MFSK'})

this_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(this_dir, 'common'));
paths = streaming_addpaths();

if nargin < 4 || ~isstruct(opts), opts = struct(); end
if nargin < 1 || isempty(session)
    session = create_session_dir(fullfile(paths.streaming_dir, 'sessions'));
else
    ensure_session_dirs(session);
end
if nargin < 2 || isempty(text_or_file)
    text_or_file = getfield_def(opts, 'text', 'P5 hello');
end
if nargin < 3 || isempty(schemes)
    schemes = getfield_def(opts, 'schemes', {'FH-MFSK'});
end

sys = sys_params_default();
sys = apply_payload_bits(sys, opts);
frame_idx0 = getfield_def(opts, 'frame_idx', next_raw_frame_idx(session));

write_pid(fullfile(session, 'tx.pid'), 'tx');

if isfield(opts, 'payloads')
    payload_sets = {normalize_cellstr(opts.payloads)};
    scheme_sets = {normalize_cellstr(schemes)};
else
    text = read_text_input(text_or_file);
    scheme_cells = normalize_cellstr(schemes);
    scheme_name = streaming_scheme_codec('name', scheme_cells{1}, sys);
    payload_capacity = streaming_scheme_codec('payload_capacity_bits', scheme_name, sys);
    chunks = text_chunker(text, floor(payload_capacity / 8));
    if isempty(chunks), chunks = {''}; end

    payload_sets = cell(1, length(chunks));
    scheme_sets = cell(1, length(chunks));
    for k = 1:length(chunks)
        payload_sets{k} = {chunks{k}};
        scheme_sets{k} = {scheme_name};
    end
end

for k = 1:length(payload_sets)
    frame_idx = frame_idx0 + k - 1;
    tx_opts = struct('frame_idx', frame_idx);
    if isfield(opts, 'modem_params')
        tx_opts.modem_params = opts.modem_params;
    elseif isfield(opts, 'profile_params')
        tx_opts.profile_params = opts.profile_params;
    end
    t0 = tic;
    tx_stream_p4(payload_sets{k}, scheme_sets{k}, session, sys, tx_opts);
    append_log(session, sprintf('[TX-P5] frame %04d wrote %d payload(s) in %.3fs', ...
        frame_idx, length(payload_sets{k}), toc(t0)));
end

fprintf('[TX-P5] wrote %d outer frame(s) to %s\n', length(payload_sets), session);

end

% -------------------------------------------------------------------------
function ensure_session_dirs(session)

dirs = {session, fullfile(session, 'raw_frames'), ...
    fullfile(session, 'channel_frames'), fullfile(session, 'rx_out')};
for k = 1:length(dirs)
    if ~exist(dirs{k}, 'dir'), mkdir(dirs{k}); end
end
log_path = fullfile(session, 'session.log');
if exist(log_path, 'file') ~= 2
    fid = fopen(log_path, 'w');
    fprintf(fid, '[%s] session opened: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), session);
    fclose(fid);
end

end

% -------------------------------------------------------------------------
function sys = apply_payload_bits(sys, opts)

payload_bits = getfield_def(opts, 'payload_bits', []);
if ~isempty(payload_bits)
    sys.frame.payload_bits = payload_bits;
    sys.frame.body_bits = sys.frame.header_bits + sys.frame.payload_bits + ...
        sys.frame.payload_crc_bits;
end

end

% -------------------------------------------------------------------------
function idx = next_raw_frame_idx(session)

raw_dir = fullfile(session, 'raw_frames');
files = [dir(fullfile(raw_dir, '*.ready')); dir(fullfile(raw_dir, '*.wav'))];
idx_vals = [];
for k = 1:length(files)
    [~, name] = fileparts(files(k).name);
    value = str2double(name);
    if ~isnan(value)
        idx_vals(end+1) = value; %#ok<AGROW>
    end
end
if isempty(idx_vals)
    idx = 1;
else
    idx = max(idx_vals) + 1;
end

end

% -------------------------------------------------------------------------
function text = read_text_input(text_or_file)

if isstring(text_or_file), text_or_file = char(text_or_file); end
if ischar(text_or_file) && exist(text_or_file, 'file') == 2
    text = fileread(text_or_file);
elseif ischar(text_or_file)
    text = text_or_file;
else
    text = char(text_or_file);
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
    error('start_tx: expected char, string, or cell array');
end
out = out(:).';
for k = 1:length(out)
    if isstring(out{k}), out{k} = char(out{k}); end
end

end

% -------------------------------------------------------------------------
function write_pid(path, role)

pid = NaN;
try
    pid = feature('getpid');
catch
end
fid = fopen(path, 'w');
fprintf(fid, '%s pid=%g role=%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS.FFF'), pid, role);
fclose(fid);

end

% -------------------------------------------------------------------------
function append_log(session, msg)

fid = fopen(fullfile(session, 'session.log'), 'a');
if fid > 0
    fprintf(fid, '[%s] %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), msg);
    fclose(fid);
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
