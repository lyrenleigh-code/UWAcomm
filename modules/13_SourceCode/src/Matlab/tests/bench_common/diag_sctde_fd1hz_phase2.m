%% diag_sctde_fd1hz_phase2.m
% Phase 2 综合诊断：LFM 峰特征 + sub-sample 消融
%
% 上游：alpha_err Phase 1.2 + iter ablation 显示 L0 偏差 deterministic
% 目的：
%   (a) C2 - 量化 LFM 峰诊断（tau_*_frac, snr_up/dn）按 seed 分布
%   (b) C1 - sub-sample on/off 对 L0 偏差贡献
% 输出：
%   p2_subsample_on.csv  / p2_subsample_off.csv
%   控制台分析 + LFM 峰按 seed 散点
%
% 矩阵：15 seed × 3 SNR（ber=20 dB）+ default 3 fading
% 对照：use_subsample = {true, false}
% 注：bench_alpha_iter = 0（基于 ablation 结论，避免 iter 干扰 L0 分析）
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

h_csv_on  = fullfile(h_out_dir, 'p2_subsample_on.csv');
h_csv_off = fullfile(h_out_dir, 'p2_subsample_off.csv');
if exist(h_csv_on,  'file'), delete(h_csv_on);  end
if exist(h_csv_off, 'file'), delete(h_csv_off); end

fprintf('========================================\n');
fprintf('  Phase 2 · LFM 峰 + sub-sample 双条件\n');
fprintf('  iter=0 · use_subsample={true,false} · 15 seed × 3 SNR × 3 fading\n');
fprintf('========================================\n\n');

h_t0 = tic;

for h_cond_idx = 1:2
    if h_cond_idx == 1
        cond_name = 'subsample-on';
        h_use_sub = true;
        h_csv_master = h_csv_on;
    else
        cond_name = 'subsample-off';
        h_use_sub = false;
        h_csv_master = h_csv_off;
    end
    fprintf('=== Condition %d/%d: %s ===\n', h_cond_idx, 2, cond_name);

    for h_si = 1:h_n_snr
        h_snr = h_snr_list(h_si);
        fprintf('--- SNR=%d ---\n  ', h_snr);
        for h_di = 1:h_n_seed
            h_seed = h_seeds(h_di);
            h_csv_trial = fullfile(h_out_dir, sprintf('p2_%s_seed%d_snr%d.csv', ...
                                                      cond_name, h_seed, h_snr));
            if exist(h_csv_trial, 'file'), delete(h_csv_trial); end

            benchmark_mode                 = true; %#ok<*NASGU>
            bench_snr_list                 = h_snr;
            bench_channel_profile          = 'custom6';
            bench_seed                     = h_seed;
            bench_stage                    = sprintf('p2-%s', cond_name);
            bench_scheme_name              = 'SC-TDE';
            bench_csv_path                 = h_csv_trial;
            bench_diag                     = struct('enable', false);
            bench_toggles                  = struct();
            bench_oracle_alpha             = false;
            bench_oracle_passband_resample = false;
            bench_use_real_doppler         = true;
            diag_oracle_alpha              = false;
            bench_alpha_iter               = 0;             % iter=0 锁定（已证明）
            bench_use_subsample            = h_use_sub;     % ★ 条件变量

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
        fprintf('\n');
    end
    fprintf('\n');
end
fprintf('总用时：%.2f min\n\n', toc(h_t0)/60);

%% 读两组数据
T_on  = readtable(h_csv_on);
T_off = readtable(h_csv_off);
T_on_fd1  = T_on(T_on.fd_hz == 1, :);
T_off_fd1 = T_off(T_off.fd_hz == 1, :);

%% C1: sub-sample 消融 ===========
fprintf('=========== C1 · sub-sample 消融（L0 |α_err|）===========\n');
fprintf('  SNR  | sub=ON mean | sub=OFF mean | Δ\n');
fprintf('-------+-------------+--------------+--------\n');
for h_si = 1:h_n_snr
    m1 = T_on_fd1.snr_db == h_snr_list(h_si);
    m2 = T_off_fd1.snr_db == h_snr_list(h_si);
    e1 = mean(abs(T_on_fd1.alpha_lfm_raw(m1)  - T_on_fd1.doppler_rate(m1)));
    e2 = mean(abs(T_off_fd1.alpha_lfm_raw(m2) - T_off_fd1.doppler_rate(m2)));
    fprintf('  %3d  | %.4e | %.4e  | %+.2e\n', h_snr_list(h_si), e1, e2, e2-e1);
end

fprintf('\n=========== C1 · BER 对比 ===========\n');
fprintf('  SNR  | sub=ON mean BER | sub=OFF mean BER | Δ\n');
fprintf('-------+-----------------+------------------+------\n');
for h_si = 1:h_n_snr
    m1 = T_on_fd1.snr_db == h_snr_list(h_si);
    m2 = T_off_fd1.snr_db == h_snr_list(h_si);
    b1 = mean(T_on_fd1.ber_coded(m1)) * 100;
    b2 = mean(T_off_fd1.ber_coded(m2)) * 100;
    fprintf('  %3d  | %12.2f%% | %13.2f%% | %+5.2f\n', h_snr_list(h_si), b1, b2, b2-b1);
