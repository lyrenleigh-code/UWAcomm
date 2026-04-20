%% verify_discrete_bench.m — 5 个 discrete_doppler runner 贯通验证
% 版本：V1.0.0（2026-04-19）

clc; close all;
this_dir = fileparts(mfilename('fullpath'));
addpath(this_dir);

fprintf('============================================\n');
fprintf('  discrete_doppler 5 runner benchmark 贯通验证\n');
fprintf('============================================\n\n');

cases = {
    'SC-FDE',  'SC-FDE',  'test_scfde_discrete_doppler.m',   ...
        { 'static', 'static', zeros(1,6), 1024, 128, 4, 0 };
    'OFDM',    'OFDM',    'test_ofdm_discrete_doppler.m',    ...
        { 'static', 'static', zeros(1,6), 1024, 128, 4, 0 };
    'SC-TDE',  'SC-TDE',  'test_sctde_discrete_doppler.m',   ...
        { 'static', 'static', zeros(1,6), 0 };
    'DSSS',    'DSSS',    'test_dsss_discrete_doppler.m',    ...
        { 'static', 'static', zeros(1,5), 0 };
    'FH-MFSK', 'FH-MFSK', 'test_fhmfsk_discrete_doppler.m',  ...
        { 'static', 'static', zeros(1,5), 0 };
};

pass_count = 0; fail_count = 0;
results = {};

for c = 1:size(cases,1)
    scheme = cases{c,1};
    subdir = cases{c,2};
    script = cases{c,3};
    cfg_row = cases{c,4};

    fprintf('\n--- 测试 [%d/%d] %s ---\n', c, size(cases,1), scheme);
    runner_path = fullfile(fileparts(this_dir), subdir, script);
    tmp_csv = fullfile(tempdir, sprintf('verify_discB_%s_%d.csv', scheme, c));
    if exist(tmp_csv, 'file'), delete(tmp_csv); end

    clearvars -except this_dir cases pass_count fail_count results ...
                      c scheme subdir script cfg_row runner_path tmp_csv

    benchmark_mode        = true;
    bench_snr_list        = [10];
    bench_fading_cfgs     = cfg_row;
    bench_channel_profile = 'custom6';
    bench_seed            = 42;
    bench_stage           = 'B-verify';
    bench_scheme_name     = scheme;
    bench_csv_path        = tmp_csv;

    try
        run(runner_path);
        assert(exist(tmp_csv, 'file') == 2, 'CSV 未生成');
        fid = fopen(tmp_csv, 'r');
        content = fread(fid, inf, 'uint8=>char').';
        fclose(fid);
        lines = splitlines(strtrim(content));
        assert(numel(lines) == 2, '行数 = %d（应 2）', numel(lines));
        hdr = strsplit(lines{1}, ',');
        data = strsplit(lines{2}, ',');
        ber_col = find(strcmp(hdr, 'ber_coded'), 1);
        ber_val = str2double(data{ber_col});
        assert(~isnan(ber_val) && ber_val >= 0 && ber_val <= 1, 'ber_coded 异常 = %g', ber_val);

        pass_count = pass_count + 1;
        results{end+1} = sprintf('%s ✓ ber=%.4f', scheme, ber_val);
        fprintf('  %s ✓ ber=%.4f\n', scheme, ber_val);
        delete(tmp_csv);
    catch ME
        fail_count = fail_count + 1;
        results{end+1} = sprintf('%s ✗ %s', scheme, ME.message);
        fprintf('  %s ✗ %s\n', scheme, ME.message);
    end
end

fprintf('\n============================================\n');
fprintf('  汇总: %d 通过 / %d 失败\n', pass_count, fail_count);
for k = 1:numel(results), fprintf('  %s\n', results{k}); end
fprintf('============================================\n');

if fail_count > 0
    error('verify_discrete_bench:HasFailures', '%d 项失败', fail_count);
end
