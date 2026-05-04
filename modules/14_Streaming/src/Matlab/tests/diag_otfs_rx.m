clear functions; clear classes; clear all; clc;
this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));

out_dir = fullfile(this_dir, 'simple_ui_full_matrix_out');
files = dir(fullfile(out_dir, 'tx_OTFS_*.json'));
[~, idx] = sort([files.datenum], 'descend');
json_path = fullfile(out_dir, files(idx(1)).name);
[~, base, ~] = fileparts(json_path);
wav_path = fullfile(out_dir, [base '.wav']);

fprintf('OTFS wav: %s\n', wav_path);
fid = fopen(json_path, 'r'); js = fread(fid, '*char').'; fclose(fid);
meta = simple_ui_meta_io('decode', js);

fprintf('meta.frame: '); disp(meta.frame);
fprintf('meta.scheme: %s\n', meta.scheme);
if isfield(meta, 'encode_meta')
    fprintf('encode_meta fields: %s\n', strjoin(fieldnames(meta.encode_meta), ', '));
else
    fprintf('encode_meta MISSING\n');
end

r = rx_simple_ui('headless', true);
r.wav_path = wav_path; r.json_path = json_path; r.meta = meta;
r.channel_mode = 'pass'; r.chunk_ms = 50;
try
    r.on_run();
    fprintf('OTFS pass result: BER=%.3f%% frames=%d\n', ...
        r.last_result.mean_ber*100, r.last_result.decoded_count);
catch ME
    fprintf('OTFS pass ERR: %s\n', ME.message);
    if ~isempty(ME.stack)
        for si = 1:min(5, length(ME.stack))
            fprintf('  @ %s L%d\n', ME.stack(si).name, ME.stack(si).line);
        end
    end
end
