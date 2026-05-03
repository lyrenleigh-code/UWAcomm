function ack = amc_make_ack(decision, q, sys)
%AMC_MAKE_ACK Build a CTRL-frame payload model for AMC feedback.

if nargin < 3 || isempty(sys), sys = sys_params_default(); end

ack = struct();
ack.valid = true;
ack.scheme = 'CTRL';
ack.scheme_code = sys.frame.scheme_ctrl;
ack.frame_idx = field_or(decision, 'frame_idx', NaN);
ack.recommend_scheme = field_or(decision, 'selected_scheme', 'FH-MFSK');
ack.recommend_scheme_code = streaming_scheme_codec('code', ack.recommend_scheme, sys);
ack.recommend_profile = field_or(decision, 'selected_profile', 'default');
ack.recommend_modem_params = field_or(decision, 'profile_params', struct());
ack.recommend_throughput_ratio = field_or(decision, 'profile_throughput_ratio', 1.0);
ack.link_quality_metric = field_or(q, 'quality_db', NaN);
ack.snr_est_db = field_or(q, 'snr_est_db', NaN);
ack.doppler_hz = field_or(q, 'doppler_hz', NaN);
ack.delay_spread_s = field_or(q, 'delay_spread_s', NaN);
ack.sync_peak = field_or(q, 'sync_peak', NaN);
ack.ber_est = field_or(q, 'ber_est', NaN);
ack.fer_est = field_or(q, 'fer_est', NaN);

end

% -------------------------------------------------------------------------
function v = field_or(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
end

end
