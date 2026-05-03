function [decision, state] = mode_selector(q, state, sys, opts)
%MODE_SELECTOR AMC decision table with hysteresis and cooldown.

if nargin < 2 || ~isstruct(state), state = struct(); end
if nargin < 3 || isempty(sys), sys = sys_params_default(); end
if nargin < 4 || ~isstruct(opts), opts = struct(); end

state = init_state(state);
frame_idx = field_or(q, 'frame_idx', NaN);
if isnan(frame_idx)
    frame_idx = state.frame_idx + 1;
end

target = raw_target_scheme(q, opts);
current = state.current_scheme;
current_profile = state.current_profile;
cooldown_frames = getfield_def(opts, 'cooldown_frames', 3);
if ~isempty(current) && fixed_doppler_ofdm_target(q, target, opts) && ...
        scheme_rank(target) > scheme_rank(current)
    cooldown_frames = getfield_def(opts, ...
        'fixed_doppler_recovery_cooldown_frames', cooldown_frames);
end
changed = false;
hold_reason = '';

if isempty(current)
    selected = target;
    changed = true;
    hold_reason = 'initial';
elseif strcmp(current, target)
    selected = current;
    hold_reason = 'already_selected';
elseif frame_idx - state.last_switch_frame < cooldown_frames
    selected = current;
    hold_reason = 'cooldown';
else
    current_rank = scheme_rank(current);
    target_rank = scheme_rank(target);
    quality_now = field_or(q, 'quality_db', field_or(q, 'snr_est_db', 0));
    quality_ref = state.last_switch_quality_db;
    if ~isfinite(quality_ref)
        quality_ref = quality_now;
    end

    if fixed_doppler_ofdm_target(q, target, opts) && ...
            getfield_def(opts, 'fixed_doppler_bypass_improve_hysteresis', true)
        selected = target;
        changed = true;
        hold_reason = 'fixed_doppler_policy';
    elseif target_rank < current_rank
        if fixed_doppler_success_hold(q, current, opts)
            selected = current;
            hold_reason = 'fixed_doppler_success_hold';
        elseif quality_now <= quality_ref - getfield_def(opts, 'degrade_hysteresis_db', 2) || ...
                hard_robust_event(q, opts)
            selected = target;
            changed = true;
            hold_reason = 'degrade_hysteresis';
        else
            selected = current;
            hold_reason = 'degrade_hysteresis_hold';
        end
    else
        improve_margin = getfield_def(opts, 'improve_hysteresis_db', 5);
        improve_reason = 'improve_hysteresis';
        if isfield(opts, 'recovery_hysteresis_db') && ...
                ~isempty(opts.recovery_hysteresis_db) && ...
                static_recovery_event(q, current, target, opts)
            improve_margin = opts.recovery_hysteresis_db;
            improve_reason = 'recovery_hysteresis';
        end

        if quality_now >= quality_ref + improve_margin
            selected = target;
            changed = true;
            hold_reason = improve_reason;
        else
            selected = current;
            hold_reason = [improve_reason, '_hold'];
        end
    end
end

decision = struct();
decision.frame_idx = frame_idx;
decision.selected_scheme = selected;
decision.target_scheme = target;
decision.previous_scheme = current;
decision.changed = changed;
decision.hold_reason = hold_reason;
selected_profile = select_profile(selected, q, sys, opts);
target_profile = select_profile(target, q, sys, opts);
decision.selected_profile = selected_profile.id;
decision.target_profile = target_profile.id;
decision.profile_params = selected_profile.params;
decision.profile_reason = selected_profile.reason;
decision.profile_throughput_ratio = selected_profile.throughput_ratio;
decision.profile_changed = ~strcmp(current_profile, selected_profile.id);
decision.quality_db = field_or(q, 'quality_db', NaN);
decision.snr_est_db = field_or(q, 'snr_est_db', NaN);
decision.doppler_hz = field_or(q, 'doppler_hz', NaN);
decision.delay_spread_s = field_or(q, 'delay_spread_s', NaN);
decision.sync_peak = field_or(q, 'sync_peak', NaN);
decision.doppler_model = text_field_or(q, 'doppler_model', '');
decision.channel_model = text_field_or(q, 'channel_model', '');
decision.ok_ratio = field_or(q, 'ok_ratio', NaN);
decision.ber_est = field_or(q, 'ber_est', NaN);
decision.fer_est = field_or(q, 'fer_est', NaN);
decision.ack = amc_make_ack(decision, q, sys);

