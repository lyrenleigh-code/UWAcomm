%% diag_sctde_fd1hz_v5_6_verify.m
% V5.6 path E verify：HFM-signature based deterministic bias calibration
%
% 矩阵：default fading_cfgs (fd=0/1/5) × 15 seed × SNR={10,15,20}
% 配置：caller 不显式设 bench_alpha_iter / bench_v56_calib_amount → V5.5+V5.6 default
%   fd=0 → iter=2, calib disabled (HFM=0)
%   fd=1 → iter=0, calib -1.5e-5 (HFM=-1)
%   fd=5 → iter=2, calib disabled (HFM≫-1)
%
% 比较：V5.6 vs V5.5 (alpha_err phase1.2 / phase2 cond1 数据 = iter=0 explicit) vs oracle (h4_oracle_full)
%
% 接受准则：spec 5/5
%   SNR=15 mean ≤ 3% / 灾难率 ≤ 25%
%   SNR=20 mean ≤ 1.5% / 灾难率 ≤ 15%
%   单调性 ✓
%
% 版本：V1.0.0 (2026-04-25)

clear functions; clear; close all; clc;

%% 参数
h_this_dir  = fileparts(mfilename('fullpath'));
h_tests_dir = fileparts(h_this_dir);
h_runner    = fullfile(h_tests_dir, 'SC-TDE', 'test_sctde_timevarying.m');
h_out_dir   = fullfile(h_this_dir, 'diag_sctde_fd1hz_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

h_snr_list = [10, 15, 20];
h_seeds    = 1:15;
h_n_snr    = length(h_snr_list);
h_n_seed   = length(h_seeds);
n_seed = h_n_seed;
thresh_dis = 5;

h_csv_master = fullfile(h_out_dir, 'v5_6_verify_summary.csv');
if exist(h_csv_master, 'file'), delete(h_csv_master); end

fprintf('========================================\n');
fprintf('  V5.6 verify · HFM-signature bias calibration\n');
fprintf('  default fading_cfgs × 15 seed × SNR=%s\n', mat2str(h_snr_list));
fprintf('========================================\n\n');

h_t0 = tic;
for h_si = 1:h_n_snr
    h_snr = h_snr_list(h_si);
    fprintf('--- SNR=%d dB ---\n  ', h_snr);
    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv_trial = fullfile(h_out_dir, sprintf('v56_seed%d_snr%d.csv', h_seed, h_snr));
        if exist(h_csv_trial, 'file'), delete(h_csv_trial); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = h_snr;
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'v5_6-verify';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv_trial;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;
        diag_oracle_alpha              = false;
        % caller 不显式设 bench_alpha_iter / bench_v56_calib_amount
        % 让 V5.5（fd-conditional iter） + V5.6（HFM signature calib）自动 kick in

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR:%s] ', h_seed, ME.identifier);
            continue;
        end

        if exist(h_csv_trial, 'file')
            try
                T_trial = readtable(h_csv_trial);
                if exist(h_csv_master, 'file')
                    T_acc = readtable(h_csv_master);
                    T_acc = [T_acc; T_trial]; %#ok<AGROW>
                    writetable(T_acc, h_csv_master);
                else
                    writetable(T_trial, h_csv_master);
                end
            catch
            end
        end
        fprintf('s%d ', h_seed);
        if mod(h_di, 5) == 0 && h_di < h_n_seed, fprintf('\n  '); end
    end
    fprintf('\n\n');
end
fprintf('总用时：%.2f min\n\n', toc(h_t0)/60);

%% 加载比较数据
T_v56 = readtable(h_csv_master);
T_v56_fd1 = T_v56(T_v56.fd_hz == 1, :);

m_v55 = load(fullfile(h_out_dir, 'phase2_summary.mat'));    % V5.5 proxy（iter=0 + sub=ON）
T_v55_fd1 = m_v55.T_on(m_v55.T_on.fd_hz == 1, :);

m_oracle = load(fullfile(h_out_dir, 'h4_oracle_full.mat'));
ber_oracle = m_oracle.h_ber_oracle;

