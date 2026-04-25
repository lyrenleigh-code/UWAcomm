%% diag_sctde_fd1hz_alpha_err.m
% Phase 1.2 · 量化 SC-TDE fd=1Hz 下 α estimator 4 层偏差
%
% 上游 spec: specs/active/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md
% 上游 plan: plans/2026-04-25-sctde-fd1hz-alpha-estimator-fix.md
%
% 矩阵：15 seed × 3 SNR × default 3 行 fading（与 H4 oracle full 同）
% 4 层 α：L0 alpha_lfm_raw / L1 alpha_lfm_iter / L2 alpha_lfm_scan / L3 alpha_est
% 输出：
%   alpha_err_summary.csv (raw 数据每行 = 1 trial × 1 SNR × 1 fading)
%   alpha_err_dist.txt    (mean/std/p50/p90 |err| 分布按 SNR 分组)
%   控制台 + figure
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

% 主输出 CSV
h_csv_master = fullfile(h_out_dir, 'alpha_err_summary.csv');
if exist(h_csv_master, 'file'), delete(h_csv_master); end

fprintf('========================================\n');
fprintf('  SC-TDE fd=1Hz · Phase 1.2 · α estimator 偏差量化\n');
fprintf('  SNR=%s × seed=1..%d (%d trial × 3 fading)\n', ...
    mat2str(h_snr_list), h_n_seed, h_n_snr*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_si = 1:h_n_snr
    h_snr = h_snr_list(h_si);
    fprintf('--- SNR=%d dB ---\n  ', h_snr);
    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv_trial = fullfile(h_out_dir, sprintf('SCTDE_seed%d_snr%d_alphaErr.csv', h_seed, h_snr));
        if exist(h_csv_trial, 'file'), delete(h_csv_trial); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = h_snr;
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'fd1hz-alpha-err-phase1';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv_trial;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;
        diag_oracle_alpha              = false;   % baseline，非 oracle

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR:%s] ', h_seed, ME.identifier);
            continue;
        end

        % 单 trial CSV → 累积到 master
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
            catch ME2
                fprintf('s%d[CSV-ERR:%s] ', h_seed, ME2.identifier);
            end
        end

        fprintf('s%d ', h_seed);
        if mod(h_di, 5) == 0 && h_di < h_n_seed, fprintf('\n  '); end
    end
    fprintf('\n\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.2f min\n\n', h_elapsed/60);

%% 读累积 CSV 做分析
if ~exist(h_csv_master, 'file')
    fprintf('  ✗ master CSV 不存在，提前退出\n');
    return;
end
T = readtable(h_csv_master);
fprintf('累积 trial 行数：%d\n\n', height(T));

% 仅 fd=1Hz 行（spec 主关心）
T_fd1 = T(T.fd_hz == 1, :);
fprintf('fd=1Hz 行数：%d\n\n', height(T_fd1));

% 4 层偏差
err_L0 = T_fd1.alpha_lfm_raw  - T_fd1.doppler_rate;
err_L1 = T_fd1.alpha_lfm_iter - T_fd1.doppler_rate;
err_L2 = T_fd1.alpha_lfm_scan - T_fd1.doppler_rate;
err_L3 = T_fd1.alpha_est      - T_fd1.doppler_rate;

%% 分布表（按 SNR 分组）
h_txt = fullfile(h_out_dir, 'alpha_err_dist.txt');
fid = fopen(h_txt, 'w');
print_dist = @(label, e, snr_list, snrs, fout) print_distribution(label, e, snr_list, snrs, fout);

fprintf('\n=========== |α_err| 分布（按 SNR 分组）===========\n');
fprintf(fid, '|α_err| 分布按 SNR 分组（fd=1Hz only）\n\n');
for L_idx = 0:3
    switch L_idx
        case 0, e = err_L0; lbl = 'L0 (alpha_lfm_raw)';
        case 1, e = err_L1; lbl = 'L1 (alpha_lfm_iter)';
        case 2, e = err_L2; lbl = 'L2 (alpha_lfm_scan)';
        case 3, e = err_L3; lbl = 'L3 (alpha_est)';
    end
    print_distribution(lbl, abs(e), T_fd1.snr_db, h_snr_list, 1);
    print_distribution(lbl, abs(e), T_fd1.snr_db, h_snr_list, fid);
end
fclose(fid);
fprintf('  分布写入：%s\n', h_txt);

