%% diag_sctde_fd1hz_monte_carlo.m
% SC-TDE fd=1Hz 非单调 BER vs SNR 调研 — 阶段 1 多 seed Monte Carlo
%
% spec : specs/active/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md
% plan : plans/sctde-fd1hz-nonmonotonic-investigation.md
% 模板 : diag_5scheme_monte_carlo.m
%
% 矩阵：SC-TDE × fd=1Hz Jakes × SNR ∈ {10,15,20} × seed ∈ 1:15 = 45 trial
%   ftype='slow', fd_hz=1, dop_rate=1/fc=8.33e-5（fc=12000）
%
% 目的：判定 spec H1（Turbo+BEM 稀有触发 vs 普遍崩坏）
%   - 灾难率 < 15% 且 mean BER 单调降 → known limitation 归档
%   - 灾难率 > 30% → 进 spec 阶段 2 H2/H3/H4 隔离
%
% 灾难阈值：>5%（spec line 60，比 diag_5scheme 的 30% 严，放大稀有触发可见度）
%
% 版本：V1.0.0（2026-04-24）

clear functions; clear; close all; clc;

%% 参数
h_this_dir  = fileparts(mfilename('fullpath'));
h_tests_dir = fileparts(h_this_dir);
h_runner    = fullfile(h_tests_dir, 'SC-TDE', 'test_sctde_timevarying.m');
h_out_dir   = fullfile(h_this_dir, 'diag_sctde_fd1hz_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

h_fc       = 12000;                              % runner 内 fc（test_sctde_timevarying.m L46）
h_snr_list = [10, 15, 20];
h_seeds    = 1:15;
h_n_snr    = length(h_snr_list);
h_n_seed   = length(h_seeds);
% 不覆盖 bench_fading_cfgs → runner 走 default 3 行，fd=1Hz 是 fi=2
% rng seed 依赖 fi 行号，必须保证与 V5.4 验证一致（阶段 1.5 已证实）

% 灾难阈值（百分比）
h_thresh_disaster = 5;     % >5% 视为灾难（spec）
h_thresh_severe   = 30;    % >30% 视为严重（diag_5scheme 一致，二级判定）

h_ber = nan(h_n_snr, h_n_seed);

fprintf('========================================\n');
fprintf('  SC-TDE fd=1Hz 非单调调研 · 阶段 1 MC V2\n');
fprintf('  fading=default 3 行（筛 fd=1Hz = fi=2）\n');
fprintf('  SNR=%s, seed=1..%d (%d trial × 3 fading)\n', mat2str(h_snr_list), h_n_seed, h_n_snr*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_si = 1:h_n_snr
    h_snr = h_snr_list(h_si);
    fprintf('--- SNR=%d dB ---\n  ', h_snr);
    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv = fullfile(h_out_dir, sprintf('SCTDE_seed%d_snr%d.csv', h_seed, h_snr));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = h_snr;
        % 故意不设 bench_fading_cfgs：走 default 3 行，fd=1Hz 即 fi=2
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'fd1hz-nonmono-MC-V2';
        bench_scheme_name              = 'SC-TDE';
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
                % 筛 fd_hz==1 行（fi=2 trial）
                h_idx = find(T.fd_hz == 1, 1);
                if ~isempty(h_idx)
                    h_ber(h_si, h_di) = T.ber_coded(h_idx);
                end
            catch
            end
        end

        b = h_ber(h_si, h_di) * 100;
        if b < h_thresh_disaster
            mk = '.';
        elseif b < h_thresh_severe
            mk = 'o';
        else
            mk = 'X';
        end
        fprintf('s%d=%.2f%%[%s] ', h_seed, b, mk);
        if mod(h_di, 5) == 0 && h_di < h_n_seed, fprintf('\n  '); end
    end
    fprintf('\n\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Summary 表
fprintf('=========== BER 分布统计（fd=1Hz Jakes）===========\n');
fprintf('  SNR  | mean   | median | std    | min   | max    | 灾难率(>%d%%) | 严重率(>%d%%)\n', ...
        h_thresh_disaster, h_thresh_severe);
fprintf('-------+--------+--------+--------+-------+--------+--------------+--------------\n');
for h_si = 1:h_n_snr
    r = h_ber(h_si, :) * 100;
    h_dis = sum(r > h_thresh_disaster, 'omitnan');
    h_sev = sum(r > h_thresh_severe,   'omitnan');
    fprintf('  %3d  | %6.2f | %6.2f | %6.2f | %5.2f | %6.2f | %2d/%d (%4.1f%%) | %2d/%d (%4.1f%%)\n', ...
        h_snr_list(h_si), ...
        mean(r,'omitnan'), median(r,'omitnan'), std(r,'omitnan'), ...
        min(r,[],'omitnan'), max(r,[],'omitnan'), ...
        h_dis, h_n_seed, 100*h_dis/h_n_seed, ...
        h_sev, h_n_seed, 100*h_sev/h_n_seed);
end

%% 灾难案例 seed 列表
fprintf('\n=========== 灾难案例 seed 列表 (BER > %d%%) ===========\n', h_thresh_disaster);
for h_si = 1:h_n_snr
    r = h_ber(h_si, :) * 100;
    h_idx = find(r > h_thresh_disaster);
    if isempty(h_idx)
        fprintf('  SNR=%d: 无灾难\n', h_snr_list(h_si));
    else
        h_seed_list = h_seeds(h_idx);
        h_ber_list  = r(h_idx);
        fprintf('  SNR=%d: ', h_snr_list(h_si));
        for h_k = 1:length(h_idx)
            fprintf('s%d=%.2f%% ', h_seed_list(h_k), h_ber_list(h_k));
        end
        fprintf('\n');
    end
end

%% 单调性检查（mean BER 应 SNR 升 → BER 降）
fprintf('\n=========== 单调性检查 ===========\n');
h_mean_ber = nan(1, h_n_snr);
for h_si = 1:h_n_snr
    h_mean_ber(h_si) = mean(h_ber(h_si, :) * 100, 'omitnan');
end
fprintf('  mean BER = ');
for h_si = 1:h_n_snr
    fprintf('SNR=%d:%.2f%%  ', h_snr_list(h_si), h_mean_ber(h_si));
end
fprintf('\n');
if all(diff(h_mean_ber) <= 0)
    fprintf('  ✓ mean BER 单调递降\n');
else
    fprintf('  ✗ mean BER 非单调（违反 SNR 升则 BER 降）\n');
end

%% H1 判定
fprintf('\n=========== H1 判定 ===========\n');
h_max_dis_rate = 0;
for h_si = 1:h_n_snr
    r = h_ber(h_si, :) * 100;
    h_dis = sum(r > h_thresh_disaster, 'omitnan');
    h_rate = 100*h_dis/h_n_seed;
    if h_rate > h_max_dis_rate, h_max_dis_rate = h_rate; end
end
if h_max_dis_rate < 15 && all(diff(h_mean_ber) <= 0)
    fprintf('  ✓ H1 confirmed: 灾难率 %.1f%% < 15%% 且 mean 单调，归 known limitation\n', h_max_dis_rate);
elseif h_max_dis_rate > 30
    fprintf('  ✗ H1 falsified: 灾难率 %.1f%% > 30%%，进 spec 阶段 2（H2/H3/H4 隔离）\n', h_max_dis_rate);
else
    fprintf('  🟡 中间区: 灾难率 %.1f%%（15-30%%），阶段 2 选择性做（先 H4 oracle α）\n', h_max_dis_rate);
end

%% 持久化矩阵（供后续分析）
h_mat = fullfile(h_out_dir, 'mc_summary.mat');
save(h_mat, 'h_ber', 'h_snr_list', 'h_seeds', 'h_elapsed', ...
            'h_thresh_disaster', 'h_thresh_severe', 'h_mean_ber');
fprintf('\n矩阵已保存：%s\n', h_mat);

fprintf('\n完成\n');
