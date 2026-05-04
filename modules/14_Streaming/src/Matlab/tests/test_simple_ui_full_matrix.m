%% test_simple_ui_full_matrix.m
% 完整 6 体制 × 4 信道模式 = 24 cases BER 矩阵
% 用于详细测试报告
% Spec: specs/active/2026-05-04-tx-rx-simple-ui-split.md

clear functions; clear classes; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));

diary_path = fullfile(this_dir, 'test_simple_ui_full_matrix_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('================================================================\n');
fprintf(' tx_simple_ui + rx_simple_ui 完整测试矩阵\n');
fprintf(' 6 体制 × 4 信道模式 = 24 cases\n');
fprintf(' 时间：%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('================================================================\n\n');

out_dir = fullfile(this_dir, 'simple_ui_full_matrix_out');
if exist(out_dir, 'dir'), rmdir(out_dir, 's'); end
mkdir(out_dir);

schemes = {'SC-FDE', 'OFDM', 'SC-TDE', 'OTFS', 'DSSS', 'FH-MFSK'};
modes   = {'pass', 'awgn', 'jakes', 'multipath'};

% --- Step 1: TX 生成 6 个 wav ---
fprintf('==== Step 1: 6 体制 TX 生成 ====\n\n');
wav_paths  = cell(1, length(schemes));
json_paths = cell(1, length(schemes));
for k = 1:length(schemes)
    sch = schemes{k};
    fprintf('--- TX %s ---\n', sch);
    pause(1.05);
    t = tx_simple_ui('headless', true);
    t.scheme = sch;
    t.output_dir = out_dir;
    t.on_generate();
    wav_paths{k}  = t.last_wav_path;
    json_paths{k} = t.last_json_path;
    delete(t); clear t;
end

% --- Step 2: 6 × 4 RX 解码矩阵 ---
fprintf('\n==== Step 2: RX 解码矩阵 ====\n\n');

ber_matrix     = NaN(length(schemes), length(modes));
frames_matrix  = zeros(length(schemes), length(modes));
alpha_matrix   = NaN(length(schemes), length(modes));
gate_matrix    = strings(length(schemes), length(modes));
fs_pos_matrix  = zeros(length(schemes), length(modes));
elapsed_matrix = NaN(length(schemes), length(modes));
err_matrix     = strings(length(schemes), length(modes));

for ki = 1:length(schemes)
    for mi = 1:length(modes)
        sch  = schemes{ki};
        mode = modes{mi};
        fprintf('=== [%d/%d] %s × %s ===\n', ...
            (ki-1)*length(modes)+mi, length(schemes)*length(modes), sch, mode);
        try
            r = rx_simple_ui('headless', true);
            r.wav_path  = wav_paths{ki};
            r.json_path = json_paths{ki};
            fid = fopen(json_paths{ki}, 'r'); js = fread(fid, '*char').'; fclose(fid);
            r.meta = simple_ui_meta_io('decode', js);
            r.channel_mode = mode;
            r.channel_params.snr_db = 20;
            r.channel_params.fading_type = 'slow';
            r.channel_params.fading_fd_hz = 1;
            r.channel_params.doppler_rate = 0;
            r.channel_params.mp_seed = 4242;
            r.chunk_ms = 50;

            tic;
            r.on_run();
            elapsed_matrix(ki, mi) = toc;

            ber_matrix(ki, mi)    = r.last_result.mean_ber;
            frames_matrix(ki, mi) = r.last_result.decoded_count;
            if r.last_result.decoded_count > 0
                d = r.last_result.details{1};
                alpha_matrix(ki, mi)  = d.alpha_used;
                gate_matrix(ki, mi)   = string(d.alpha_gate_reason);
                fs_pos_matrix(ki, mi) = d.fs_pos;
            end

            fprintf('  → BER=%.3f%% frames=%d α=%+.2e gate=%s fs_pos=%d (elapsed %.1fs)\n\n', ...
                r.last_result.mean_ber*100, r.last_result.decoded_count, ...
                alpha_matrix(ki, mi), gate_matrix(ki, mi), fs_pos_matrix(ki, mi), ...
                elapsed_matrix(ki, mi));

            delete(r); clear r;
        catch ME
            err_matrix(ki, mi) = string(ME.message);
            fprintf('  → [ERR] %s\n\n', ME.message);
        end
    end
end

% --- Step 3: 输出报告 ---
fprintf('\n================================================================\n');
fprintf(' 测试矩阵报告\n');
fprintf('================================================================\n\n');

fprintf('## BER 矩阵 (%%)\n\n');
fprintf('| 体制\\模式  | %8s | %8s | %8s | %8s |\n', modes{:});
fprintf('|-----------|----------|----------|----------|----------|\n');
for ki = 1:length(schemes)
    fprintf('| %-9s ', schemes{ki});
    for mi = 1:length(modes)
        if frames_matrix(ki, mi) == 0 && ~isempty(char(err_matrix(ki, mi)))
            fprintf('| %8s ', 'ERR');
        elseif frames_matrix(ki, mi) == 0
            fprintf('| %8s ', '0 frame');
        else
            fprintf('| %7.3f%% ', ber_matrix(ki, mi)*100);
        end
    end
    fprintf('|\n');
end

fprintf('\n## 帧数矩阵\n\n');
fprintf('| 体制\\模式  | %8s | %8s | %8s | %8s |\n', modes{:});
fprintf('|-----------|----------|----------|----------|----------|\n');
for ki = 1:length(schemes)
    fprintf('| %-9s ', schemes{ki});
    for mi = 1:length(modes)
        fprintf('| %8d ', frames_matrix(ki, mi));
    end
    fprintf('|\n');
end

fprintf('\n## α 估计 + gate 决策\n\n');
fprintf('| 体制\\模式  | %15s | %15s | %15s | %15s |\n', modes{:});
fprintf('|-----------|-----------------|-----------------|-----------------|-----------------|\n');
for ki = 1:length(schemes)
    fprintf('| %-9s ', schemes{ki});
    for mi = 1:length(modes)
        if frames_matrix(ki, mi) > 0
            fprintf('| %+.2e %-7s', alpha_matrix(ki, mi), gate_matrix(ki, mi));
        else
            fprintf('| %-15s ', '—');
        end
    end
    fprintf('|\n');
end

fprintf('\n## 同步位置（fs_pos，理想 = 1）\n\n');
fprintf('| 体制\\模式  | %8s | %8s | %8s | %8s |\n', modes{:});
fprintf('|-----------|----------|----------|----------|----------|\n');
for ki = 1:length(schemes)
    fprintf('| %-9s ', schemes{ki});
    for mi = 1:length(modes)
        fprintf('| %8d ', fs_pos_matrix(ki, mi));
    end
    fprintf('|\n');
end

fprintf('\n## 单帧解码耗时 (s)\n\n');
fprintf('| 体制\\模式  | %8s | %8s | %8s | %8s |\n', modes{:});
fprintf('|-----------|----------|----------|----------|----------|\n');
for ki = 1:length(schemes)
    fprintf('| %-9s ', schemes{ki});
    for mi = 1:length(modes)
        if isnan(elapsed_matrix(ki, mi))
            fprintf('| %8s ', '—');
        else
            fprintf('| %7.2fs ', elapsed_matrix(ki, mi));
        end
    end
    fprintf('|\n');
end

fprintf('\n## 总结统计\n\n');
n_total = numel(ber_matrix);
n_decoded = sum(frames_matrix(:) > 0);
ber_low = sum(ber_matrix(:) < 0.05 & ~isnan(ber_matrix(:)));    % BER < 5%
ber_zero = sum(ber_matrix(:) < 0.001 & ~isnan(ber_matrix(:)));  % BER < 0.1%
fprintf('  总 cases:        %d\n', n_total);
fprintf('  解码成功:        %d (%.1f%%)\n', n_decoded, n_decoded/n_total*100);
fprintf('  BER < 5%%:        %d (%.1f%%)\n', ber_low, ber_low/n_total*100);
fprintf('  BER < 0.1%%:      %d (%.1f%%)\n', ber_zero, ber_zero/n_total*100);
fprintf('  总耗时 (24 case): %.1fs\n', nansum(elapsed_matrix(:)));

% 保存矩阵到 .mat 供后续报告生成
mat_path = fullfile(out_dir, 'matrix_results.mat');
save(mat_path, 'schemes', 'modes', 'ber_matrix', 'frames_matrix', ...
    'alpha_matrix', 'gate_matrix', 'fs_pos_matrix', 'elapsed_matrix', 'err_matrix');
fprintf('\n矩阵 .mat 保存：%s\n', mat_path);

diary off;
fprintf('Log: %s\n', diary_path);