%% |err| 与 BER 相关性（关心 L0 和 L3）
fprintf('\n=========== |α_err| vs BER 相关性 ===========\n');
for L_idx = [0, 3]
    if L_idx == 0
        e = abs(err_L0); lbl = 'L0';
    else
        e = abs(err_L3); lbl = 'L3';
    end
    for h_si = 1:h_n_snr
        m = T_fd1.snr_db == h_snr_list(h_si);
        ev = e(m); bv = T_fd1.ber_coded(m);
        if numel(ev) >= 3
            r = corr(ev, bv, 'rows', 'complete');
            fprintf('  %s SNR=%d: corr(|err|, ber) = %+.3f, n=%d\n', ...
                lbl, h_snr_list(h_si), r, numel(ev));
        end
    end
end

%% 坏 seed 标记（baseline ber > 5%）
fprintf('\n=========== fd=1Hz 坏 seed (ber>5%%) 偏差细查 ===========\n');
for h_si = 1:h_n_snr
    m_bad = T_fd1.snr_db == h_snr_list(h_si) & T_fd1.ber_coded > 0.05;
    bad = T_fd1(m_bad, :);
    fprintf('  SNR=%d: %d 坏 seed\n', h_snr_list(h_si), height(bad));
    for k = 1:height(bad)
        fprintf('    seed=%d ber=%.2f%% | L0=%+.2e (err %+.2e) | L3=%+.2e (err %+.2e) | dop_rate=%+.2e\n', ...
            bad.seed(k), bad.ber_coded(k)*100, ...
            bad.alpha_lfm_raw(k),  bad.alpha_lfm_raw(k) - bad.doppler_rate(k), ...
            bad.alpha_est(k),       bad.alpha_est(k)     - bad.doppler_rate(k), ...
            bad.doppler_rate(k));
    end
end

%% Figure（|err_L0| vs BER 散点）
try
    figure('Name', 'fd=1Hz |α_err_L0| vs BER', 'Position', [100 100 900 360]);
    snr_colors = lines(h_n_snr);
    subplot(1, 2, 1);
    hold on;
    for h_si = 1:h_n_snr
        m = T_fd1.snr_db == h_snr_list(h_si);
        scatter(abs(err_L0(m)), T_fd1.ber_coded(m)*100, 50, snr_colors(h_si,:), 'filled', ...
                'DisplayName', sprintf('SNR=%d', h_snr_list(h_si)));
    end
    set(gca, 'XScale', 'log', 'YScale', 'linear');
    xlabel('|α_{lfm\_raw} - α_{true}|'); ylabel('BER coded (%)');
    title('L0 偏差 vs BER'); grid on; legend('Location', 'best');

    subplot(1, 2, 2);
    hold on;
    for h_si = 1:h_n_snr
        m = T_fd1.snr_db == h_snr_list(h_si);
        scatter(abs(err_L3(m)), T_fd1.ber_coded(m)*100, 50, snr_colors(h_si,:), 'filled', ...
                'DisplayName', sprintf('SNR=%d', h_snr_list(h_si)));
    end
    set(gca, 'XScale', 'log', 'YScale', 'linear');
    xlabel('|α_{est} - α_{true}|'); ylabel('BER coded (%)');
    title('L3 偏差 vs BER'); grid on;

    h_fig = fullfile(h_out_dir, 'alpha_err_scatter.png');
    saveas(gcf, h_fig);
    fprintf('\n散点图：%s\n', h_fig);
catch ME_fig
    fprintf('Figure 失败：%s\n', ME_fig.message);
end

%% 持久化
h_mat = fullfile(h_out_dir, 'alpha_err_summary.mat');
save(h_mat, 'T', 'T_fd1', 'err_L0', 'err_L1', 'err_L2', 'err_L3', ...
           'h_seeds', 'h_snr_list', 'h_elapsed');
fprintf('\n.mat 持久化：%s\n', h_mat);
fprintf('完成\n');

%% ============== 子函数 ==============
function print_distribution(label, abs_err, snr_col, snr_list, fout)
% 输出 |α_err| 分布按 SNR 分组到 stdout 或文件
% fout = 1 → stdout; fout = fid 文件句柄 → 写文件
fprintf(fout, '\n[%s]\n', label);
fprintf(fout, '  SNR  | mean       | median     | std        | p90        | n\n');
fprintf(fout, '-------+------------+------------+------------+------------+----\n');
for h_si = 1:length(snr_list)
    m = snr_col == snr_list(h_si);
    e = abs_err(m);
    e = e(~isnan(e));
    if isempty(e)
        fprintf(fout, '  %3d  | (n/a)\n', snr_list(h_si));
        continue;
    end
    mn = mean(e); md = median(e); sd = std(e);
    p90 = prctile(e, 90);
    fprintf(fout, '  %3d  | %.4e | %.4e | %.4e | %.4e | %d\n', ...
        snr_list(h_si), mn, md, sd, p90, numel(e));
end
end
