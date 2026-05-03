%% test_p6_amc_decision.m - Streaming P6 AMC decision regression
% Acceptance:
%   1. Static / low Doppler / high Doppler converge within 10 frames.
%   2. Cooldown >= 3 frames prevents rapid switching.
%   3. Opt-in fixed-Doppler policy keeps compensated high-SNR offset on OFDM.
%   4. Fixed-Doppler successful OFDM frames tolerate tiny sync-margin dips.
%   5. Hysteresis uses 2 dB degrade / 5 dB improve margins.
%   6. Blind mode works without ACK.
%   7. Session updater writes AMC JSON and history.
%   8. Visualization helper writes a history plot.

clear functions; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));

streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(streaming_root);
addpath(fullfile(streaming_root, 'common'));
streaming_addpaths();

diary_path = fullfile(this_dir, 'test_p6_amc_decision_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('========================================\n');
fprintf(' Streaming P6 - AMC decision regression\n');
fprintf('========================================\n\n');
fprintf('Note: BER below is an AMC regression proxy from RX info / synthetic metrics,\n');
fprintf('      not a full physical-link BER benchmark.\n\n');

sys = sys_params_default();
opts = struct('cooldown_frames', 3, 'degrade_hysteresis_db', 2, ...
    'improve_hysteresis_db', 5, 'low_doppler_hz', 0.75, ...
    'high_doppler_hz', 3, 'large_delay_s', 1.0e-3);

pass_count = 0;
total_checks = 0;

% 1) Three canonical channel classes converge within 10 frames.
scenarios = { ...
    struct('name', 'static', 'expected', 'OFDM', ...
        'snr', 18, 'doppler', 0, 'delay', 0.3e-3, 'sync', 0.92), ...
    struct('name', 'low_doppler', 'expected', 'SC-FDE', ...
        'snr', 18, 'doppler', 1.0, 'delay', 0.8e-3, 'sync', 0.88), ...
    struct('name', 'high_doppler', 'expected', 'OTFS', ...
        'snr', 18, 'doppler', 5.0, 'delay', 0.8e-3, 'sync', 0.86)};

for sidx = 1:length(scenarios)
    s = scenarios{sidx};
    state = struct();
    selected = '';
    final_decision = struct();
    for k = 1:10
        q = make_q(k, s.snr, s.sync, s.delay, s.doppler);
        [decision, state] = mode_selector(q, state, sys, opts);
        selected = decision.selected_scheme;
        final_decision = decision;
    end
    total_checks = total_checks + 1;
    if strcmp(selected, s.expected)
        pass_count = pass_count + 1;
        fprintf('[PASS] %s converged to %s within 10 frames (BER_est=%.3g, FER_est=%.3g)\n', ...
            s.name, selected, final_decision.ber_est, final_decision.fer_est);
    else
        fprintf('[FAIL] %s selected %s, expected %s\n', ...
            s.name, selected, s.expected);
    end
end

% 2) Cooldown blocks immediate switching for frames 2 and 3; frame 4 can switch.
state = struct();
[d1, state] = mode_selector(make_q(1, 18, 0.92, 0.3e-3, 0), state, sys, opts);
[d2, state] = mode_selector(make_q(2, 15, 0.88, 0.8e-3, 1.0), state, sys, opts);
[d3, state] = mode_selector(make_q(3, 15, 0.88, 0.8e-3, 1.0), state, sys, opts);
[d4, state] = mode_selector(make_q(4, 15, 0.88, 0.8e-3, 1.0), state, sys, opts);
total_checks = total_checks + 1;
if strcmp(d1.selected_scheme, 'OFDM') && strcmp(d2.selected_scheme, 'OFDM') && ...
        strcmp(d3.selected_scheme, 'OFDM') && strcmp(d4.selected_scheme, 'SC-FDE')
    pass_count = pass_count + 1;
    fprintf('[PASS] cooldown held two frames and allowed switch on frame 4\n');
else
    fprintf('[FAIL] cooldown sequence: %s -> %s -> %s -> %s\n', ...
        d1.selected_scheme, d2.selected_scheme, d3.selected_scheme, d4.selected_scheme);
end

% 3) Opt-in fixed-Doppler policy keeps compensated high-SNR fixed offset on OFDM.
fixed_opts = opts;
fixed_opts.enable_fixed_doppler_policy = true;
fixed_opts.fixed_doppler_scheme = 'OFDM';
fixed_opts.fixed_doppler_min_snr_db = 10;
q_fixed = make_q(1, 18, 0.90, 0.8e-3, 5.0);
q_fixed.doppler_model = 'fixed_constant';
q_fixed.channel_model = 'fixed_gain_multipath';
q_fixed.time_varying_factor = 0;
q_jakes = make_q(1, 18, 0.90, 0.8e-3, 5.0);
q_jakes.doppler_model = 'jakes_fast';
q_jakes.channel_model = 'time_varying_jakes';
[d_fixed, ~] = mode_selector(q_fixed, struct(), sys, fixed_opts);
[d_jakes, ~] = mode_selector(q_jakes, struct(), sys, fixed_opts);
total_checks = total_checks + 1;
if strcmp(d_fixed.selected_scheme, 'OFDM') && strcmp(d_jakes.selected_scheme, 'OTFS')
    pass_count = pass_count + 1;
    fprintf('[PASS] fixed-Doppler opt-in selects OFDM while Jakes high-Doppler remains OTFS\n');