state.frame_idx = frame_idx;
if changed
    state.current_scheme = selected;
    state.last_switch_frame = frame_idx;
    state.last_switch_quality_db = decision.quality_db;
end
state.current_profile = decision.selected_profile;
state.current_profile_params = decision.profile_params;
state.last_decision = decision;
state.history{end+1} = decision;

end

% -------------------------------------------------------------------------
function state = init_state(state)

if ~isfield(state, 'current_scheme'), state.current_scheme = ''; end
if ~isfield(state, 'current_profile'), state.current_profile = ''; end
if ~isfield(state, 'current_profile_params'), state.current_profile_params = struct(); end
if ~isfield(state, 'frame_idx'), state.frame_idx = 0; end
if ~isfield(state, 'last_switch_frame'), state.last_switch_frame = -Inf; end
if ~isfield(state, 'last_switch_quality_db'), state.last_switch_quality_db = -Inf; end
if ~isfield(state, 'history') || ~iscell(state.history), state.history = {}; end

end

% -------------------------------------------------------------------------
function profile = select_profile(scheme, q, sys, opts)

profile = struct();
profile.id = 'default';
profile.params = struct();
profile.reason = 'profile_aware_disabled';
profile.throughput_ratio = 1.0;

if ~getfield_def(opts, 'enable_profile_aware', false)
    return;
end

scheme_norm = normalize_scheme(scheme);
if strcmp(scheme_norm, 'SCFDE')
    if use_scfde_block_pilot(q, opts)
        blk_fft = getfield_def(opts, 'scfde_profile_blk_fft', 256);
        blk_cp = getfield_def(opts, 'scfde_profile_blk_cp', 128);
        n_blocks = getfield_def(opts, 'scfde_profile_n_blocks', 16);
        turbo_iter = getfield_def(opts, 'scfde_profile_turbo_iter', sys.scfde.turbo_iter);
        pilot_per_blk = getfield_def(opts, 'scfde_profile_pilot_per_blk', 128);
        pilot_per_blk = max(0, min(pilot_per_blk, blk_fft - 1));
        profile.id = sprintf('SC-FDE-pilot%d', pilot_per_blk);
        profile.params = struct('scfde', struct('blk_fft', blk_fft, ...
            'blk_cp', blk_cp, 'N_blocks', n_blocks, ...
            'turbo_iter', turbo_iter, 'train_period_K', n_blocks - 1, ...
            'pilot_per_blk', pilot_per_blk));
        profile.reason = 'low_mid_doppler_block_pilot';
        profile.throughput_ratio = (blk_fft - pilot_per_blk) / blk_fft;
    else
        profile.id = 'SC-FDE-legacy';
        profile.reason = 'scfde_legacy_profile';
    end
elseif strcmp(scheme_norm, 'DSSS') && ...
        getfield_def(opts, 'enable_dsss_fast_profile', false)
    dsss_sps = max(2, round(getfield_def(opts, 'dsss_profile_sps', 3)));
    dsss_rolloff = getfield_def(opts, 'dsss_profile_rolloff', sys.dsss.rolloff);
    dsss_chip_rate = sys.fs / dsss_sps;
    dsss_total_bw = dsss_chip_rate * (1 + dsss_rolloff);
    profile.id = sprintf('DSSS-sps%d', dsss_sps);
    profile.params = struct('dsss', struct('sps', dsss_sps, ...
        'rolloff', dsss_rolloff, ...
        'chip_rate', dsss_chip_rate, ...
        'total_bw', dsss_total_bw));
    profile.reason = 'dsss_fast_profile';
    profile.throughput_ratio = sys.dsss.sps / dsss_sps;
else
    profile.id = [scheme, '-default'];
    profile.reason = 'scheme_default_profile';
end

end

% -------------------------------------------------------------------------
function tf = use_scfde_block_pilot(q, opts)

doppler_hz = abs(field_or(q, 'doppler_hz', 0));
snr_db = field_or(q, 'snr_est_db', -Inf);
min_fd = getfield_def(opts, 'scfde_profile_min_fd_hz', ...
    getfield_def(opts, 'low_doppler_hz', 0.75));
max_fd = getfield_def(opts, 'scfde_profile_max_fd_hz', ...
    getfield_def(opts, 'high_doppler_hz', 3));
