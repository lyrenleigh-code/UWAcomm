%% diag_jakes_v2_debug.m - 验证 V2.0 passband Jakes 输出 + HFM detect
clear functions; clear classes; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));

out_dir = fullfile(this_dir, 'rx_simple_ui_smoke_out');
files = dir(fullfile(out_dir, 'tx_SC-FDE_*.wav'));
[~, idx] = sort([files.datenum], 'descend');
wav_path = fullfile(out_dir, files(idx(1)).name);
[~, base, ~] = fileparts(wav_path);
json_path = fullfile(out_dir, [base '.json']);
fprintf('用 wav: %s\n', wav_path);

[audio_full, fs] = audioread(wav_path);
audio_full = audio_full(:, 1).';
fid = fopen(json_path, 'r'); js = fread(fid, '*char').'; fclose(fid);
meta = simple_ui_meta_io('decode', js);

% undo TX scale
audio_full = audio_full / meta.frame.scale_factor;

fprintf('原始 wav: power=%.3e peak=%.3e len=%d\n', mean(audio_full.^2), max(abs(audio_full)), length(audio_full));

% 实例化 RX UI 拿 jakes 函数（headless 模式构造）
r = rx_simple_ui('headless', true);
r.meta = meta;
r.channel_mode = 'jakes';

% 试 3 种 fd：0 / 1 / 5
fds = [0, 1, 5];
sys = sys_params_default();
fn = length(audio_full);

for k = 1:length(fds)
    r.channel_params.fading_fd_hz = fds(k);
    r.channel_params.snr_db = 30;   % 高 SNR 确保不是噪声问题
    r.channel_params.mp_seed = 4242;
    fprintf('\n--- fd=%g Hz ---\n', fds(k));
    audio_jakes = r.apply_jakes_full(audio_full);
    fprintf('jakes 输出: power=%.3e peak=%.3e len=%d\n', ...
        mean(audio_jakes.^2), max(abs(audio_jakes)), length(audio_jakes));

    % 直接 detect_frame_stream
    det = detect_frame_stream(audio_jakes, length(audio_jakes), 0, sys, ...
        struct('frame_len_hint', fn));
    fprintf('  detect: found=%d fs_pos=%d peak_ratio=%.2f conf=%.2f\n', ...
        det.found, det.fs_pos, det.peak_ratio, det.confidence);
end

% baseline: pass-through
fprintf('\n--- pass-through (no channel) ---\n');
det0 = detect_frame_stream(audio_full, fn, 0, sys, struct('frame_len_hint', fn));
fprintf('  detect: found=%d fs_pos=%d peak_ratio=%.2f conf=%.2f\n', ...
    det0.found, det0.fs_pos, det0.peak_ratio, det0.confidence);

% baseline: multipath only
fprintf('\n--- multipath baseline (no fading) ---\n');
r.channel_mode = 'multipath';
r.channel_params.snr_db = 30;
audio_mp = r.apply_multipath_full(audio_full);
fprintf('multipath 输出: power=%.3e peak=%.3e\n', mean(audio_mp.^2), max(abs(audio_mp)));
det_mp = detect_frame_stream(audio_mp, fn, 0, sys, struct('frame_len_hint', fn));
fprintf('  detect: found=%d fs_pos=%d peak_ratio=%.2f conf=%.2f\n', ...
    det_mp.found, det_mp.fs_pos, det_mp.peak_ratio, det_mp.confidence);
