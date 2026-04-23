%% verify_alpha_sweep.m — SC-TDE 删 post-CFO 后 α 扫描 + α=0 SNR Gate
%
% Spec : specs/active/2026-04-24-sctde-remove-post-cfo-compensation.md
% Plan : plans/sctde-remove-post-cfo.md (Step 2)
% 版本 : V1.0.0 (2026-04-24)
%
% 目的（合 V1+V2）：
%   V1 α 工作范围：α ∈ {±1e-4, ±1e-3, +3e-3, ±1e-2, +3e-2} × seed 1..5 × SNR=10
%   V2 α=0 D0b gate：α=0 × seed 1..5 × SNR=[10, 15, 20]（确认改动不破坏 α=0 场景）
%
% 通过判据（plan + spec 接受准则）：
%   V1: |α|≤1e-2 mean BER ≤ 1%，α=+3e-2 物理极限可放宽至 ≤30%
%   V2: α=0 全 3 SNR mean BER ≤ 0.5%（SNR=20 ≤0.1%）
%
% 预估耗时：~5 min（50 trial × ~5s）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'verify_alpha_sweep_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

%% 扫描矩阵
% V1: α 扫描（SNR=10）
h_alpha_v1 = [+1e-4, +1e-3, +3e-3, +1e-2, +3e-2, -1e-3, -1e-2, -1e-4];
% V2: α=0 SNR gate
h_snr_v2   = [10, 15, 20];
% 公共
h_seeds    = [1, 2, 3, 4, 5];
h_n_seed   = length(h_seeds);

h_n_v1 = length(h_alpha_v1);
h_n_v2 = length(h_snr_v2);

h_ber_v1 = nan(h_n_v1, h_n_seed);       % (α, seed) @ SNR=10
h_ber_v2 = nan(h_n_v2, h_n_seed);       % (SNR, seed) @ α=0
h_alpha_est_v1 = nan(h_n_v1, h_n_seed);

