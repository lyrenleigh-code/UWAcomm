%% test_p4_scheme_routing.m - Streaming P4 mixed-scheme routing regression
% Acceptance:
%   1. One channel wav contains six payload schemes.
%   2. RX dispatches to all six modem_decode paths.
%   3. Header OK + payload CRC fail records a miss instead of crashing.
%   4. Header failure does not stop later HFM frame search.

clear functions; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));

streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(streaming_root, 'channel'));

addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '12_IterativeProc', 'src', 'Matlab'));

diary_path = fullfile(this_dir, 'test_p4_scheme_routing_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('========================================\n');
fprintf(' Streaming P4 - mixed scheme routing\n');
fprintf('========================================\n\n');

sys = sys_params_default();
sys.frame.payload_bits = 96;
sys.frame.body_bits = sys.frame.header_bits + sys.frame.payload_bits + sys.frame.payload_crc_bits;
sys.scfde.fading_type = 'static';
sys.ofdm.fading_type = 'static';
sys.sctde.fading_type = 'static';
sys.dsss.fading_type = 'static';
sys.otfs.fading_type = 'static';

schemes = {'FH-MFSK', 'SC-FDE', 'OFDM', 'SC-TDE', 'DSSS', 'OTFS'};
payloads = {'FHMFSK', 'SCFDE', 'OFDM', 'SCTDE', 'DSSS', 'OTFS'};
expected_text = strjoin(payloads, '');

session_root = fullfile(proj_root, 'modules', '14_Streaming', 'sessions');
session = create_session_dir(session_root);

tx_stream_p4(payloads, schemes, session, sys);

ch_params = struct( ...
    'fs', sys.fs, ...
    'delays_s', [0, 0.167, 0.5, 0.833, 1.333] * 1e-3, ...
    'gains', [1, 0.5*exp(1j*0.5), 0.3*exp(1j*1.2), 0.2*exp(1j*2.0), 0.1*exp(1j*0.8)], ...
    'num_paths', 5, ...
    'doppler_rate', 0, ...
    'fading_type', 'static', ...
    'fading_fd_hz', 0, ...
    'snr_db', 30, ...
    'seed', 4242);
channel_simulator_p1(session, ch_params, sys);

[text_clean, info_clean] = rx_stream_p4(session, sys, struct('threshold_ratio', 0.05));

pass_count = 0;
total_checks = 0;

total_checks = total_checks + 1;
if strcmp(text_clean, expected_text)
    pass_count = pass_count + 1;
    fprintf('[PASS] clean mixed-scheme text recovered: %s\n', text_clean);
else
    fprintf('[FAIL] clean text mismatch: got "%s", expected "%s"\n', text_clean, expected_text);
end

total_checks = total_checks + 1;
if all_dispatch_once(info_clean.dispatch_counts, schemes)
    pass_count = pass_count + 1;
    fprintf('[PASS] dispatched once to all six schemes\n');
else
    fprintf('[FAIL] dispatch counts are not all one\n');
    disp(info_clean.dispatch_counts);
end

% Corrupt payload of frame 2 and header of frame 3, then re-run RX.
chan_dir = fullfile(session, 'channel_frames');
[rx_pb, ~] = wav_read_frame(chan_dir, 1);
meta_tx = load(fullfile(session, 'raw_frames', '0001.meta.mat'));
frame_metas = meta_tx.frame_metas{1};
frame_starts = [1, cumsum(meta_tx.frame_lengths(1:end-1)) + 1];

fm2 = frame_metas{2};
lo2 = frame_starts(2) + fm2.payload_start - 1;
hi2 = min(lo2 + round(0.65 * fm2.payload_samples) - 1, length(rx_pb));
rx_pb(lo2:hi2) = 0;

fm3 = frame_metas{3};
lo3 = frame_starts(3) + fm3.header_start - 1;
hi3 = min(lo3 + fm3.header_samples - 1, length(rx_pb));
rx_pb(lo3:hi3) = 0;

wav_write_frame(rx_pb, chan_dir, 1, sys);
[text_corrupt, info_corrupt] = rx_stream_p4(session, sys, struct('threshold_ratio', 0.05));

total_checks = total_checks + 1;
if ~isempty(strfind(text_corrupt, '[missing frame 2]'))
    pass_count = pass_count + 1;
    fprintf('[PASS] payload CRC failure recorded as missing frame 2\n');
else
    fprintf('[FAIL] payload CRC failure was not recorded: %s\n', text_corrupt);
end

total_checks = total_checks + 1;
if ~isempty(strfind(text_corrupt, '[missing frame 3]')) && ...
        ~isempty(strfind(text_corrupt, 'SCTDEDSSSOTFS'))
    pass_count = pass_count + 1;
    fprintf('[PASS] header failure skipped and later frames decoded\n');
else
    fprintf('[FAIL] header failure did not preserve later frames: %s\n', text_corrupt);
end

fprintf('\nResult: %d/%d checks passed\n', pass_count, total_checks);
if pass_count == total_checks
    fprintf('[PASS] Streaming P4 routing regression passed\n');
else
    error('test_p4_scheme_routing: %d/%d checks failed', total_checks - pass_count, total_checks);
end

diary off;
fprintf('Log written: %s\n', diary_path);

% -------------------------------------------------------------------------
function ok = all_dispatch_once(dispatch_counts, schemes)

ok = true;
for k = 1:length(schemes)
    field_name = matlab.lang.makeValidName(schemes{k});
    if ~isfield(dispatch_counts, field_name) || dispatch_counts.(field_name) ~= 1
        ok = false;
        return;
    end
end

end
