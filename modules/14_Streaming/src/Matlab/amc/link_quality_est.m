function [q, details] = link_quality_est(rx_info, ch_info, sys, opts)
%LINK_QUALITY_EST Build physical-layer AMC metrics from RX/channel info.

if nargin < 1 || ~isstruct(rx_info), rx_info = struct(); end
if nargin < 2 || ~isstruct(ch_info), ch_info = struct(); end
if nargin < 3 || isempty(sys), sys = sys_params_default(); end
if nargin < 4 || ~isstruct(opts), opts = struct(); end

q = struct();
q.frame_idx = field_or(rx_info, 'frame_idx', NaN);
q.sync_peak = first_finite([field_or(rx_info, 'sync_peak', NaN), decoded_sync_peaks(rx_info)]);
q.snr_est_db = first_finite([field_or(rx_info, 'snr_est_db', NaN), ...
    field_or(rx_info, 'snr_db', NaN), field_or(rx_info, 'estimated_snr', NaN), ...
    decoded_snrs(rx_info), peak_snr(rx_info)]);
q.delay_spread_s = first_finite([field_or(rx_info, 'delay_spread_s', NaN), ...
    field_or(ch_info, 'delay_spread_s', NaN), channel_delay_spread(ch_info, sys)]);
q.doppler_hz = abs(first_finite([field_or(rx_info, 'doppler_hz', NaN), ...
    alpha_to_hz(field_or(rx_info, 'alpha', NaN), sys), ...
    channel_doppler_hz(ch_info, sys)]));
q.doppler_model = first_text({text_field_or(rx_info, 'doppler_model', ''), ...
    text_field_or(rx_info, 'fading_type', ''), ...
    text_field_or(ch_info, 'doppler_model', ''), ...
    text_field_or(ch_info, 'fading_type', ''), ...
    text_field_or(ch_info, 'model', '')});
q.channel_model = first_text({text_field_or(rx_info, 'channel_model', ''), ...
    text_field_or(ch_info, 'channel_model', ''), ...
    text_field_or(ch_info, 'preset', '')});
q.time_varying_factor = first_finite([field_or(rx_info, 'time_varying_factor', NaN), ...
    field_or(ch_info, 'time_varying_factor', NaN)]);
q.alpha_std = first_finite([field_or(rx_info, 'alpha_std', NaN), ...
    field_or(ch_info, 'alpha_std', NaN)]);

if isnan(q.sync_peak), q.sync_peak = 0; end
if isnan(q.snr_est_db), q.snr_est_db = 0; end
if isnan(q.delay_spread_s), q.delay_spread_s = 0; end
if isnan(q.doppler_hz), q.doppler_hz = 0; end
if isnan(q.time_varying_factor), q.time_varying_factor = NaN; end
if isnan(q.alpha_std), q.alpha_std = NaN; end

doppler_penalty = getfield_def(opts, 'doppler_penalty_db_per_hz', 1.0);
delay_penalty = getfield_def(opts, 'delay_penalty_db_per_ms', 0.5);
sync_penalty = getfield_def(opts, 'sync_penalty_db', 6);

sync_loss = max(0, 1 - min(max(q.sync_peak, 0), 1));
q.quality_db = q.snr_est_db ...
    - doppler_penalty * max(q.doppler_hz - 1, 0) ...
    - delay_penalty * (q.delay_spread_s * 1e3) ...
    - sync_penalty * sync_loss;

q.ok_ratio = decoded_ok_ratio(rx_info);
q.ber_est = first_finite([field_or(rx_info, 'ber_est', NaN), ...
    field_or(rx_info, 'estimated_ber', NaN), decoded_bers(rx_info)]);
if isnan(q.ber_est) && isfinite(q.ok_ratio)
    q.ber_est = 1 - q.ok_ratio;
end
if isfinite(q.ok_ratio)
    q.fer_est = 1 - q.ok_ratio;
else
    q.fer_est = NaN;
end
q.valid = isfinite(q.quality_db);
q.delay_spread_ms = q.delay_spread_s * 1e3;
q.snr_class = classify_snr(q.snr_est_db);
q.doppler_class = classify_doppler(q.doppler_hz);
q.delay_class = classify_delay(q.delay_spread_s);

details = struct();
details.source = 'rx_info+ch_info';
details.rx_has_decoded = isfield(rx_info, 'decoded');
details.ch_has_delays = isfield(ch_info, 'delays_s') || isfield(ch_info, 'delays_samp');

end

% -------------------------------------------------------------------------
function vals = decoded_sync_peaks(info)

vals = [];
decoded = decoded_records(info);
for k = 1:length(decoded)
    d = decoded{k};
    if isstruct(d) && isfield(d, 'sync_peak')
        vals(end+1) = d.sync_peak; %#ok<AGROW>
    end
end
vals = vals(isfinite(vals));
if ~isempty(vals), vals = max(vals); end

end

% -------------------------------------------------------------------------
function vals = decoded_snrs(info)