fprintf('========================================\n');
fprintf('  verify_alpha_sweep — SC-TDE post-CFO fix 验证\n');
fprintf('  V1: α ∈ %s × SNR=10 × 5 seed\n', mat2str(h_alpha_v1));
fprintf('  V2: α=0 × SNR=%s × 5 seed\n', mat2str(h_snr_v2));
fprintf('  总 %d trial\n', h_n_v1*h_n_seed + h_n_v2*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;

%% === V1: α 扫描 @ SNR=10 ===
fprintf('--- V1: α 扫描 @ SNR=10 ---\n');
for h_ai = 1:h_n_v1
    h_alpha = h_alpha_v1(h_ai);
    fprintf('  α=%+.0e: ', h_alpha);

    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv  = fullfile(h_out_dir, sprintf('v1_a%+.0e_seed%d.csv', h_alpha, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true;            %#ok<*NASGU>
        bench_snr_list                 = 10;
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'verify_v1';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;

        diag_oracle_alpha       = false;
        diag_oracle_h           = false;
        diag_use_ls             = false;
        diag_turbo_iter         = [];
        diag_dump_h             = false;
        diag_dump_signal        = false;
        diag_dump_rxfilt        = false;
        diag_enable_legacy_cfo  = false;  % 反义 toggle，默认关 = 新行为

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR:%s] ', h_seed, ME.identifier);
            continue;
        end

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                if height(T) >= 1
                    h_ber_v1(h_ai, h_di)       = T.ber_coded(1);
                    if ismember('alpha_est', T.Properties.VariableNames)
                        h_alpha_est_v1(h_ai, h_di) = T.alpha_est(1);
                    end
                end
            catch
            end
        end

        b = h_ber_v1(h_ai, h_di) * 100;
        if b < 1,       mk='.';
        elseif b < 10,  mk='o';
        elseif b < 30,  mk='O';
        else,           mk='X';
        end
        fprintf('s%d=%.2f%%[%s] ', h_seed, b, mk);
    end
    fprintf('\n');
end

%% === V2: α=0 SNR gate ===
fprintf('\n--- V2: α=0 SNR gate ---\n');
for h_si = 1:h_n_v2
    h_snr = h_snr_v2(h_si);
    fprintf('  SNR=%d: ', h_snr);

    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv  = fullfile(h_out_dir, sprintf('v2_snr%d_seed%d.csv', h_snr, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true;
        bench_snr_list                 = h_snr;
        bench_fading_cfgs              = { 'nominal', 'static', 0, 0 };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'verify_v2';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;

        diag_oracle_alpha       = false;
        diag_oracle_h           = false;
        diag_use_ls             = false;
        diag_turbo_iter         = [];
        diag_dump_h             = false;
        diag_dump_signal        = false;
        diag_dump_rxfilt        = false;
        diag_enable_legacy_cfo  = false;

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR:%s] ', h_seed, ME.identifier);
            continue;
        end

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                if height(T) >= 1, h_ber_v2(h_si, h_di) = T.ber_coded(1); end
            catch
            end
        end

        b = h_ber_v2(h_si, h_di) * 100;
        if b < 0.5,     mk='.';
        elseif b < 2,   mk='o';
        else,           mk='X';
        end
        fprintf('s%d=%.3f%%[%s] ', h_seed, b, mk);
    end
    fprintf('\n');
end

h_elapsed = toc(h_t0);
fprintf('\n总用时：%.1f min\n\n', h_elapsed/60);

%% === Summary V1 ===
fprintf('========== V1 汇总（SNR=10）==========\n');
fprintf('  α           | mean BER   | std     | α_est mean   | seeds\n');
fprintf('--------------+------------+---------+--------------+------\n');
for h_ai = 1:h_n_v1
    r  = h_ber_v1(h_ai, :) * 100;
    ae = h_alpha_est_v1(h_ai, :);
    fprintf('  α=%+.0e  | %6.2f%%   | %5.2f%%  | %+.3e    | %d\n', ...
        h_alpha_v1(h_ai), mean(r,'omitnan'), std(r,'omitnan'), ...
        mean(ae,'omitnan'), sum(~isnan(r)));
end

%% === Summary V2 ===
fprintf('\n========== V2 汇总（α=0 D0b gate）==========\n');
fprintf('  SNR  | mean BER   | std     | seeds\n');
fprintf('-------+------------+---------+------\n');
for h_si = 1:h_n_v2
    r = h_ber_v2(h_si, :) * 100;
    fprintf('  %3d  | %6.3f%%   | %5.3f%%  | %d\n', ...
        h_snr_v2(h_si), mean(r,'omitnan'), std(r,'omitnan'), sum(~isnan(r)));
end

%% === 判据自动评估 ===
fprintf('\n========== 判据自动评估 ==========\n');

% V1 判据
v1_small_alpha_pass = true;
for h_ai = 1:h_n_v1
    if abs(h_alpha_v1(h_ai)) <= 1e-2
        m = mean(h_ber_v1(h_ai,:)*100, 'omitnan');
        if m > 1
            fprintf('  [V1 FAIL] α=%+.0e mean BER=%.2f%% > 1%%\n', h_alpha_v1(h_ai), m);
            v1_small_alpha_pass = false;
        end
    end
end
if v1_small_alpha_pass
    fprintf('  [V1 PASS] |α|≤1e-2 全部 mean BER ≤ 1%%\n');
end
% α=+3e-2 物理极限放宽至 30%
h_big_idx = find(abs(h_alpha_v1 - 3e-2) < 1e-8, 1);
if ~isempty(h_big_idx)
    m = mean(h_ber_v1(h_big_idx,:)*100, 'omitnan');
    if m > 30
        fprintf('  [V1 BIG FAIL] α=+3e-2 mean BER=%.2f%% > 30%% (物理极限放宽版)\n', m);
    else
        fprintf('  [V1 BIG OK] α=+3e-2 mean BER=%.2f%% ≤ 30%% (物理极限)\n', m);
    end
end

% V2 判据
v2_pass = true;
for h_si = 1:h_n_v2
    m = mean(h_ber_v2(h_si,:)*100, 'omitnan');
    th = 0.5;
    if h_snr_v2(h_si) == 20, th = 0.1; end
    if m > th
        fprintf('  [V2 FAIL] SNR=%d mean BER=%.3f%% > %.2f%%\n', h_snr_v2(h_si), m, th);
        v2_pass = false;
    end
end
if v2_pass
    fprintf('  [V2 PASS] α=0 全 SNR 过 D0b gate\n');
end

fprintf('\n');
if v1_small_alpha_pass && v2_pass
    fprintf('  *** 整体 PASS：可进 V3 时变路径回归（手跑 test_sctde_timevarying.m）***\n');
else
    fprintf('  *** 部分 FAIL：需回滚或诊断 ***\n');
end
fprintf('\n');

%% === 保存 mat ===
h_mat_path = fullfile(h_out_dir, 'verify_alpha_sweep_results.mat');
save(h_mat_path, 'h_alpha_v1', 'h_snr_v2', 'h_seeds', ...
    'h_ber_v1', 'h_ber_v2', 'h_alpha_est_v1', 'h_elapsed');
fprintf('已保存结果到 %s\n', h_mat_path);

%% === 可视化 ===
try
    figure('Name','verify_alpha_sweep','Position',[100 100 1000 400]);
    subplot(1,2,1);
    semilogy(h_alpha_v1, mean(h_ber_v1,2,'omitnan')*100 + 1e-3, 'o-','LineWidth',1.5);
    grid on; xlabel('\alpha'); ylabel('mean BER (%)');
    title(sprintf('V1: α 扫描 @ SNR=10 (5 seed, %d α)', h_n_v1));
    yline(1, '--r', '1%');
    subplot(1,2,2);
    semilogy(h_snr_v2, mean(h_ber_v2,2,'omitnan')*100 + 1e-4, 's-','LineWidth',1.5);
    grid on; xlabel('SNR (dB)'); ylabel('mean BER (%)');
    title(sprintf('V2: α=0 SNR gate (5 seed, %d SNR)', h_n_v2));
    yline(0.5, '--r', '0.5%'); yline(0.1, '--g', '0.1%');
    saveas(gcf, fullfile(h_out_dir, 'verify_alpha_sweep.png'));
    fprintf('已保存图到 verify_alpha_sweep.png\n');
catch ME
    fprintf('绘图失败（可忽略）：%s\n', ME.message);
end