min_snr = getfield_def(opts, 'scfde_profile_min_snr_db', 15);

tf = doppler_hz >= min_fd && doppler_hz < max_fd && snr_db >= min_snr;

end

% -------------------------------------------------------------------------
function name = normalize_scheme(scheme)

name = upper(strrep(strrep(strtrim(scheme), '-', ''), '_', ''));

end

% -------------------------------------------------------------------------
function scheme = raw_target_scheme(q, opts)

sync_min = getfield_def(opts, 'sync_min', 0.35);
snr_low = getfield_def(opts, 'snr_low_db', 0);
snr_mid = getfield_def(opts, 'snr_mid_db', 5);
low_doppler = getfield_def(opts, 'low_doppler_hz', 0.75);
high_doppler = getfield_def(opts, 'high_doppler_hz', 3);
large_delay = getfield_def(opts, 'large_delay_s', 1.0e-3);
sync_fail_scheme = getfield_def(opts, 'sync_fail_scheme', 'FH-MFSK');
very_low_snr_scheme = getfield_def(opts, 'very_low_snr_scheme', 'FH-MFSK');
low_doppler_scheme = getfield_def(opts, 'low_doppler_scheme', 'SC-FDE');
high_doppler_scheme = getfield_def(opts, 'high_doppler_scheme', 'OTFS');
large_delay_scheme = getfield_def(opts, 'large_delay_scheme', 'SC-FDE');
fixed_doppler_scheme = getfield_def(opts, 'fixed_doppler_scheme', 'OFDM');
fixed_doppler_include_static = getfield_def(opts, ...
    'fixed_doppler_include_static', false);

sync_peak = field_or(q, 'sync_peak', 0);
snr_db = field_or(q, 'snr_est_db', 0);
doppler_hz = abs(field_or(q, 'doppler_hz', 0));
delay_s = field_or(q, 'delay_spread_s', 0);

if sync_peak < sync_min
    scheme = low_or_default(sync_fail_scheme, 'FH-MFSK');
elseif snr_db < snr_low
    scheme = low_or_default(very_low_snr_scheme, 'FH-MFSK');
elseif snr_db < snr_mid
    scheme = 'DSSS';
elseif fixed_doppler_event(q, opts) && ...
        (doppler_hz >= low_doppler || fixed_doppler_include_static)
    scheme = low_or_default(fixed_doppler_scheme, 'OFDM');
elseif doppler_hz >= high_doppler
    scheme = low_or_default(high_doppler_scheme, 'OTFS');
elseif doppler_hz >= low_doppler
    scheme = low_or_default(low_doppler_scheme, 'SC-FDE');
elseif delay_s >= large_delay
    scheme = low_or_default(large_delay_scheme, 'SC-FDE');
else
    scheme = 'OFDM';
end

end

% -------------------------------------------------------------------------
function tf = fixed_doppler_ofdm_target(q, target, opts)

tf = fixed_doppler_event(q, opts) && strcmp(normalize_scheme(target), 'OFDM');

end

% -------------------------------------------------------------------------
function tf = fixed_doppler_event(q, opts)

tf = false;
if ~getfield_def(opts, 'enable_fixed_doppler_policy', false)
    return;
end

snr_db = field_or(q, 'snr_est_db', -Inf);
min_snr = getfield_def(opts, 'fixed_doppler_min_snr_db', ...
    getfield_def(opts, 'snr_mid_db', 5));
if snr_db < min_snr
    return;
end

model_text = lower(strtrim([ ...
    text_field_or(q, 'doppler_model', ''), ' ', ...
    text_field_or(q, 'channel_model', ''), ' ', ...
    text_field_or(q, 'fading_type', ''), ' ', ...
    text_field_or(q, 'fading_model', '')]));

has_fixed_label = contains(model_text, 'fixed') || ...
    contains(model_text, 'constant') || ...
    contains(model_text, 'static');

has_zero_variation = false;
if isstruct(q) && isfield(q, 'time_varying_factor') && ...
        isnumeric(q.time_varying_factor) && isfinite(q.time_varying_factor)
    has_zero_variation = abs(q.time_varying_factor) < ...
        getfield_def(opts, 'fixed_doppler_timevary_tol', 1e-12);
