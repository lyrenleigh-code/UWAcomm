clear functions; clear classes; clear all; clc;
this_dir = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(streaming_root, 'common'));

out_dir = fullfile(this_dir, 'rx_simple_ui_smoke_out');
files = dir(fullfile(out_dir, 'tx_SC-FDE_*.json'));
[~, idx] = sort([files.datenum], 'descend');
json_path = fullfile(out_dir, files(idx(1)).name);
fid = fopen(json_path, 'r'); js = fread(fid, '*char').'; fclose(fid);
meta = simple_ui_meta_io('decode', js);

r = rx_simple_ui('headless', true);
r.meta = meta;
sys_dec = r.rebuild_sys_for_decode();
sys_def = sys_params_default();

fprintf('--- preamble compare ---\n');
fprintf('def: %s\n', struct2str(sys_def.preamble));
fprintf('dec: %s\n', struct2str(sys_dec.preamble));
fprintf('def fs=%d fc=%d\n', sys_def.fs, sys_def.fc);
fprintf('dec fs=%d fc=%d\n', sys_dec.fs, sys_dec.fc);

function s = struct2str(st)
    fns = fieldnames(st); cells = {};
    for k = 1:length(fns), cells{k} = sprintf('%s=%s', fns{k}, mat2str(st.(fns{k}))); end
    s = strjoin(cells, ' ');
end
