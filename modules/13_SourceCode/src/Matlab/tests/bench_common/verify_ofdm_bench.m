%% verify_ofdm_bench.m — OFDM runner benchmark_mode 贯通验证
% 版本：V1.0.0（2026-04-19）

clc; close all;
addpath(fileparts(mfilename('fullpath')));

fprintf('============================================\n');
fprintf('  OFDM runner benchmark_mode 贯通验证\n');
fprintf('============================================\n\n');

benchmark_mode        = true;
bench_snr_list        = [10];
bench_fading_cfgs     = { 'static', 'static', 0, 0, 1024, 128, 4 };
bench_channel_profile = 'custom6';
bench_seed            = 42;
bench_stage           = 'verify';
bench_scheme_name     = 'OFDM';

tmp_csv = fullfile(tempdir, sprintf('verify_ofdm_bench_%d.csv', round(now*1e6)));
bench_csv_path        = tmp_csv;
if exist(tmp_csv, 'file'), delete(tmp_csv); end

runner_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                       'OFDM', 'test_ofdm_timevarying.m');
fprintf('Running: %s\n', runner_path);
run(runner_path);

fprintf('\n--- CSV 验证 ---\n');
assert(exist(tmp_csv, 'file') == 2, 'CSV 未生成: %s', tmp_csv);

fid = fopen(tmp_csv, 'r');
content = fread(fid, inf, 'uint8=>char').';
fclose(fid);
lines = splitlines(strtrim(content));
assert(numel(lines) == 2, '行数 = %d（应 2）', numel(lines));
hdr_fields = strsplit(lines{1}, ',');
data_fields = strsplit(lines{2}, ',');
ber_col = find(strcmp(hdr_fields, 'ber_coded'), 1);
ber_val = str2double(data_fields{ber_col});
assert(~isnan(ber_val) && ber_val >= 0 && ber_val <= 1, 'ber_coded = %g', ber_val);
fprintf('  行数=%d ber_coded=%.4f ✓\n', numel(lines), ber_val);
fprintf('  CSV: %s\n', tmp_csv);
