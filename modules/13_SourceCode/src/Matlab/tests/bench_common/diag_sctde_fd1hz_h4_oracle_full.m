%% diag_sctde_fd1hz_h4_oracle_full.m
% 阶段 2 · H4 Oracle α 全量（15 seed × 3 SNR）
%
% 前置：diag_sctde_fd1hz_monte_carlo.m V2 baseline + h4_oracle_alpha 4 坏 seed
%
% 目的：oracle α 下 mean/median/灾难率 是否回归健康 + 单调性是否恢复
%
% 判定：
%   oracle mean <5% 且单调 + 灾难率 <15% → α estimator 是主根因，fix α 即可
%   oracle 仍有 >15% 灾难 → 部分 seed 非 α 问题，进 H2/H3
%
% 版本：V1.0.0（2026-04-24）

clear functions; clear; close all; clc;

%% 参数
h_this_dir  = fileparts(mfilename('fullpath'));
h_tests_dir = fileparts(h_this_dir);
h_runner    = fullfile(h_tests_dir, 'SC-TDE', 'test_sctde_timevarying.m');
h_out_dir   = fullfile(h_this_dir, 'diag_sctde_fd1hz_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

h_fc       = 12000;
h_snr_list = [10, 15, 20];
h_seeds    = 1:15;
h_n_snr    = length(h_snr_list);
h_n_seed   = length(h_seeds);

h_thresh_disaster = 5;
h_thresh_severe   = 30;

% Baseline 读
h_mat_prev = fullfile(h_out_dir, 'mc_summary.mat');
h_baseline = nan(h_n_snr, h_n_seed);
if exist(h_mat_prev, 'file')
    L = load(h_mat_prev, 'h_ber');
    h_baseline = L.h_ber;
    fprintf('[Baseline loaded]\n');
end

h_ber_oracle = nan(h_n_snr, h_n_seed);

fprintf('========================================\n');
fprintf('  SC-TDE fd=1Hz · 阶段 2 · H4 Oracle α 全量\n');
fprintf('  SNR=%s × seed=1..%d (%d trial × 3 fading)\n', ...
    mat2str(h_snr_list), h_n_seed, h_n_snr*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_si = 1:h_n_snr
    h_snr = h_snr_list(h_si);
    fprintf('--- SNR=%d dB ---\n  ', h_snr);
    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv = fullfile(h_out_dir, sprintf('SCTDE_seed%d_snr%d_oracleA_full.csv', h_seed, h_snr));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = h_snr;
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'fd1hz-H4-oracle-full';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;
        diag_oracle_alpha              = true;

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR] ', h_seed);
            continue;
        end

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                h_idx = find(T.fd_hz == 1, 1);
                if ~isempty(h_idx)
                    h_ber_oracle(h_si, h_di) = T.ber_coded(h_idx);
                end
            catch
            end
        end

        b = h_ber_oracle(h_si, h_di) * 100;
        if b < h_thresh_disaster, mk = '.';
        elseif b < h_thresh_severe, mk = 'o';
        else, mk = 'X';
        end
        fprintf('s%d=%.2f%%[%s] ', h_seed, b, mk);
        if mod(h_di, 5) == 0 && h_di < h_n_seed, fprintf('\n  '); end
    end
    fprintf('\n\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.2f min\n\n', h_elapsed/60);

%% Summary 表（oracle）
fprintf('=========== Oracle α 下 BER 分布 ===========\n');
fprintf('  SNR  | mean   | median | std    | min   | max    | 灾难率(>%d%%) | 严重率(>%d%%)\n', ...
        h_thresh_disaster, h_thresh_severe);
fprintf('-------+--------+--------+--------+-------+--------+--------------+--------------\n');
h_mean_oracle = nan(1, h_n_snr);
h_dis_rate_oracle = nan(1, h_n_snr);
for h_si = 1:h_n_snr
    r = h_ber_oracle(h_si, :) * 100;
    h_dis = sum(r > h_thresh_disaster, 'omitnan');
    h_sev = sum(r > h_thresh_severe,   'omitnan');
    h_mean_oracle(h_si) = mean(r, 'omitnan');
    h_dis_rate_oracle(h_si) = 100*h_dis/h_n_seed;
    fprintf('  %3d  | %6.2f | %6.2f | %6.2f | %5.2f | %6.2f | %2d/%d (%4.1f%%) | %2d/%d (%4.1f%%)\n', ...
        h_snr_list(h_si), ...
        h_mean_oracle(h_si), median(r,'omitnan'), std(r,'omitnan'), ...
        min(r,[],'omitnan'), max(r,[],'omitnan'), ...
        h_dis, h_n_seed, h_dis_rate_oracle(h_si), ...
        h_sev, h_n_seed, 100*h_sev/h_n_seed);
end

%% 对比 baseline
fprintf('\n=========== Baseline vs Oracle（mean/灾难率）===========\n');
fprintf('  SNR  | base mean | oracle mean | Δmean   | base 灾难率 | oracle 灾难率 | Δ灾难率\n');
fprintf('-------+-----------+-------------+---------+-------------+---------------+---------\n');
for h_si = 1:h_n_snr
    m_b = mean(h_baseline(h_si, :) * 100, 'omitnan');
    m_o = h_mean_oracle(h_si);
    dis_b = sum(h_baseline(h_si, :) * 100 > h_thresh_disaster, 'omitnan') / h_n_seed * 100;
    dis_o = h_dis_rate_oracle(h_si);
    fprintf('  %3d  | %8.2f%% | %10.2f%% | %+6.2f | %9.1f%% | %11.1f%% | %+6.1f\n', ...
        h_snr_list(h_si), m_b, m_o, m_o-m_b, dis_b, dis_o, dis_o-dis_b);
end

%% 单调性检查
fprintf('\n=========== 单调性检查 ===========\n');
fprintf('  oracle mean BER = ');
for h_si = 1:h_n_snr
    fprintf('SNR=%d:%.2f%%  ', h_snr_list(h_si), h_mean_oracle(h_si));
end
fprintf('\n');
if all(diff(h_mean_oracle) <= 0)
    fprintf('  ✓ oracle 下 mean 单调递降\n');
else
    fprintf('  ✗ oracle 下 mean 仍非单调\n');
end

%% 灾难 seed 残留
fprintf('\n=========== oracle 下残留灾难 seed (>%d%%) ===========\n', h_thresh_disaster);
for h_si = 1:h_n_snr
    r = h_ber_oracle(h_si, :) * 100;
    h_idx = find(r > h_thresh_disaster);
    if isempty(h_idx)
        fprintf('  SNR=%d: 无\n', h_snr_list(h_si));
    else
        fprintf('  SNR=%d: ', h_snr_list(h_si));
        for h_k = 1:length(h_idx)
            fprintf('s%d=%.2f%% ', h_seeds(h_idx(h_k)), r(h_idx(h_k)));
        end
        fprintf('\n');
    end
end

%% H4 全量判定
fprintf('\n=========== H4 全量判定 ===========\n');
h_max_dis = max(h_dis_rate_oracle);
h_mean_max = max(h_mean_oracle);
h_monotone = all(diff(h_mean_oracle) <= 0);
if h_mean_max < 5 && h_max_dis < 15 && h_monotone
    fprintf('  ✓ H4 全量 confirmed: mean<5%% + 灾难率<15%% + 单调\n');
    fprintf('  → α estimator 偏差是 fd=1Hz 非单调主根因\n');
    fprintf('  → fix α estimator 应能恢复 fd=1Hz 正常工作\n');
elseif h_max_dis < 30 && h_monotone
    fprintf('  🟡 H4 部分 confirmed: 单调恢复 + 灾难率降到 %.1f%% (<30%%)\n', h_max_dis);
    fprintf('  → α 是主因但非唯一，残留 seed 需 H2/H3 补充\n');
else
    fprintf('  ✗ H4 不完全: oracle 下 mean_max=%.2f%% / 灾难率_max=%.1f%% / 单调=%d\n', ...
        h_mean_max, h_max_dis, h_monotone);
    fprintf('  → α 非主因，转 H2（BEM Q）或 H3（nv_post）\n');
end

%% 持久化
h_mat = fullfile(h_out_dir, 'h4_oracle_full.mat');
save(h_mat, 'h_ber_oracle', 'h_baseline', 'h_seeds', 'h_snr_list', ...
           'h_elapsed', 'h_mean_oracle', 'h_dis_rate_oracle');
fprintf('\n矩阵已保存：%s\n\n完成\n', h_mat);
