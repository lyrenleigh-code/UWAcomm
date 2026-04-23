%% diag_5scheme_monte_carlo.m
% Phase c：5 体制灾难率横向 sanity check
%
% 验证 SC-FDE 发现的 ~10% deterministic 灾难触发率是否是孤立现象，还是
% OFDM/SC-TDE/DSSS/FH-MFSK 也有类似问题（之前 bench_seed=42 单 seed 假象
% 可能掩盖了所有 5 体制的系统脆弱性）。
%
% 矩阵：5 scheme × α ∈ {+1e-2} × SNR=10 dB × seed ∈ 1:15 = 75 trial
%   （α=+1e-2 是 SC-FDE 最薄弱点，seed 减到 15 降低跑时）
%
% OTFS 跳过（memory: uwacomm skip_otfs）
%
% 输出：每体制灾难率直方图 + median/max BER 对比
%
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_tests_dir = fileparts(h_this_dir);   % .../tests/
h_out_dir  = fullfile(h_this_dir, 'diag_5scheme_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

% 5 scheme（不含 OTFS）
h_schemes = {
    'SC-FDE',  fullfile(h_tests_dir, 'SC-FDE', 'test_scfde_timevarying.m');
    'OFDM',    fullfile(h_tests_dir, 'OFDM',   'test_ofdm_timevarying.m');
    'SC-TDE',  fullfile(h_tests_dir, 'SC-TDE', 'test_sctde_timevarying.m');
    'DSSS',    fullfile(h_tests_dir, 'DSSS',   'test_dsss_timevarying.m');
    'FH-MFSK', fullfile(h_tests_dir, 'FH-MFSK','test_fhmfsk_timevarying.m');
};
h_alpha  = +1e-2;
h_snr    = 10;
h_seeds  = 1:15;
h_n_sch  = size(h_schemes, 1);
h_n_seed = length(h_seeds);

h_ber = nan(h_n_sch, h_n_seed);

fprintf('========================================\n');
fprintf('  5 体制灾难率横向 Monte Carlo\n');
fprintf('  α=%+.0e, SNR=%d dB, seed=1..%d (75 trial)\n', h_alpha, h_snr, h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_ci = 1:h_n_sch
    h_scheme = h_schemes{h_ci, 1};
    h_runner = h_schemes{h_ci, 2};
    fprintf('--- %s ---\n  ', h_scheme);
    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv = fullfile(h_out_dir, sprintf('%s_seed%d.csv', h_scheme, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        % fading_cfgs 列数依 scheme：SC-FDE/OFDM 7 列，其他 4 列
        if any(strcmp(h_scheme, {'SC-FDE','OFDM'}))
            bench_fading_cfgs = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha, 1024, 128, 4 };
        else
            bench_fading_cfgs = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
        end
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'C-sanity';
        bench_scheme_name              = h_scheme;
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR:%s] ', h_seed, ME.message(1:min(end,30)));
            continue;
        end

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                if height(T) >= 1, h_ber(h_ci, h_di) = T.ber_coded(1); end
            catch, end
        end

        b = h_ber(h_ci, h_di) * 100;
        if b < 1, mk='.'; elseif b < 30, mk='o'; else mk='X'; end
        fprintf('s%d=%.1f%%[%s] ', h_seed, b, mk);
        if mod(h_di, 5)==0 && h_di<h_n_seed, fprintf('\n  '); end
    end
    fprintf('\n\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Summary
fprintf('=========== BER 分布统计 (α=+1e-2, SNR=%d dB) ===========\n', h_snr);
fprintf('  scheme   | mean  | median | std   | min  | max   | 灾难率 (>30%%)\n');
fprintf('-----------+-------+--------+-------+------+-------+----------------\n');
for h_ci = 1:h_n_sch
    r = h_ber(h_ci, :) * 100;
    h_dis = sum(r > 30, 'omitnan');
    fprintf('  %-8s | %5.2f | %5.2f  | %5.2f | %4.1f | %5.2f | %d/%d (%4.1f%%)\n', ...
        h_schemes{h_ci,1}, ...
        mean(r,'omitnan'), median(r,'omitnan'), std(r,'omitnan'), ...
        min(r,[],'omitnan'), max(r,[],'omitnan'), ...
        h_dis, h_n_seed, 100*h_dis/h_n_seed);
end

fprintf('\n=========== 判定 ===========\n');
for h_ci = 1:h_n_sch
    r = h_ber(h_ci, :) * 100;
    h_dis = sum(r > 30, 'omitnan');
    h_rate = 100*h_dis/h_n_seed;
    if h_rate == 0
        fprintf('  %-8s: ✓ 健康（0/%d 灾难）\n', h_schemes{h_ci,1}, h_n_seed);
    elseif h_rate > 15
        fprintf('  %-8s: ⚠ 灾难率 %.1f%%（%d/%d），与 SC-FDE 同源问题\n', ...
            h_schemes{h_ci,1}, h_rate, h_dis, h_n_seed);
    else
        fprintf('  %-8s: 🟡 轻度灾难 %.1f%%\n', h_schemes{h_ci,1}, h_rate);
    end
end

fprintf('\n完成\n');
