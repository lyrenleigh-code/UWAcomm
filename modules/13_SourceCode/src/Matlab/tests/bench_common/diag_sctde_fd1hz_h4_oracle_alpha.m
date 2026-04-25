%% diag_sctde_fd1hz_h4_oracle_alpha.m
% 阶段 2 · H4 Oracle α 隔离
%
% spec: specs/active/2026-04-24-sctde-fd1hz-nonmonotonic-investigation.md
% 前置: diag_sctde_fd1hz_monte_carlo.m V2 已跑，得 baseline
%
% 坏 seed: s5 / s11 / s12 / s15（三 SNR 均 >5% 灾难）
%
% 实验：4 坏 seed × 3 SNR × diag_oracle_alpha=true
%
% 判定：
%   oracle 下 BER 大幅改善（>50% 相对下降）→ H4 confirmed，α estimator 偏差是根因
%   oracle 下 BER 持平或微改 → H4 排除，转 H2/H3 隔离
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
h_seeds    = [5, 11, 12, 15];   % 阶段 1 V2 三 SNR 均灾难的稳定坏 seed
h_n_snr    = length(h_snr_list);
h_n_seed   = length(h_seeds);

% Baseline（从阶段 1 V2 mc_summary.mat 读）
h_mat_prev = fullfile(h_out_dir, 'mc_summary.mat');
h_baseline = nan(h_n_snr, h_n_seed);
if exist(h_mat_prev, 'file')
    L = load(h_mat_prev, 'h_ber', 'h_seeds', 'h_snr_list');
    for h_si = 1:h_n_snr
        for h_di = 1:h_n_seed
            h_si_prev = find(L.h_snr_list == h_snr_list(h_si), 1);
            h_di_prev = find(L.h_seeds == h_seeds(h_di), 1);
            if ~isempty(h_si_prev) && ~isempty(h_di_prev)
                h_baseline(h_si, h_di) = L.h_ber(h_si_prev, h_di_prev);
            end
        end
    end
    fprintf('[Baseline loaded from mc_summary.mat]\n');
else
    fprintf('[WARN] baseline mat 未找到，只跑 oracle\n');
end

h_ber_oracle = nan(h_n_snr, h_n_seed);

fprintf('========================================\n');
fprintf('  SC-TDE fd=1Hz · 阶段 2 · H4 Oracle α\n');
fprintf('  坏 seed=%s, SNR=%s (%d trial)\n', ...
    mat2str(h_seeds), mat2str(h_snr_list), h_n_snr*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_si = 1:h_n_snr
    h_snr = h_snr_list(h_si);
    fprintf('--- SNR=%d dB ---\n  ', h_snr);
    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv = fullfile(h_out_dir, sprintf('SCTDE_seed%d_snr%d_oracleA.csv', h_seed, h_snr));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = h_snr;
        % 不设 bench_fading_cfgs → default 3 行，fd=1Hz 是 fi=2
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'fd1hz-H4-oracle-alpha';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;       % bench 层不用，H4 用 runner 内 diag
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;
        diag_oracle_alpha              = true;        % 核心开关：runner L330-335

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR:%s] ', h_seed, ME.message(1:min(end,30)));
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
        if b < 5, mk = '.'; elseif b < 30, mk = 'o'; else, mk = 'X'; end
        fprintf('s%d=%.2f%%[%s] ', h_seed, b, mk);
    end
    fprintf('\n\n');
end
h_elapsed = toc(h_t0);
fprintf('用时：%.2f min\n\n', h_elapsed/60);

%% 对比表
fprintf('=========== Baseline vs Oracle α 对比 ===========\n');
fprintf('  SNR  | seed | baseline BER | oracle BER | Δ(pp)   | 相对\n');
fprintf('-------+------+--------------+------------+---------+--------\n');
h_improved = 0;
h_total    = 0;
for h_si = 1:h_n_snr
    for h_di = 1:h_n_seed
        b_base = h_baseline(h_si, h_di) * 100;
        b_orac = h_ber_oracle(h_si, h_di) * 100;
        if isnan(b_base) || isnan(b_orac), continue; end
        d = b_orac - b_base;
        if b_base > 0
            rel = d / b_base * 100;
            rel_str = sprintf('%+.0f%%', rel);
        else
            rel_str = '--';
        end
        if b_base > 5 && b_orac < b_base * 0.5
            tag = '↓↓'; h_improved = h_improved + 1;
        elseif b_base > 5 && b_orac < b_base * 0.8
            tag = '↓';
        elseif b_orac > b_base * 1.2
            tag = '↑';
        else
            tag = '=';
        end
        h_total = h_total + 1;
        fprintf('  %3d  | s%-3d | %11.2f%% | %9.2f%% | %+7.2f | %s %s\n', ...
            h_snr_list(h_si), h_seeds(h_di), b_base, b_orac, d, rel_str, tag);
    end
end

%% H4 判定
fprintf('\n=========== H4 判定 ===========\n');
if h_total == 0
    fprintf('  [WARN] 无有效对比数据\n');
elseif h_improved / h_total > 0.5
    fprintf('  ✓ H4 confirmed: %d/%d 坏 trial oracle α 下 BER 下降 >50%%（相对）\n', h_improved, h_total);
    fprintf('  → α estimator 偏差是 fd=1Hz 非单调根因\n');
    fprintf('  → 下一步：fix α estimator 或调整训练精估门禁\n');
else
    fprintf('  ✗ H4 排除: 只有 %d/%d 坏 trial oracle 下明显改善\n', h_improved, h_total);
    fprintf('  → α 不是根因，转 H2（BEM Q 阶）或 H3（nv_post）隔离\n');
end

%% 持久化
h_mat = fullfile(h_out_dir, 'h4_oracle_alpha.mat');
save(h_mat, 'h_ber_oracle', 'h_baseline', 'h_seeds', 'h_snr_list', 'h_elapsed');
fprintf('\n矩阵已保存：%s\n\n完成\n', h_mat);
