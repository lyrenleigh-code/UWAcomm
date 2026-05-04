%% diag_pass_vs_awgn80.m - 区分 pass 49% BER 是 noise 缺失还是 RX UI 路径 bug
clear functions; clear classes; clear all; clc;

this_dir = 'D:/Claude/TechReq/UWAcomm-claude/modules/14_Streaming/src/Matlab/tests';
streaming_root = fileparts(this_dir);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));

out_dir = fullfile(this_dir, 'rx_simple_ui_smoke_out');
% 找最新 wav
files = dir(fullfile(out_dir, 'tx_SC-FDE_*.wav'));
[~, idx] = sort([files.datenum], 'descend');
wav_path = fullfile(out_dir, files(idx(1)).name);
[~, base, ~] = fileparts(wav_path);
json_path = fullfile(out_dir, [base '.json']);
fprintf('用 wav: %s\n', wav_path);

fid = fopen(json_path, 'r');
json_str = fread(fid, '*char').';
fclose(fid);
meta = simple_ui_meta_io('decode', json_str);

% 测 3 个 SNR
snrs = [10, 30, 80];
for k = 1:length(snrs)
    r = rx_simple_ui('headless', true);
    r.wav_path = wav_path;
    r.json_path = json_path;
    r.meta = meta;
    r.channel_mode = 'awgn';
    r.channel_params.snr_db = snrs(k);
    r.chunk_ms = 50;
    r.on_run();
    fprintf('  SNR=%2d dB → BER = %.3f%%\n\n', snrs(k), r.last_result.mean_ber*100);
    delete(r); clear r;
end

% pass 模式
r = rx_simple_ui('headless', true);
r.wav_path = wav_path; r.json_path = json_path; r.meta = meta;
r.channel_mode = 'pass';
r.chunk_ms = 50;
r.on_run();
fprintf('  PASS (no noise) → BER = %.3f%%\n', r.last_result.mean_ber*100);
delete(r); clear r;
