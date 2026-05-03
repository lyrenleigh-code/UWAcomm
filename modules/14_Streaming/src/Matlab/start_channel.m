function processed = start_channel(session, preset, opts)
%START_CHANNEL Streaming P5 Channel daemon entry point.

this_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(this_dir, 'common'));
streaming_addpaths();

if nargin < 1 || isempty(session)
    error('start_channel: session is required');
end
if nargin < 2 || isempty(preset), preset = 'static'; end
if nargin < 3 || ~isstruct(opts), opts = struct(); end

sys = sys_params_default();
sys = apply_payload_bits(sys, opts);
if isfield(opts, 'ch_params')
    ch_params = opts.ch_params;
else
    ch_params = p5_channel_preset(preset, sys, opts);
end

processed = channel_daemon_p5(session, ch_params, sys, opts);

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
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
end

end
