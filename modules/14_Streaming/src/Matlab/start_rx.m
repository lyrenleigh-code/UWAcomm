function processed = start_rx(session, opts)
%START_RX Streaming P5 RX daemon entry point.

this_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(this_dir, 'common'));
streaming_addpaths();

if nargin < 1 || isempty(session)
    error('start_rx: session is required');
end
if nargin < 2 || ~isstruct(opts), opts = struct(); end

sys = sys_params_default();
sys = apply_payload_bits(sys, opts);
processed = rx_daemon_p5(session, sys, opts);

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
