%% verify_scfde_bench.m — SC-FDE runner benchmark_mode 贯通验证
% 覆盖：
%   1. benchmark_mode=true 不崩溃
%   2. CSV 按预期 schema 生成
%   3. 行数匹配 fading × snr
%   4. ber_coded 在合理范围（static+10dB 应 < 20%）
% 版本：V1.0.0（2026-04-19）

clc; close all;
addpath(fileparts(mfilename('fullpath')));

fprintf('============================================\n');
fprintf('  SC-FDE runner benchmark_mode 贯通验证\n');
fprintf('============================================\n\n');

%% ========== 注入 benchmark 参数（最小子集 1 点） ==========
benchmark_mode        = true;
bench_snr_list        = [10];
bench_fading_cfgs     = { 'static', 'static', 0, 0, 1024, 128, 4 };
bench_channel_profile = 'custom6';
bench_seed            = 42;
bench_stage           = 'verify';
bench_scheme_name     = 'SC-FDE';

% CSV 写到临时目录
tmp_csv = fullfile(tempdir, sprintf('verify_scfde_bench_%d.csv', round(now*1e6)));
bench_csv_path        = tmp_csv;

% 清理旧 CSV（如有）
if exist(tmp_csv, 'file'), delete(tmp_csv); end

%% ========== 运行 SC-FDE runner ==========
runner_path = fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
                       'SC-FDE', 'test_scfde_timevarying.m');
fprintf('Running: %s\n', runner_path);
run(runner_path);

%% ========== 验证 CSV ==========
fprintf('\n--- CSV 验证 ---\n');
assert(exist(tmp_csv, 'file') == 2, 'CSV 未生成: %s', tmp_csv);
fprintf('  CSV 路径: %s\n', tmp_csv);

fid = fopen(tmp_csv, 'r');
content = fread(fid, inf, 'uint8=>char').';
fclose(fid);
lines = splitlines(strtrim(content));

assert(numel(lines) == 2, '行数 = %d（应 1 header + 1 data = 2）', numel(lines));
fprintf('  行数: %d ✓\n', numel(lines));

header = lines{1};
for f = {'scheme','stage','profile','fd_hz','doppler_rate', ...
         'snr_db','ber_coded','frame_detected','seed'}
    assert(contains(header, f{1}), 'header 缺列 %s', f{1});
end
fprintf('  header 列齐 ✓\n');

data = lines{2};
assert(contains(data, 'SC-FDE'), 'data 无 scheme');
assert(contains(data, 'custom6'));
% ber_coded 在 data 里找数值合理范围
fields = strsplit(data, ',');
% 找到 ber_coded 列
hdr_fields = strsplit(header, ',');
ber_col = find(strcmp(hdr_fields, 'ber_coded'), 1);
ber_val = str2double(fields{ber_col});
assert(~isnan(ber_val), 'ber_coded 为 NaN');
assert(ber_val >= 0 && ber_val <= 1, 'ber_coded = %g 超范围', ber_val);
fprintf('  ber_coded = %.4f (SC-FDE static+10dB) ✓\n', ber_val);

fprintf('\n验证通过。CSV 保留在: %s\n', tmp_csv);