end

%% C2: LFM 峰诊断（base sub=ON 条件）===========
fprintf('\n=========== C2 · LFM 峰诊断（fd=1Hz, sub=ON）===========\n');
fprintf('  SNR  | tau_up_frac mean | tau_dn_frac mean | snr_up mean | snr_dn mean | dtau_resid_s mean\n');
fprintf('-------+------------------+------------------+-------------+-------------+--------------------\n');
for h_si = 1:h_n_snr
    m = T_on_fd1.snr_db == h_snr_list(h_si);
    t = T_on_fd1(m, :);
    fprintf('  %3d  | %16.4f | %16.4f | %11.2f | %11.2f | %.4e\n', h_snr_list(h_si), ...
        mean(t.diag_tau_up_frac), mean(t.diag_tau_dn_frac), ...
        mean(t.diag_snr_up), mean(t.diag_snr_dn), mean(t.diag_dtau_resid_s));
end

fprintf('\n=========== C2 · 坏 vs 好 seed 的 LFM 峰特征对比 ===========\n');
% 用 SNR=20 数据
m20 = T_on_fd1.snr_db == 20;
T20 = T_on_fd1(m20, :);
m_bad  = T20.ber_coded > 0.05;
m_good = T20.ber_coded <= 0.05;
fprintf('  Group | n | tau_up_frac mean (std) | tau_dn_frac mean (std) | snr_up mean | snr_dn mean | err_L0 mean\n');
fprintf('--------+---+-------------------------+-------------------------+-------------+-------------+--------------\n');
print_group = @(name, t) fprintf('  %-6s | %d | %+.4f (%.4f) | %+.4f (%.4f) | %10.2f | %10.2f | %+.3e\n', ...
    name, height(t), ...
    mean(t.diag_tau_up_frac), std(t.diag_tau_up_frac), ...
    mean(t.diag_tau_dn_frac), std(t.diag_tau_dn_frac), ...
    mean(t.diag_snr_up), mean(t.diag_snr_dn), ...
    mean(t.alpha_lfm_raw - t.doppler_rate));
print_group('bad',  T20(m_bad, :));
print_group('good', T20(m_good, :));

%% Figure：tau_up/dn frac 分布 + snr 分布
try
    figure('Name', 'Phase 2 LFM peak diagnostic', 'Position', [100 100 1200 700]);

    % SNR=20 散点：tau_up_frac vs tau_dn_frac，染色 = ber
    subplot(2,2,1);
    scatter(T20.diag_tau_up_frac, T20.diag_tau_dn_frac, 80, T20.ber_coded*100, 'filled');
    cb = colorbar; cb.Label.String = 'BER %';
    xlabel('tau\_up\_frac'); ylabel('tau\_dn\_frac');
    title('SNR=20: subsample peak 偏移 vs BER');
    grid on; axis square;

    % alpha_lfm_raw err vs tau_up_frac 散点
    subplot(2,2,2);
    err_L0_20 = T20.alpha_lfm_raw - T20.doppler_rate;
    scatter(T20.diag_tau_up_frac, err_L0_20, 80, T20.ber_coded*100, 'filled');
    cb = colorbar; cb.Label.String = 'BER %';
    xlabel('tau\_up\_frac'); ylabel('err\_L0 = α\_lfm\_raw - dop\_rate');
    title('SNR=20: peak frac vs L0 err');
    grid on;

    % snr_up vs snr_dn
    subplot(2,2,3);
    scatter(T20.diag_snr_up, T20.diag_snr_dn, 80, T20.ber_coded*100, 'filled');
    cb = colorbar; cb.Label.String = 'BER %';
    xlabel('snr\_up'); ylabel('snr\_dn');
    title('SNR=20: LFM peak SNR (peak/median)');
    grid on; axis square;

    % subsample-off 对比 err 分布
    subplot(2,2,4);
    err_on  = T_on_fd1.alpha_lfm_raw  - T_on_fd1.doppler_rate;
    err_off = T_off_fd1.alpha_lfm_raw - T_off_fd1.doppler_rate;
    histogram(err_on,  20, 'FaceAlpha', 0.5, 'DisplayName', 'sub=ON');
    hold on;
    histogram(err_off, 20, 'FaceAlpha', 0.5, 'DisplayName', 'sub=OFF');
    xlabel('err\_L0 = α\_lfm\_raw - dop\_rate'); ylabel('count');
    title('L0 偏差分布对比');
    legend('Location', 'best'); grid on;

    h_fig = fullfile(h_out_dir, 'phase2_lfm_peak_subsample.png');
    saveas(gcf, h_fig);
    fprintf('\n图：%s\n', h_fig);
catch ME_fig
    fprintf('Figure 失败：%s\n', ME_fig.message);
end

%% 持久化
h_mat = fullfile(h_out_dir, 'phase2_summary.mat');
save(h_mat, 'T_on', 'T_off', 'h_seeds', 'h_snr_list');
fprintf('\n.mat 持久化：%s\n完成\n', h_mat);
