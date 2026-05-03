function out = amc_ctrl_codec(op, input, sys)
%AMC_CTRL_CODEC Compact CTRL payload codec for AMC ACK feedback.
%
% Usage:
%   text = amc_ctrl_codec('pack_ack', ack, sys)
%   ack  = amc_ctrl_codec('unpack_ack', text, sys)
%
% The on-air payload is UTF-8/ASCII JSON carried by a CTRL routed frame.
% Field names are intentionally compact so the ACK fits inside the robust
% FH-MFSK payload capacity used by CTRL.

if nargin < 3 || isempty(sys), sys = sys_params_default(); end

switch lower(op)
    case 'pack_ack'
        out = pack_ack(input, sys);
    case 'unpack_ack'
        out = unpack_ack(input, sys);
    otherwise
        error('amc_ctrl_codec: unknown op "%s"', op);
end

end

% -------------------------------------------------------------------------
function text = pack_ack(ack, sys)

if nargin < 1 || ~isstruct(ack) || ~isfield(ack, 'valid') || ~ack.valid
    error('amc_ctrl_codec: pack_ack requires a valid ACK struct');
end

payload = struct();
payload.v = 1;
payload.t = 'amc_ack';
payload.f = finite_or_nan(field_or(ack, 'frame_idx', NaN));
payload.s = field_or(ack, 'recommend_scheme_code', ...
    streaming_scheme_codec('code', field_or(ack, 'recommend_scheme', 'FH-MFSK'), sys));
payload.n = field_or(ack, 'recommend_scheme', streaming_scheme_codec('name', payload.s, sys));
payload.p = field_or(ack, 'recommend_profile', 'default');
payload.r = finite_or_nan(field_or(ack, 'recommend_throughput_ratio', 1.0));
payload.q = finite_or_nan(field_or(ack, 'link_quality_metric', NaN));
payload.sn = finite_or_nan(field_or(ack, 'snr_est_db', NaN));
payload.fd = finite_or_nan(field_or(ack, 'doppler_hz', NaN));
payload.sy = finite_or_nan(field_or(ack, 'sync_peak', NaN));
payload.be = finite_or_nan(field_or(ack, 'ber_est', NaN));
payload.fe = finite_or_nan(field_or(ack, 'fer_est', NaN));
payload.mp = compact_modem_params(field_or(ack, 'recommend_modem_params', struct()));

text = jsonencode(payload);
max_chars = floor(streaming_scheme_codec('payload_capacity_bits', 'CTRL', sys) / 8);
if length(text) > max_chars
    payload.mp = struct();
    text = jsonencode(payload);
end
assert(length(text) <= max_chars, ...
    'amc_ctrl_codec: packed ACK has %d chars, CTRL capacity is %d chars', ...
    length(text), max_chars);

end

% -------------------------------------------------------------------------
function ack = unpack_ack(text, sys)

if isstring(text), text = char(text); end
if ~(ischar(text) && ~isempty(strtrim(text)))
    error('amc_ctrl_codec: unpack_ack requires non-empty text');
end

payload = jsondecode(text);
if ~isstruct(payload) || ~isfield(payload, 't') || ~strcmp(payload.t, 'amc_ack')
    error('amc_ctrl_codec: CTRL payload is not an AMC ACK');
end

scheme_code = field_or(payload, 's', sys.frame.scheme_fhmfsk);
ack = struct();
ack.valid = true;
ack.scheme = 'CTRL';
ack.scheme_code = sys.frame.scheme_ctrl;
ack.frame_idx = field_or(payload, 'f', NaN);
ack.recommend_scheme_code = scheme_code;
ack.recommend_scheme = streaming_scheme_codec('name', scheme_code, sys);
ack.recommend_profile = field_or(payload, 'p', 'default');
ack.recommend_modem_params = expand_modem_params(field_or(payload, 'mp', struct()));
ack.recommend_throughput_ratio = field_or(payload, 'r', 1.0);
ack.link_quality_metric = field_or(payload, 'q', NaN);
ack.snr_est_db = field_or(payload, 'sn', NaN);
ack.doppler_hz = field_or(payload, 'fd', NaN);
ack.sync_peak = field_or(payload, 'sy', NaN);
ack.ber_est = field_or(payload, 'be', NaN);
ack.fer_est = field_or(payload, 'fe', NaN);

end

% -------------------------------------------------------------------------
function mp = compact_modem_params(params)

mp = struct();
if ~isstruct(params)
    return;
end
if isfield(params, 'scfde') && isstruct(params.scfde)
    s = params.scfde;
    mp.scfde = [field_or(s, 'blk_fft', NaN), ...
        field_or(s, 'blk_cp', NaN), ...
        field_or(s, 'N_blocks', NaN), ...
        field_or(s, 'turbo_iter', NaN), ...
        field_or(s, 'train_period_K', NaN), ...
        field_or(s, 'pilot_per_blk', NaN)];
end
if isfield(params, 'dsss') && isstruct(params.dsss)
    d = params.dsss;
    mp.dsss = [field_or(d, 'sps', NaN), ...
        field_or(d, 'rolloff', NaN), ...
        field_or(d, 'chip_rate', NaN), ...
        field_or(d, 'total_bw', NaN)];
end

end

% -------------------------------------------------------------------------
function params = expand_modem_params(mp)

params = struct();
if ~isstruct(mp)
    return;
end
if isfield(mp, 'scfde')
    vals = mp.scfde(:).';
    names = {'blk_fft', 'blk_cp', 'N_blocks', 'turbo_iter', ...
        'train_period_K', 'pilot_per_blk'};
    params.scfde = expand_numeric_fields(vals, names);
end
if isfield(mp, 'dsss')
    vals = mp.dsss(:).';
    names = {'sps', 'rolloff', 'chip_rate', 'total_bw'};
    params.dsss = expand_numeric_fields(vals, names);
end

end

% -------------------------------------------------------------------------
function s = expand_numeric_fields(vals, names)

s = struct();
for k = 1:min(numel(vals), numel(names))
    if isnumeric(vals(k)) && isfinite(vals(k))
        s.(names{k}) = vals(k);
    end
end

end

% -------------------------------------------------------------------------
function v = finite_or_nan(v)

if ~(isnumeric(v) && isscalar(v) && isfinite(v))
    v = NaN;
end

end

% -------------------------------------------------------------------------
function v = field_or(s, fname, default)

if isstruct(s) && isfield(s, fname) && ~isempty(s.(fname))
    v = s.(fname);
else
    v = default;
end

end
