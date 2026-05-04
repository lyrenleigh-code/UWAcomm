clear functions; clear classes; clear all; clc;
this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));

out_dir = fullfile(this_dir, 'rx_simple_ui_smoke_out');
files = dir(fullfile(out_dir, 'tx_SC-FDE_*.wav'));
[~, idx] = sort([files.datenum], 'descend');
wav_path = fullfile(out_dir, files(idx(1)).name);
[audio_full, fs] = audioread(wav_path);
audio_full = audio_full(:, 1).';
fprintf('原始 wav: power=%.3e peak=%.3e\n', mean(audio_full.^2), max(abs(audio_full)));

% 模拟 apply_jakes_full
addpath(fullfile(fileparts(streaming_root), '..', '..', '13_SourceCode', 'src', 'Matlab', 'common'));
addpath(fullfile(fileparts(streaming_root), '..', '..', '09_Waveform', 'src', 'Matlab'));

sys = sys_params_default();
[bb, ~] = downconvert(audio_full, sys.fs, sys.fc, sys.fs);
fprintf('downconvert 后: power=%.3e peak=%.3e (complex)\n', mean(abs(bb).^2), max(abs(bb)));

ch_params = struct('fs', sys.fs, 'num_paths', 5, ...
    'delay_profile', 'custom', ...
    'delays_s', [0, 0.167, 0.5, 0.833, 1.333] * 1e-3, ...
    'gains', [1, 0.5, 0.3, 0.2, 0.1], ...
    'doppler_rate', 0, 'fading_type', 'slow', 'fading_fd_hz', 1, ...
    'snr_db', Inf, 'seed', 12345);
[bb_ch, ~] = gen_uwa_channel(bb, ch_params);
fprintf('jakes 后:    power=%.3e peak=%.3e len=%d (vs orig %d)\n', ...
    mean(abs(bb_ch).^2), max(abs(bb_ch)), length(bb_ch), length(bb));

if length(bb_ch) > length(bb), bb_ch = bb_ch(1:length(bb));
elseif length(bb_ch) < length(bb), bb_ch = [bb_ch, zeros(1, length(bb)-length(bb_ch))]; end

[audio_out, ~] = upconvert(bb_ch, sys.fs, sys.fc);
audio_out = real(audio_out);
fprintf('upconvert 后: power=%.3e peak=%.3e\n', mean(audio_out.^2), max(abs(audio_out)));

% detect
[bb2, ~] = downconvert(audio_out, sys.fs, sys.fc, 8000);
fprintf('detect 用 bw=8000 downconvert: power=%.3e\n', mean(abs(bb2).^2));

% try detect on the audio_out
det = detect_frame_stream(audio_out, length(audio_out), 0, sys, struct('frame_len_hint', length(audio_full)));
fprintf('detect on jakes audio_out: found=%d fs_pos=%d peak_ratio=%.2f\n', ...
    det.found, det.fs_pos, det.peak_ratio);

% try detect on raw wav (no jakes) 对照
det0 = detect_frame_stream(audio_full, length(audio_full), 0, sys, struct('frame_len_hint', length(audio_full)));
fprintf('detect on raw wav (no jakes): found=%d fs_pos=%d peak_ratio=%.2f\n', ...
    det0.found, det0.fs_pos, det0.peak_ratio);
