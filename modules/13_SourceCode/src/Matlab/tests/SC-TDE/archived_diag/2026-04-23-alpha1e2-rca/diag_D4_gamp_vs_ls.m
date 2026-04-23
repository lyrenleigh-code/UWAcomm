%% diag_D4_gamp_vs_ls.m — SC-TDE α=+1e-2 灾难 RCA 第 4 步
%
% 目的：换掉 GAMP 用 LS（Tikhonov ridge=1e-3），判断 GAMP 发散是否独有。
% 额外：dump h_est 的幅度/相位，对比 oracle h_sym，量化估计偏差。
%
% 配置：α=+1e-2 / SNR=10 / custom6 / static / seed 1..5
% 矩阵：{GAMP, LS} × 5 seed = 10 trial，diag_dump_h=true（每组首 seed 打印 h）
%
% 判据：
%   LS mean<5%, GAMP>30%   → GAMP 发散（建议加 guard 或默认 LS）
%   LS 也>30%              → 估计器方法无关，进 D5 扩展（同步/定时/帧提取）
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D4_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_alpha  = +1e-2;
h_snr    = 10;
h_seeds  = 1:5;
h_n_seed = length(h_seeds);

h_groups = {
    'GAMP',  false;
    'LS',    true;
};
h_n_grp = size(h_groups, 1);

h_ber = nan(h_n_grp, h_n_seed);

fprintf('========================================\n');
fprintf('  D4 — GAMP vs LS diag（SC-TDE α=+1e-2 RCA）\n');
fprintf('  α=%+.0e, SNR=%d dB, seeds=%d..%d\n', h_alpha, h_snr, h_seeds(1), h_seeds(end));
fprintf('========================================\n\n');

h_t0 = tic;
for h_gi = 1:h_n_grp
    h_group_name = h_groups{h_gi, 1};
    h_use_ls     = h_groups{h_gi, 2};
    fprintf('--- %s (use_ls=%d) ---\n  ', h_group_name, h_use_ls);

    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv = fullfile(h_out_dir, sprintf('D4_%s_seed%d.csv', h_group_name, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'D4';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;

        diag_oracle_alpha = false;
        diag_oracle_h     = false;
        diag_use_ls       = h_use_ls;
        diag_turbo_iter   = [];
        diag_dump_h       = (h_di == 1);   % 每组首 seed 打印 h 对比

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR:%s] ', h_seed, ME.message(1:min(end,30)));
            continue;
        end

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                if height(T) >= 1, h_ber(h_gi, h_di) = T.ber_coded(1); end
            catch, end
        end

        b = h_ber(h_gi, h_di) * 100;
        if b < 1, mk='.'; elseif b < 30, mk='o'; else, mk='X'; end
        fprintf('s%d=%.1f%%[%s] ', h_seed, b, mk);
    end
    fprintf('\n\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Summary
fprintf('=========== D4 结果（α=+1e-2, SNR=%d dB）===========\n', h_snr);
fprintf('  estimator | mean  | median | std   | min  | max   | 灾难率\n');
fprintf('------------+-------+--------+-------+------+-------+--------\n');
for h_gi = 1:h_n_grp
    r = h_ber(h_gi, :) * 100;
    h_dis = sum(r > 30, 'omitnan');
    fprintf('  %-9s | %5.2f | %5.2f  | %5.2f | %4.1f | %5.2f | %d/%d\n', ...
        h_groups{h_gi,1}, ...
        mean(r,'omitnan'), median(r,'omitnan'), std(r,'omitnan'), ...
        min(r,[],'omitnan'), max(r,[],'omitnan'), ...
        h_dis, h_n_seed);
end

fprintf('\n=========== 判据 ===========\n');
m_gamp = mean(h_ber(1,:)*100,'omitnan');
m_ls   = mean(h_ber(2,:)*100,'omitnan');
fprintf('  GAMP mean: %.2f%%\n', m_gamp);
fprintf('  LS   mean: %.2f%%\n', m_ls);

if m_ls < 5 && m_gamp > 30
    fprintf('  ✓ LS 恢复、GAMP 灾难 → GAMP 发散是主因\n');
    fprintf('    → 下一步：SC-TDE 加 GAMP divergence guard 或默认切 LS（新 fix spec）\n');
elseif m_ls > 30 && m_gamp > 30
    fprintf('  ✗ LS 和 GAMP 都灾难 → 估计器方法无关\n');
    fprintf('    → 可能原因：rx_sym_recv 本身含错（定时/同步/CFO），而非 h 估计\n');
    fprintf('    → 进 D5 扩展（定时层/帧提取 diag，本 spec 未覆盖需新 spec）\n');
elseif m_ls < 5 && m_gamp < 5
    fprintf('  ? 两者都能 work → 与 D2/D3 矛盾（重审）\n');
else
    fprintf('  ⚠ LS=%.2f%% / GAMP=%.2f%% 中间状态\n', m_ls, m_gamp);
end

fprintf('\n完成\n');
