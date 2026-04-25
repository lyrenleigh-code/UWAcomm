%% diag_sctde_fd1hz_iter_ablation.m
% Phase 2 (新发现) · iter refinement 消融实验
%
% 上游：diag_sctde_fd1hz_alpha_err.m 发现 iter 让 |err| 1.5e-5 → 3.0e-5（翻倍）
% 假设：iter refinement 在 fd=1Hz Jakes 下朝错误方向收敛
% 实验：bench_alpha_iter = 0（关 iter）vs 默认 2（已有数据）对比
%
% 矩阵：与 alpha_err 同（15 seed × 3 SNR × 3 fading）
% 输出：no-iter CSV + 与 baseline 对比（mean BER / |err_L0=L1=L3|）
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

h_csv_master = fullfile(h_out_dir, 'iter_ablation_summary.csv');
if exist(h_csv_master, 'file'), delete(h_csv_master); end

fprintf('========================================\n');
fprintf('  Phase 2 ablation · bench_alpha_iter=0\n');
fprintf('  SNR=%s × seed=1..%d (%d trial × 3 fading)\n', ...
    mat2str(h_snr_list), h_n_seed, h_n_snr*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_si = 1:h_n_snr
    h_snr = h_snr_list(h_si);
    fprintf('--- SNR=%d dB ---\n  ', h_snr);
    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv_trial = fullfile(h_out_dir, sprintf('SCTDE_seed%d_snr%d_iter0.csv', h_seed, h_snr));
        if exist(h_csv_trial, 'file'), delete(h_csv_trial); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = h_snr;
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'fd1hz-iter-ablation';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv_trial;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;
        diag_oracle_alpha              = false;
        bench_alpha_iter               = 0;        % 关 iter ★
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
h_elapsed = toc(h_t0);
fprintf('总用时：%.2f min\n\n', h_elapsed/60);

%% 读结果
T_iter0 = readtable(h_csv_master);
T_iter0_fd1 = T_iter0(T_iter0.fd_hz == 1, :);

% baseline (iter=2) 数据
h_csv_base = fullfile(h_out_dir, 'alpha_err_summary.csv');
T_base = readtable(h_csv_base);
T_base_fd1 = T_base(T_base.fd_hz == 1, :);

%% L0 / L3 偏差对比
err_L0_iter0 = abs(T_iter0_fd1.alpha_lfm_raw - T_iter0_fd1.doppler_rate);
err_L3_iter0 = abs(T_iter0_fd1.alpha_est     - T_iter0_fd1.doppler_rate);
err_L0_base  = abs(T_base_fd1.alpha_lfm_raw  - T_base_fd1.doppler_rate);
err_L3_base  = abs(T_base_fd1.alpha_est      - T_base_fd1.doppler_rate);

fprintf('=========== |α_err| 对比（iter=0 vs iter=2）===========\n');
fprintf('  SNR  | L0 base   | L0 iter0  | L3 base   | L3 iter0\n');
fprintf('-------+-----------+-----------+-----------+-----------\n');
for h_si = 1:h_n_snr
    m1 = T_base_fd1.snr_db  == h_snr_list(h_si);
    m2 = T_iter0_fd1.snr_db == h_snr_list(h_si);
    fprintf('  %3d  | %.3e | %.3e | %.3e | %.3e\n', h_snr_list(h_si), ...
        mean(err_L0_base(m1)), mean(err_L0_iter0(m2)), ...
        mean(err_L3_base(m1)), mean(err_L3_iter0(m2)));
end

%% BER 对比
fprintf('\n=========== fd=1Hz mean BER 对比 ===========\n');
fprintf('  SNR  | base mean BER | iter0 mean BER | Δ\n');
fprintf('-------+---------------+----------------+--------\n');
for h_si = 1:h_n_snr
    m1 = T_base_fd1.snr_db  == h_snr_list(h_si);
    m2 = T_iter0_fd1.snr_db == h_snr_list(h_si);
    b1 = mean(T_base_fd1.ber_coded(m1)) * 100;
    b2 = mean(T_iter0_fd1.ber_coded(m2)) * 100;
    fprintf('  %3d  | %10.2f%% | %11.2f%% | %+6.2f\n', h_snr_list(h_si), b1, b2, b2 - b1);
end

%% 灾难率（>5%）对比
fprintf('\n=========== fd=1Hz 灾难率（BER>5%%）对比 ===========\n');
fprintf('  SNR  | base 灾难率 | iter0 灾难率 | Δ\n');
fprintf('-------+-------------+--------------+--------\n');
for h_si = 1:h_n_snr
    m1 = T_base_fd1.snr_db  == h_snr_list(h_si);
    m2 = T_iter0_fd1.snr_db == h_snr_list(h_si);
    d1 = sum(T_base_fd1.ber_coded(m1) > 0.05)  / h_n_seed * 100;
    d2 = sum(T_iter0_fd1.ber_coded(m2) > 0.05) / h_n_seed * 100;
    fprintf('  %3d  | %9.1f%% | %10.1f%% | %+6.1f\n', h_snr_list(h_si), d1, d2, d2 - d1);
end

%% 单调性 SNR↑ → mean BER↓
mean_ber_iter0 = nan(1, h_n_snr);
for h_si = 1:h_n_snr
    m2 = T_iter0_fd1.snr_db == h_snr_list(h_si);
    mean_ber_iter0(h_si) = mean(T_iter0_fd1.ber_coded(m2)) * 100;
end
fprintf('\n=========== iter0 单调性检查 ===========\n');
fprintf('  iter0 mean BER：');
for h_si = 1:h_n_snr, fprintf('SNR=%d:%.2f%%  ', h_snr_list(h_si), mean_ber_iter0(h_si)); end
fprintf('\n');
if all(diff(mean_ber_iter0) <= 0)
    fprintf('  ✓ iter0 下 mean BER 单调递降\n');
else
    fprintf('  ✗ iter0 下 mean BER 仍非单调\n');
end

%% 持久化
h_mat = fullfile(h_out_dir, 'iter_ablation_summary.mat');
save(h_mat, 'T_iter0', 'T_base', 'h_seeds', 'h_snr_list', 'h_elapsed', ...
           'err_L0_base', 'err_L0_iter0', 'err_L3_base', 'err_L3_iter0', 'mean_ber_iter0');
fprintf('\n.mat 持久化：%s\n完成\n', h_mat);
