%% diag_pass_other_schemes.m - 验证其他体制在 pass 模式下工作（证 RX UI 不是 bug）
clear functions; clear classes; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));

out_dir = fullfile(this_dir, 'rx_simple_ui_smoke_out');
if exist(out_dir, 'dir'), rmdir(out_dir, 's'); end
mkdir(out_dir);

schemes = {'OFDM', 'FH-MFSK', 'DSSS'};   % 选无 cascade BEM/GAMP 的 3 体制
fprintf('========================================\n');
fprintf(' RX UI pass 模式验证（其他体制，非 SC-FDE）\n');
fprintf('========================================\n\n');

for k = 1:length(schemes)
    sch = schemes{k};
    fprintf('--- %s ---\n', sch);
    pause(1.05);
    t = tx_simple_ui('headless', true);
    t.scheme = sch;
    t.output_dir = out_dir;
    t.on_generate();
    wav = t.last_wav_path; json = t.last_json_path;
    delete(t); clear t;

    fid = fopen(json, 'r'); js = fread(fid, '*char').'; fclose(fid);
    meta = simple_ui_meta_io('decode', js);

    r = rx_simple_ui('headless', true);
    r.wav_path = wav; r.json_path = json; r.meta = meta;
    r.channel_mode = 'pass';
    r.chunk_ms = 50;
    r.on_run();
    fprintf('  %s pass mode → BER = %.3f%% (%d frames)\n\n', ...
        sch, r.last_result.mean_ber*100, r.last_result.decoded_count);
    delete(r); clear r;
end