elseif isstruct(q) && isfield(q, 'alpha_std') && ...
        isnumeric(q.alpha_std) && isfinite(q.alpha_std)
    has_zero_variation = abs(q.alpha_std) < ...
        getfield_def(opts, 'fixed_doppler_alpha_std_tol', 1e-10);
end

tf = has_fixed_label || has_zero_variation;

end

% -------------------------------------------------------------------------
function tf = fixed_doppler_success_hold(q, current, opts)

tf = false;
if ~getfield_def(opts, 'fixed_doppler_hold_on_success', true)
    return;
end
if ~fixed_doppler_event(q, opts) || ~strcmp(normalize_scheme(current), 'OFDM')
    return;
end

sync_min = getfield_def(opts, 'sync_min', 0.35);
sync_floor = getfield_def(opts, 'fixed_doppler_success_sync_floor', ...
    max(0, sync_min - getfield_def(opts, 'fixed_doppler_success_sync_margin', 0.08)));
sync_peak = field_or(q, 'sync_peak', NaN);
if isempty(sync_peak) || ~isnumeric(sync_peak) || ~isscalar(sync_peak) || ...
        ~isfinite(sync_peak) || sync_peak < sync_floor
    return;
end

ok_ratio = field_or(q, 'ok_ratio', NaN);
ber_est = field_or(q, 'ber_est', NaN);
fer_est = field_or(q, 'fer_est', NaN);
min_ok_ratio = getfield_def(opts, 'fixed_doppler_success_min_ok_ratio', 0.99);
max_ber = getfield_def(opts, 'fixed_doppler_success_max_ber', 1e-3);
max_fer = getfield_def(opts, 'fixed_doppler_success_max_fer', 0.05);

ok_by_crc = isfinite(ok_ratio) && ok_ratio >= min_ok_ratio;
ok_by_quality = isfinite(ber_est) && ber_est <= max_ber && ...
    (~isfinite(fer_est) || fer_est <= max_fer);
tf = ok_by_crc || ok_by_quality;

end

% -------------------------------------------------------------------------
function scheme = low_or_default(value, default)

if isstring(value), value = char(value); end
if ischar(value) && ~isempty(strtrim(value))
    scheme = value;
else
    scheme = default;
end

end

% -------------------------------------------------------------------------
function tf = hard_robust_event(q, opts)

tf = field_or(q, 'sync_peak', 1) < getfield_def(opts, 'sync_min', 0.35) || ...
    field_or(q, 'snr_est_db', 0) < getfield_def(opts, 'snr_low_db', 0) || ...
    abs(field_or(q, 'doppler_hz', 0)) >= getfield_def(opts, 'high_doppler_hz', 3);

end

% -------------------------------------------------------------------------
function tf = static_recovery_event(q, current, target, opts)

if scheme_rank(target) <= scheme_rank(current) || ~strcmp(normalize_scheme(target), 'OFDM')
    tf = false;
    return;
end

snr_db = field_or(q, 'snr_est_db', -Inf);
sync_peak = field_or(q, 'sync_peak', 0);
doppler_hz = abs(field_or(q, 'doppler_hz', 0));
delay_s = field_or(q, 'delay_spread_s', 0);

min_snr = getfield_def(opts, 'recovery_min_snr_db', 15);
sync_min = getfield_def(opts, 'recovery_sync_min', ...
    getfield_def(opts, 'sync_min', 0.35));
max_doppler = getfield_def(opts, 'recovery_max_doppler_hz', ...
    getfield_def(opts, 'low_doppler_hz', 0.75));
max_delay = getfield_def(opts, 'recovery_max_delay_s', ...
    getfield_def(opts, 'large_delay_s', 1.0e-3));

tf = snr_db >= min_snr && sync_peak >= sync_min && ...
    doppler_hz < max_doppler && delay_s < max_delay;

end

% -------------------------------------------------------------------------
function r = scheme_rank(scheme)

name = upper(strrep(strrep(strtrim(scheme), '-', ''), '_', ''));
switch name
    case 'FHMFSK'
        r = 1;
    case 'DSSS'
        r = 2;
    case 'OTFS'
        r = 3;
    case 'SCFDE'
        r = 4;
    case 'OFDM'
        r = 5;
    case 'SCTDE'
        r = 4;
    otherwise
        r = 1;
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
function v = getfield_def(s, fname, default)

if isstruct(s) && isfield(s, fname)
    v = s.(fname);
else
    v = default;
end

end
