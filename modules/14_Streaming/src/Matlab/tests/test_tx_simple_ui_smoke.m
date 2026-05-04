%% test_tx_simple_ui_smoke.m
% 验证 tx_simple_ui 在 headless 模式下能为 6 体制生成 wav + JSON meta
% Spec: specs/active/2026-05-04-tx-rx-simple-ui-split.md

clear functions; clear classes; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));

diary_path = fullfile(this_dir, 'test_tx_simple_ui_smoke_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('========================================\n');
fprintf(' tx_simple_ui smoke test (6 体制)\n');
fprintf('========================================\n\n');

out_dir = fullfile(this_dir, 'tx_simple_ui_smoke_out');
if exist(out_dir, 'dir'), rmdir(out_dir, 's'); end
mkdir(out_dir);

schemes = {'SC-FDE','OFDM','SC-TDE','OTFS','DSSS','FH-MFSK'};
pass_count = 0;
total = 0;

for k = 1:length(schemes)
    sch = schemes{k};
    fprintf('--- %s ---\n', sch);

    try
        t = tx_simple_ui('headless', true);
        t.scheme = sch;
        t.output_dir = out_dir;

        % SC-FDE 用 V4.0 预设；其他用默认（已含合理初值）
        if strcmp(sch, 'SC-FDE')
            % default 已是 V4.0 配置
        elseif strcmp(sch, 'OFDM')
            t.ui_vals.blk_fft = 256;
            t.ui_vals.turbo_iter = 3;
        end

        % 等 1 秒避免 timestamp 撞名
        pause(1.05);
        t.on_generate();

        % 验证 wav + JSON 存在
        total = total + 1;
        wav_path  = t.last_wav_path;
        json_path = t.last_json_path;
        if exist(wav_path, 'file') && exist(json_path, 'file')
            % 验证 wav 可回读
            [audio, fs_read] = audioread(wav_path);
            % 验证 JSON 可解析
            fid = fopen(json_path, 'r');
            json_str = fread(fid, '*char').';
            fclose(fid);
            meta = simple_ui_meta_io('decode', json_str);

            ok_size = length(audio) == meta.frame.frame_pb_samples;
            ok_scheme = strcmp(meta.scheme, sch);
            ok_known_bits = isfield(meta, 'known_bits') && length(meta.known_bits) == meta.frame.N_info;

            if ok_size && ok_scheme && ok_known_bits && fs_read == 48000
                pass_count = pass_count + 1;
                fprintf('  [PASS] %s 生成 OK: wav=%d samples, JSON N_info=%d, body_offset=%d\n', ...
                    sch, length(audio), meta.frame.N_info, meta.frame.body_offset);
            else
                fprintf('  [FAIL] %s 验证失败: ok_size=%d ok_scheme=%d ok_known_bits=%d fs=%d\n', ...
                    sch, ok_size, ok_scheme, ok_known_bits, fs_read);
            end
        else
            fprintf('  [FAIL] 文件未生成: wav exists=%d, json exists=%d\n', ...
                exist(wav_path, 'file') == 2, exist(json_path, 'file') == 2);
        end

        delete(t);   % cleanup
        clear t;

    catch ME
        total = total + 1;
        fprintf('  [FAIL] exception: %s\n', ME.message);
        if ~isempty(ME.stack)
            for si = 1:min(3, length(ME.stack))
                fprintf('    @ %s L%d\n', ME.stack(si).name, ME.stack(si).line);
            end
        end
    end
end

fprintf('\n========================================\n');
fprintf(' Result: %d/%d 体制 PASS\n', pass_count, total);
fprintf('========================================\n');

% 列出生成的文件
fprintf('\n生成的文件 (%s):\n', out_dir);
files = dir(fullfile(out_dir, '*.*'));
for k = 1:length(files)
    if files(k).isdir, continue; end
    fprintf('  %s (%.1f KB)\n', files(k).name, files(k).bytes/1024);
end

diary off;
fprintf('Log: %s\n', diary_path);