vals = [];
decoded = decoded_records(info);
for k = 1:length(decoded)
    d = decoded{k};
    if isstruct(d) && isfield(d, 'payload_info') && isstruct(d.payload_info) && ...
            isfield(d.payload_info, 'estimated_snr')
        vals(end+1) = d.payload_info.estimated_snr; %#ok<AGROW>
    end
    if isstruct(d) && isfield(d, 'header_info') && isstruct(d.header_info) && ...
            isfield(d.header_info, 'estimated_snr')
        vals(end+1) = d.header_info.estimated_snr; %#ok<AGROW>
    end
end
vals = vals(isfinite(vals));
if ~isempty(vals), vals = median(vals); end

end

% -------------------------------------------------------------------------
function vals = decoded_bers(info)

vals = [];
decoded = decoded_records(info);
for k = 1:length(decoded)
    d = decoded{k};
    if isstruct(d) && isfield(d, 'payload_info') && isstruct(d.payload_info) && ...
            isfield(d.payload_info, 'estimated_ber')
        vals(end+1) = d.payload_info.estimated_ber; %#ok<AGROW>
    end
    if isstruct(d) && isfield(d, 'header_info') && isstruct(d.header_info) && ...
            isfield(d.header_info, 'estimated_ber')
        vals(end+1) = d.header_info.estimated_ber; %#ok<AGROW>
    end
end
vals = vals(isfinite(vals));
if ~isempty(vals), vals = median(vals); end

end

% -------------------------------------------------------------------------
function decoded = decoded_records(info)

decoded = {};
if isfield(info, 'decoded')
    if iscell(info.decoded) && length(info.decoded) == 1 && iscell(info.decoded{1})
        decoded = info.decoded{1};
    elseif iscell(info.decoded)
        decoded = info.decoded;
    end
end

end

% -------------------------------------------------------------------------
function val = peak_snr(info)

val = NaN;
if isfield(info, 'peaks_info') && isstruct(info.peaks_info)
    p = info.peaks_info;
    if isfield(p, 'peak_max') && isfield(p, 'noise_floor') && p.noise_floor > 0
        val = 20 * log10(max(p.peak_max, eps) / max(p.noise_floor, eps));
    end
end

end

% -------------------------------------------------------------------------
function val = channel_delay_spread(ch_info, sys)

val = NaN;
if isfield(ch_info, 'delays_s')
    delays = ch_info.delays_s;
    val = max(delays) - min(delays);
elseif isfield(ch_info, 'delays_samp')
    val = (max(ch_info.delays_samp) - min(ch_info.delays_samp)) / sys.fs;
end

end

% -------------------------------------------------------------------------
function val = channel_doppler_hz(ch_info, sys)

val = NaN;
stretch_hz = NaN;
if isfield(ch_info, 'doppler_rate')
    stretch_hz = abs(ch_info.doppler_rate) * sys.fc;
end
fd_hz = field_or(ch_info, 'fading_fd_hz', NaN);
vals = [stretch_hz, fd_hz];
vals = vals(isfinite(vals));
if isempty(vals)
    val = NaN;
else
    val = max(vals);
end

end

% -------------------------------------------------------------------------
function val = alpha_to_hz(alpha, sys)

if isnan(alpha)
    val = NaN;
else
    val = abs(alpha) * sys.fc;
end

end

% -------------------------------------------------------------------------
function r = decoded_ok_ratio(info)

decoded = decoded_records(info);
if isempty(decoded)
    r = NaN;
    return;
end
ok_count = 0;
for k = 1:length(decoded)
    d = decoded{k};
    if isstruct(d) && isfield(d, 'ok') && d.ok
        ok_count = ok_count + 1;
    end
end
r = ok_count / length(decoded);

end

% -------------------------------------------------------------------------
function label = classify_snr(snr_db)

if snr_db < 0
    label = 'very_low';
elseif snr_db < 5
    label = 'low';
elseif snr_db < 12
    label = 'medium';
else
    label = 'high';
end

end

% -------------------------------------------------------------------------
function label = classify_doppler(doppler_hz)

if doppler_hz < 0.75
    label = 'static';
elseif doppler_hz < 3
    label = 'low';
else
    label = 'high';
end

end

% -------------------------------------------------------------------------
function label = classify_delay(delay_s)

if delay_s < 0.75e-3
    label = 'small';
elseif delay_s < 1.5e-3
    label = 'medium';
else
    label = 'large';
end

end

% -------------------------------------------------------------------------
function val = first_finite(vals)

val = NaN;
for k = 1:length(vals)
    if isfinite(vals(k))
        val = vals(k);
        return;
    end
end

end

% -------------------------------------------------------------------------
function txt = first_text(vals)

txt = '';
for k = 1:length(vals)
    v = vals{k};
    if isstring(v)
        if ~isempty(v), v = char(v(1)); else, v = ''; end
    end
    if ischar(v) && ~isempty(strtrim(v))
        txt = v;
        return;
    end
end

end

% -------------------------------------------------------------------------
function txt = text_field_or(s, fname, default)

txt = default;
if ~(isstruct(s) && isfield(s, fname))
    return;
end

v = s.(fname);
if isstring(v)
    if ~isempty(v), txt = char(v(1)); end
elseif ischar(v)
    txt = v;
elseif iscell(v) && ~isempty(v)
    first = v{1};
    if ischar(first)
        txt = first;
    elseif isstring(first) && ~isempty(first)
        txt = char(first(1));
    end
end

end

% -------------------------------------------------------------------------
function v = field_or(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
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