else
    fprintf('[FAIL] fixed-Doppler opt-in selected fixed=%s jakes=%s\n', ...
        d_fixed.selected_scheme, d_jakes.selected_scheme);
end

% 4) A successful fixed-Doppler OFDM frame should not downgrade just because
% the sync metric is a hair below the generic threshold.
state = struct('current_scheme', 'OFDM', 'frame_idx', 4, ...
    'last_switch_frame', 1, 'last_switch_quality_db', 16, 'history', {{}});
q_hold = make_q(5, 10.8, 0.34995, 0.8e-3, 5.0);
q_hold.doppler_model = 'fixed_constant';
q_hold.channel_model = 'fixed_gain_multipath';
q_hold.time_varying_factor = 0;
q_hold.ok_ratio = 1;
q_hold.ber_est = 3e-4;
q_hold.fer_est = 0;
q_fail = q_hold;
q_fail.ok_ratio = 0;
q_fail.ber_est = 0.1;
q_fail.fer_est = 1;
[d_hold_fixed, ~] = mode_selector(q_hold, state, sys, fixed_opts);
[d_fail_fixed, ~] = mode_selector(q_fail, state, sys, fixed_opts);
total_checks = total_checks + 1;
if strcmp(d_hold_fixed.selected_scheme, 'OFDM') && ...
        strcmp(d_hold_fixed.hold_reason, 'fixed_doppler_success_hold') && ...
        strcmp(d_fail_fixed.selected_scheme, 'FH-MFSK')
    pass_count = pass_count + 1;
    fprintf('[PASS] fixed-Doppler successful OFDM frame holds through slight sync dip\n');
else
    fprintf('[FAIL] fixed-Doppler success hold selected success=%s/%s failure=%s/%s\n', ...
        d_hold_fixed.selected_scheme, d_hold_fixed.hold_reason, ...
        d_fail_fixed.selected_scheme, d_fail_fixed.hold_reason);
end

% 5) Improve hysteresis requires 5 dB before upgrading to OFDM.
state = struct();
state.current_scheme = 'SC-FDE';
state.frame_idx = 10;
state.last_switch_frame = 6;
state.last_switch_quality_db = 10;
state.history = {};
[d_hold, state] = mode_selector(make_q(11, 14.9, 0.92, 0, 0), state, sys, opts);
[d_up, state] = mode_selector(make_q(12, 15.1, 0.92, 0, 0), state, sys, opts); %#ok<ASGLU>
total_checks = total_checks + 1;
if strcmp(d_hold.selected_scheme, 'SC-FDE') && strcmp(d_up.selected_scheme, 'OFDM')
    pass_count = pass_count + 1;
    fprintf('[PASS] improve hysteresis held at +4.9dB and switched at +5.1dB\n');
else
    fprintf('[FAIL] improve hysteresis sequence: %s -> %s\n', ...
        d_hold.selected_scheme, d_up.selected_scheme);
end

% 6) ACK application and blind fixed mode.
ack = d_up.ack;
[scheme_ack, ~] = amc_tx_next_scheme('SC-FDE', ack, struct());
[scheme_blind, ~] = amc_tx_next_scheme('SC-FDE', struct(), ...
    struct('blind_mode', true, 'fixed_scheme', 'FH-MFSK'));
total_checks = total_checks + 1;
if strcmp(scheme_ack, 'OFDM') && strcmp(scheme_blind, 'FH-MFSK')
    pass_count = pass_count + 1;
    fprintf('[PASS] TX applies ACK and blind mode falls back to fixed rule\n');
else
    fprintf('[FAIL] ACK/blind schemes: ack=%s blind=%s\n', scheme_ack, scheme_blind);
end

% 7) Session updater writes AMC JSON/history from rx/chinfo files.
session = create_session_dir(fullfile(proj_root, 'modules', '14_Streaming', 'sessions'));
info = synthetic_rx_info(1, 18, 0.91);
text_out = 'AMC';
frame_idx = 1; %#ok<NASGU>
save(fullfile(session, 'rx_out', '0001.meta.mat'), 'text_out', 'info', 'frame_idx');
ch_info = struct('delays_s', [0, 0.3e-3], 'doppler_rate', 0, ...
    'fading_fd_hz', 0, 'fs', sys.fs);
