%% diag_scfde_high_snr_fix.m - 验证 V4.1 高 SNR clamp + pre-Turbo BEM disable fix
% Spec: specs/active/2026-05-04-scfde-high-snr-cascade-bem-disaster.md
clear functions; clear classes; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));

diary_path = fullfile(this_dir, 'diag_scfde_high_snr_fix_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('========================================\n');
fprintf(' SC-FDE V4.1 高 SNR 修复验证\n');
fprintf(' Spec: 2026-05-04-scfde-high-snr-cascade-bem-disaster.md\n');
fprintf('========================================\n\n');

out_dir = fullfile(this_dir, 'scfde_high_snr_fix_out');
if exist(out_dir, 'dir'), rmdir(out_dir, 's'); end
mkdir(out_dir);

% 生成 SC-FDE V4.0 wav
fprintf('Step 1: 生成 SC-FDE V4.0 wav...\n');
t = tx_simple_ui('headless', true);
t.scheme = 'SC-FDE';
t.output_dir = out_dir;
t.on_generate();
wav = t.last_wav_path; json = t.last_json_path;
delete(t); clear t;

fid = fopen(json, 'r'); js = fread(fid, '*char').'; fclose(fid);
meta = simple_ui_meta_io('decode', js);

% SNR sweep
snrs = [10, 15, 20, 25, 30, 40, 60, 80];
fprintf('\nStep 2: SC-FDE awgn 模式 SNR sweep\n\n');
fprintf('| SNR (dB) | BER (%%)  | 备注 |\n');
fprintf('|----------|----------|------|\n');
ber_awgn = zeros(1, length(snrs));
for k = 1:length(snrs)
    r = rx_simple_ui('headless', true);
    r.wav_path = wav; r.json_path = json; r.meta = meta;
    r.channel_mode = 'awgn'; r.channel_params.snr_db = snrs(k);
    r.chunk_ms = 50;
    r.on_run();
    ber_awgn(k) = r.last_result.mean_ber * 100;
    fprintf('|   %2d     | %7.3f  |      |\n', snrs(k), ber_awgn(k));
    delete(r); clear r;
end

% pass mode
fprintf('\nStep 3: SC-FDE pass 模式（无信道，等价 SNR ≈ ∞）\n');
r = rx_simple_ui('headless', true);
r.wav_path = wav; r.json_path = json; r.meta = meta;
r.channel_mode = 'pass'; r.chunk_ms = 50;
r.on_run();
ber_pass = r.last_result.mean_ber * 100;
fprintf('| pass     | %7.3f  | (≈80dB) |\n', ber_pass);
delete(r); clear r;

% 单调性检查
fprintf('\nStep 4: 单调性检查\n');
non_monotonic = false;
for k = 2:length(snrs)
    if ber_awgn(k) > ber_awgn(k-1) + 1.0   % 允许 1pp 噪声
        non_monotonic = true;
        fprintf('  非单调点：SNR %d→%d dB, BER %.3f→%.3f%% (Δ=+%.3fpp)\n', ...
            snrs(k-1), snrs(k), ber_awgn(k-1), ber_awgn(k), ber_awgn(k)-ber_awgn(k-1));
    end
end
if ~non_monotonic
    fprintf('  ✅ BER 全部单调非增（修复成功）\n');
else
    fprintf('  ❌ 仍有非单调段（修复不彻底）\n');
end

% 接受准则核查
fprintf('\nStep 5: 接受准则核查\n');
checks = {};
checks{end+1} = sprintf('SC-FDE pass < 5%%:        %s (实测 %.3f%%)', ...
    yesno(ber_pass < 5), ber_pass);
checks{end+1} = sprintf('SC-FDE SNR=30 < 5%%:      %s (实测 %.3f%%)', ...
    yesno(ber_awgn(snrs==30) < 5), ber_awgn(snrs==30));
checks{end+1} = sprintf('SC-FDE SNR=80 < 5%%:      %s (实测 %.3f%%)', ...
    yesno(ber_awgn(snrs==80) < 5), ber_awgn(snrs==80));
checks{end+1} = sprintf('SC-FDE SNR=10 ≤ 0.1%%:    %s (实测 %.3f%%)', ...
    yesno(ber_awgn(snrs==10) <= 0.1), ber_awgn(snrs==10));
checks{end+1} = sprintf('SC-FDE SNR=20 ≤ 1%%:      %s (实测 %.3f%%)', ...
    yesno(ber_awgn(snrs==20) <= 1.0), ber_awgn(snrs==20));
for k = 1:length(checks), fprintf('  %s\n', checks{k}); end

diary off;
fprintf('Log: %s\n', diary_path);

function s = yesno(b)
    if b, s = '✅'; else, s = '❌'; end
end
