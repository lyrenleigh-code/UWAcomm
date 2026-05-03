%% test_p5_three_process_smoke.m - Streaming P5 file-handshake daemon smoke
% Acceptance smoke:
%   1. start_tx/start_channel/start_rx entry points are callable.
%   2. TX -> Channel -> RX produces per-frame JSON and ready files.
%   3. Channel can keep processing while RX is offline, then RX reconnects.
%   4. static/low_doppler/high_doppler presets are selectable.

clear functions; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));

streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(streaming_root);
addpath(fullfile(streaming_root, 'common'));
streaming_addpaths();

diary_path = fullfile(this_dir, 'test_p5_three_process_smoke_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('========================================\n');
fprintf(' Streaming P5 - daemon handoff smoke\n');
fprintf('========================================\n\n');

pass_count = 0;
total_checks = 0;

sys = sys_params_default();
sys.frame.payload_bits = 32;
sys.frame.body_bits = sys.frame.header_bits + sys.frame.payload_bits + ...
    sys.frame.payload_crc_bits;

session_root = fullfile(proj_root, 'modules', '14_Streaming', 'sessions');
session = create_session_dir(session_root);
fprintf('Session: %s\n', session);

entry_files = {'start_tx.m', 'start_channel.m', 'start_rx.m'};
total_checks = total_checks + 1;
if all_files_exist(streaming_root, entry_files)
    pass_count = pass_count + 1;
    fprintf('[PASS] P5 entry files exist\n');
else
    fprintf('[FAIL] missing one or more P5 entry files\n');
end

opts_base = struct('payload_bits', 32, 'poll_sec', 0.05, ...
    'max_idle_sec', 1, 'max_frames', 1);

t0 = tic;
start_tx(session, 'P5A', {'FH-MFSK'}, setfield(opts_base, 'frame_idx', 1)); %#ok<SFLD>
start_channel(session, 'static', opts_base);
rx_opts = opts_base;
rx_opts.rx_opts = struct('threshold_ratio', 0.05, 'use_oracle_alpha', true);
start_rx(session, rx_opts);
latency_s = toc(t0);

[ok1, text1] = read_rx_text(session, 1);
total_checks = total_checks + 1;
if ok1 && strcmp(text1, 'P5A')
    pass_count = pass_count + 1;
    fprintf('[PASS] frame 1 decoded through TX/Channel/RX: %s (%.2fs)\n', ...
        text1, latency_s);
else
    fprintf('[FAIL] frame 1 decode mismatch: "%s"\n', text1);
end

total_checks = total_checks + 1;
if latency_s < 10
    pass_count = pass_count + 1;
    fprintf('[PASS] frame 1 sequential daemon latency %.2fs < 10s\n', latency_s);
else
    fprintf('[FAIL] frame 1 latency %.2fs >= 10s\n', latency_s);
end

% Simulate RX being offline: TX and Channel process frame 2 first, RX runs later.
start_tx(session, 'P5B', {'FH-MFSK'}, setfield(opts_base, 'frame_idx', 2)); %#ok<SFLD>
start_channel(session, 'static', opts_base);

total_checks = total_checks + 1;
if exist(fullfile(session, 'channel_frames', '0002.ready'), 'file') == 2 && ...
        exist(fullfile(session, 'rx_out', '0002.ready'), 'file') ~= 2
    pass_count = pass_count + 1;
    fprintf('[PASS] channel produced frame 2 while RX was offline\n');
else
    fprintf('[FAIL] offline RX handoff state is not as expected\n');
end

start_rx(session, rx_opts);
[ok2, text2] = read_rx_text(session, 2);
total_checks = total_checks + 1;
if ok2 && strcmp(text2, 'P5B')
    pass_count = pass_count + 1;
    fprintf('[PASS] RX reconnect decoded queued frame 2: %s\n', text2);
else
    fprintf('[FAIL] frame 2 reconnect decode mismatch: "%s"\n', text2);
end

ch_static = p5_channel_preset('static', sys);
ch_low = p5_channel_preset('low_doppler', sys);
ch_high = p5_channel_preset('high_doppler', sys);

total_checks = total_checks + 1;
if ch_static.doppler_rate == 0 && ch_low.doppler_rate > 0 && ...
        ch_high.doppler_rate > ch_low.doppler_rate
    pass_count = pass_count + 1;
    fprintf('[PASS] channel presets selectable: static/low/high Doppler\n');
else
    fprintf('[FAIL] channel presets are not ordered as expected\n');
end

fprintf('\nResult: %d/%d checks passed\n', pass_count, total_checks);
if pass_count == total_checks
    fprintf('[PASS] Streaming P5 daemon smoke passed\n');
else
    error('test_p5_three_process_smoke: %d/%d checks failed', ...
        total_checks - pass_count, total_checks);
end

diary off;
fprintf('Log written: %s\n', diary_path);

% -------------------------------------------------------------------------
function ok = all_files_exist(root_dir, names)

ok = true;
for k = 1:length(names)
    if exist(fullfile(root_dir, names{k}), 'file') ~= 2
        ok = false;
        return;
    end
end

end

% -------------------------------------------------------------------------
function [ok, text_out] = read_rx_text(session, frame_idx)

ok = false;
text_out = '';
json_path = fullfile(session, 'rx_out', sprintf('%04d.meta.json', frame_idx));
mat_path = fullfile(session, 'rx_out', sprintf('%04d.meta.mat', frame_idx));

if exist(json_path, 'file') == 2
    payload = jsondecode(fileread(json_path));
    text_out = payload.text_out;
    ok = true;
elseif exist(mat_path, 'file') == 2
    payload = load(mat_path);
    text_out = payload.text_out;
    ok = true;
end

end