%% 三方对比
fprintf('========== fd=1Hz V5.5 / V5.6 / oracle 对比 ==========\n');
fprintf('  SNR | V5.5 mean / 灾难率 | V5.6 mean / 灾难率 | oracle mean / 灾难率\n');
fprintf('------+--------------------+--------------------+----------------------\n');
mean_v56_arr = nan(1, h_n_snr);
dis_v56_arr  = nan(1, h_n_snr);
for s_i = 1:h_n_snr
    snr = h_snr_list(s_i);
    m1 = T_v55_fd1.snr_db == snr;
    m2 = T_v56_fd1.snr_db == snr;
    b_v55 = T_v55_fd1.ber_coded(m1) * 100;
    b_v56 = T_v56_fd1.ber_coded(m2) * 100;
    b_or  = ber_oracle(s_i, :) * 100;

    mn_v55 = mean(b_v55);  dis_v55 = sum(b_v55 > thresh_dis) / n_seed * 100;
    mn_v56 = mean(b_v56);  dis_v56 = sum(b_v56 > thresh_dis) / n_seed * 100;
    mn_or  = mean(b_or, 'omitnan'); dis_or = sum(b_or > thresh_dis, 'omitnan') / n_seed * 100;

    mean_v56_arr(s_i) = mn_v56;
    dis_v56_arr(s_i)  = dis_v56;

    fprintf('  %3d | %6.2f%% / %5.1f%%   | %6.2f%% / %5.1f%%   | %6.2f%% / %5.1f%%\n', ...
        snr, mn_v55, dis_v55, mn_v56, dis_v56, mn_or, dis_or);
end

%% L0 偏差对比
fprintf('\n========== L0 |α_err| 对比（calibration 效果）==========\n');
fprintf('  SNR | V5.5 raw |err| | V5.6 raw |err|（含 calib）\n');
fprintf('------+----------------+---------------------------\n');
for s_i = 1:h_n_snr
    snr = h_snr_list(s_i);
    m1 = T_v55_fd1.snr_db == snr;
    m2 = T_v56_fd1.snr_db == snr;
    e1 = mean(abs(T_v55_fd1.alpha_lfm_raw(m1) - T_v55_fd1.doppler_rate(m1)));
    % V5.6 中 alpha_lfm_raw 仍是 estimator 直出（calibration 在 raw_snapshot 后），
    % alpha_lfm_iter / alpha_lfm_scan 含 calibration（fd=1Hz iter=0 → iter==raw 校准后==scan）
    e2_raw  = mean(abs(T_v56_fd1.alpha_lfm_raw(m2) - T_v56_fd1.doppler_rate(m2)));
    e2_post = mean(abs(T_v56_fd1.alpha_lfm_iter(m2) - T_v56_fd1.doppler_rate(m2)));
    fprintf('  %3d | %.3e        | raw %.3e / post-calib %.3e\n', snr, e1, e2_raw, e2_post);
end

%% 单调性
fprintf('\n========== V5.6 单调性 ==========\n');
fprintf('  V5.6 mean: %.2f → %.2f → %.2f', mean_v56_arr);
mono_v56 = all(diff(mean_v56_arr) <= 0);
if mono_v56, fprintf(' ✓ 单调\n'); else, fprintf(' ✗ 非单调\n'); end

%% Spec 接受准则
fprintf('\n========== Spec 接受准则达成度（V5.6）==========\n');
m20_v56 = T_v56_fd1.snr_db == 20;
mn_20 = mean(T_v56_fd1.ber_coded(m20_v56)) * 100;
ds_20 = sum(T_v56_fd1.ber_coded(m20_v56) > 0.05) / n_seed * 100;
m15_v56 = T_v56_fd1.snr_db == 15;
mn_15 = mean(T_v56_fd1.ber_coded(m15_v56)) * 100;
ds_15 = sum(T_v56_fd1.ber_coded(m15_v56) > 0.05) / n_seed * 100;

fprintf('  SNR=15 mean ≤ 3%%   : V5.6=%.2f%%   %s\n', mn_15, tick(mn_15 <= 3));
fprintf('  SNR=15 灾难率 ≤ 25%%: V5.6=%.1f%%   %s\n', ds_15, tick(ds_15 <= 25));
fprintf('  SNR=20 mean ≤ 1.5%%: V5.6=%.2f%%   %s\n', mn_20, tick(mn_20 <= 1.5));
fprintf('  SNR=20 灾难率 ≤ 15%%: V5.6=%.1f%%   %s\n', ds_20, tick(ds_20 <= 15));
fprintf('  单调性               : %d        %s\n', mono_v56, tick(mono_v56));

%% 持久化
h_mat = fullfile(h_out_dir, 'v5_6_verify_summary.mat');
save(h_mat, 'T_v56', 'T_v55_fd1', 'ber_oracle', 'mean_v56_arr', 'dis_v56_arr', 'mono_v56');
fprintf('\n.mat 持久化：%s\n完成\n', h_mat);

function s = tick(b)
if b, s = '✓ PASS'; else, s = '✗ FAIL'; end
end