save(fullfile(session, 'channel_frames', '0001.chinfo.mat'), '-struct', 'ch_info');
[d_session, state_session, q_session] = amc_update_session(session, 1, sys, opts, struct()); %#ok<ASGLU>
json_path = fullfile(session, 'rx_out', '0001.amc.json');
hist_path = fullfile(session, 'amc_history.jsonl');
total_checks = total_checks + 1;
if exist(json_path, 'file') == 2 && exist(hist_path, 'file') == 2 && ...
        strcmp(d_session.selected_scheme, 'OFDM') && q_session.doppler_hz == 0
    pass_count = pass_count + 1;
    fprintf('[PASS] session AMC update wrote JSON/history and selected OFDM (BER_est=%.3g, FER_est=%.3g)\n', ...
        q_session.ber_est, q_session.fer_est);
else
    fprintf('[FAIL] session AMC update failed\n');
end

% 8) Visualization helper emits a plot.
viz_state = struct();
viz_frames = { ...
    make_q(1, 18, 0.92, 0.3e-3, 0), ...
    make_q(2, 18, 0.92, 0.3e-3, 0), ...
    make_q(3, 18, 0.92, 0.3e-3, 0), ...
    make_q(4, 18, 0.88, 0.8e-3, 1.0), ...
    make_q(5, 18, 0.88, 0.8e-3, 1.0), ...
    make_q(6, 18, 0.88, 0.8e-3, 1.0), ...
    make_q(7, 18, 0.86, 0.8e-3, 5.0), ...
    make_q(8, 18, 0.86, 0.8e-3, 5.0), ...
    make_q(9, 18, 0.86, 0.8e-3, 5.0), ...
    make_q(10, -2, 0.30, 1.3e-3, 0.2), ...
    make_q(11, -2, 0.30, 1.3e-3, 0.2), ...
    make_q(12, -2, 0.30, 1.3e-3, 0.2)};
for vk = 1:length(viz_frames)
    [~, viz_state] = mode_selector(viz_frames{vk}, viz_state, sys, opts);
end
plot_path = fullfile(session, 'p6_amc_history.png');
amc_plot_history(viz_state.history, plot_path, struct('visible', 'off'));
stable_plot_path = fullfile(this_dir, 'p6_amc_history.png');
if exist(stable_plot_path, 'file'), delete(stable_plot_path); end
copyfile(plot_path, stable_plot_path);
total_checks = total_checks + 1;
if exist(plot_path, 'file') == 2 && exist(stable_plot_path, 'file') == 2
    pass_count = pass_count + 1;
    fprintf('[PASS] AMC history plot written: %s\n', stable_plot_path);
else
    fprintf('[FAIL] AMC history plot missing\n');
end

fprintf('\nResult: %d/%d checks passed\n', pass_count, total_checks);
fprintf('Stable visualization: %s\n', stable_plot_path);
if pass_count == total_checks
    fprintf('[PASS] Streaming P6 AMC regression passed\n');
else
    error('test_p6_amc_decision: %d/%d checks failed', ...
        total_checks - pass_count, total_checks);
end

diary off;
fprintf('Log written: %s\n', diary_path);

% -------------------------------------------------------------------------
function q = make_q(frame_idx, snr_db, sync_peak, delay_s, doppler_hz)

q = struct();
q.frame_idx = frame_idx;
q.snr_est_db = snr_db;
q.sync_peak = sync_peak;
q.delay_spread_s = delay_s;
q.doppler_hz = doppler_hz;
q.quality_db = snr_db - max(doppler_hz - 1, 0) - 0.5 * delay_s * 1e3;
q.ber_est = min(0.5, 0.5 * exp(-max(snr_db, 0) / 3) + 0.005 * max(doppler_hz - 1, 0));
q.fer_est = min(1, q.ber_est * 10);
q.valid = true;

end

% -------------------------------------------------------------------------
function info = synthetic_rx_info(frame_idx, snr_db, sync_peak)

payload_info = struct('estimated_snr', snr_db, 'estimated_ber', 1e-4);
header_info = struct('estimated_snr', snr_db, 'estimated_ber', 1e-5);
decoded = {struct('idx', 1, 'text', 'AMC', 'ok', true, ...
    'scheme', 'FH-MFSK', 'hdr_crc_ok', true, 'magic_ok', true, ...
    'payload_crc_ok', true, 'sync_peak', sync_peak, ...
    'payload_info', payload_info, 'header_info', header_info)};
info = struct();
info.frame_idx = frame_idx;
info.decoded = {decoded};
info.N_detected = 1;
info.N_expected = 1;
info.peaks_info = struct('peak_max', 10, 'noise_floor', 1);
info.alpha = 0;

end
