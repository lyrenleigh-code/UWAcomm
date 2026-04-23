%% diag_D3_turbo_iter_sweep.m — SC-TDE α=+1e-2 灾难 RCA 第 3 步
%
% 目的：区分 DFE (iter=1) 失败 vs iter≥2 错误放大。
% turbo_iter sweep：{1, 2, 3, 5, 10} × 5 seed = 25 trial，所有 oracle=false。
%
% 判据：
%   iter=1 BER<5% 且单调恶化 → iter≥2 错误放大（H2 confirmed），改 turbo_equalizer_sctde
%   iter=10 最好（单调下降） → Turbo 正常，问题在上游（矛盾结果，重审 D1/D2）
%   全 iter 都 50%            → DFE iter=1 就失败，进 D4
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D3_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_alpha    = +1e-2;
h_snr      = 10;
h_seeds    = 1:5;
h_iters    = [1, 2, 3, 5, 10];
h_n_seed   = length(h_seeds);
h_n_iter   = length(h_iters);

h_ber = nan(h_n_iter, h_n_seed);

fprintf('========================================\n');
fprintf('  D3 — turbo_iter sweep（SC-TDE α=+1e-2 RCA）\n');
fprintf('  α=%+.0e, SNR=%d dB, iters=%s, seeds=%d..%d\n', ...
    h_alpha, h_snr, mat2str(h_iters), h_seeds(1), h_seeds(end));
fprintf('========================================\n\n');

h_t0 = tic;
for h_ii = 1:h_n_iter
    h_iter_val = h_iters(h_ii);
    fprintf('--- turbo_iter=%d ---\n  ', h_iter_val);

    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv = fullfile(h_out_dir, sprintf('D3_iter%d_seed%d.csv', h_iter_val, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'D3';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;

        diag_oracle_alpha = false;
        diag_oracle_h     = false;
        diag_use_ls       = false;
        diag_turbo_iter   = h_iter_val;
        diag_dump_h       = false;

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR:%s] ', h_seed, ME.message(1:min(end,30)));
            continue;
        end

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                if height(T) >= 1, h_ber(h_ii, h_di) = T.ber_coded(1); end
            catch, end
        end

        b = h_ber(h_ii, h_di) * 100;
        if b < 1, mk='.'; elseif b < 30, mk='o'; else, mk='X'; end
        fprintf('s%d=%.1f%%[%s] ', h_seed, b, mk);
    end
    fprintf('\n\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Summary
fprintf('=========== D3 结果（turbo_iter sweep）===========\n');
fprintf('  iter | mean  | median | std   | min  | max   | 灾难率\n');
fprintf('-------+-------+--------+-------+------+-------+--------\n');
mean_by_iter = nan(1, h_n_iter);
for h_ii = 1:h_n_iter
    r = h_ber(h_ii, :) * 100;
    h_dis = sum(r > 30, 'omitnan');
    mean_by_iter(h_ii) = mean(r, 'omitnan');
    fprintf('  %4d | %5.2f | %5.2f  | %5.2f | %4.1f | %5.2f | %d/%d\n', ...
        h_iters(h_ii), mean_by_iter(h_ii), median(r,'omitnan'), std(r,'omitnan'), ...
        min(r,[],'omitnan'), max(r,[],'omitnan'), h_dis, h_n_seed);
end

fprintf('\n=========== 判据 ===========\n');
m_iter1  = mean_by_iter(1);
m_iter10 = mean_by_iter(end);

if m_iter1 < 5 && m_iter10 > 30
    fprintf('  ✓ iter=1 mean=%.2f%% <5%% 而 iter=10 mean=%.2f%% >30%%\n', m_iter1, m_iter10);
    fprintf('    → iter≥2 错误放大（H2 confirmed）\n');
    fprintf('    → 下一步：修 turbo_equalizer_sctde 的 ISI 消除（新 fix spec）\n');
elseif m_iter1 < 5 && m_iter10 < 5
    fprintf('  ? iter=1 和 iter=10 都<5%% → Turbo 正常\n');
    fprintf('    → 矛盾（与 D1/D2 100%% 灾难不符），重审诊断框架\n');
elseif m_iter1 > 30 && m_iter10 > 30
    fprintf('  ✗ iter=1 就已灾难（%.2f%%）→ DFE 本身失败\n', m_iter1);
    fprintf('    → 进 D4 (GAMP→LS) 或检查 h_est 作为 DFE 初始化是否合理\n');
else
    fprintf('  ⚠ 曲线不单调：iter=%s mean=%s\n', ...
        mat2str(h_iters), mat2str(round(mean_by_iter*100)/100));
    fprintf('    → 需要可视化 + per-iter 进一步分析\n');
end

% 可视化：mean BER vs iter
try
    figure('Position',[100 100 600 400]);
    plot(h_iters, mean_by_iter, 'o-', 'LineWidth',2, 'MarkerSize',8);
    xlabel('turbo\_iter');
    ylabel('mean BER (%)');
    title(sprintf('D3: BER vs turbo\\_iter (SC-TDE, α=%+.0e, SNR=%ddB)', h_alpha, h_snr));
    grid on;
    ylim([0 60]);
    saveas(gcf, fullfile(h_out_dir, 'D3_ber_vs_iter.png'));
    fprintf('可视化已保存：%s\n', fullfile(h_out_dir, 'D3_ber_vs_iter.png'));
catch
end

fprintf('\n完成\n');
