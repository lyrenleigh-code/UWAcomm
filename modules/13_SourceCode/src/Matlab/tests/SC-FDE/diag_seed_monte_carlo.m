%% diag_seed_monte_carlo.m
% Phase J：30 seed Monte Carlo — 测 17% 灾难率是否是真实统计量
%
% 之前 5 seed (42/137/256/511/1024) 中 1 个出灾难（17%），可能：
%   - 真 17%（系统普遍脆弱）
%   - 远 < 17%（seed=1024 是离群）
%   - 远 > 17%（更糟）
%
% 设计：
%   α ∈ {-1e-2, +1e-2}
%   SNR = 10 dB（已知受灾点）
%   seed ∈ 1:30
%   共 60 trial
%
% 判定：
%   - 单峰分布（mean ≈ median，std 小）→ 健康统计涨落
%   - 双峰分布（一群 ~0%、一群 ~50%）→ deterministic 灾难，bug 性质确认
%
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_monte_carlo_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

h_alpha_list = [-1e-2, +1e-2];
h_snr        = 10;
h_seed_list  = 1:30;
h_n_alpha    = length(h_alpha_list);
h_n_seed     = length(h_seed_list);

h_ber = nan(h_n_alpha, h_n_seed);

fprintf('========================================\n');
fprintf('  Monte Carlo: 30 seed × 2 α × SNR=10 dB\n');
fprintf('========================================\n\n');

h_t0 = tic;
for h_ai = 1:h_n_alpha
    h_alpha_val = h_alpha_list(h_ai);
    fprintf('--- α=%+.0e ---\n', h_alpha_val);
    for h_di = 1:h_n_seed
        h_seed = h_seed_list(h_di);
        h_csv_path = fullfile(h_out_dir, sprintf('a%+g_seed%d.csv', h_alpha_val, h_seed));
        if exist(h_csv_path, 'file'), delete(h_csv_path); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha_val), 'static', 0, h_alpha_val, 1024, 128, 4 };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'diag';
        bench_scheme_name              = 'SC-FDE';
        bench_csv_path                 = h_csv_path;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('  seed=%2d ERR: %s\n', h_seed, ME.message);
            continue;
        end

        if exist(h_csv_path, 'file')
            try
                h_T = readtable(h_csv_path);
                if height(h_T) >= 1
                    h_ber(h_ai, h_di) = h_T.ber_coded(1);
                end
            catch
            end
        end

        % 紧凑进度（每 10 seed 一行）
        if mod(h_di, 10) == 1
            fprintf('  ');
        end
        h_b = h_ber(h_ai, h_di) * 100;
        if h_b < 1, h_mark = '.';
        elseif h_b < 30, h_mark = 'o';
        else h_mark = 'X'; end
        fprintf('s%02d=%5.1f%%[%s] ', h_seed, h_b, h_mark);
        if mod(h_di, 5) == 0, fprintf('\n  '); end
    end
    fprintf('\n\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Distribution analysis
fprintf('=========== BER 分布统计 ===========\n');
fprintf('  α          | mean   | median | std   | min  | max  | 灾难率 (BER>30%%)\n');
fprintf('-------------+--------+--------+-------+------+------+------------------\n');
for h_ai = 1:h_n_alpha
    h_row = h_ber(h_ai, :) * 100;
    h_disaster = sum(h_row > 30, 'omitnan');
    fprintf('  %+8.0e   | %5.2f  | %5.2f  | %5.2f | %4.1f | %4.1f | %d/%d (%5.1f%%)\n', ...
        h_alpha_list(h_ai), ...
        mean(h_row, 'omitnan'), median(h_row, 'omitnan'), std(h_row, 'omitnan'), ...
        min(h_row, [], 'omitnan'), max(h_row, [], 'omitnan'), ...
        h_disaster, h_n_seed, 100*h_disaster/h_n_seed);
end

%% Histogram bins
fprintf('\n=========== BER 直方图（30 seed）===========\n');
h_bins = [0, 1, 5, 15, 30, 50, 101];
h_bin_labels = {'BER<1%', '1-5%', '5-15%', '15-30%', '30-50%', '>50%'};
fprintf('  α          ');
for h_bi = 1:length(h_bin_labels)
    fprintf('| %s ', h_bin_labels{h_bi});
end
fprintf('\n-------------+--------+------+-------+--------+--------+------\n');
for h_ai = 1:h_n_alpha
    h_row = h_ber(h_ai, :) * 100;
    fprintf('  %+8.0e   ', h_alpha_list(h_ai));
    for h_bi = 1:length(h_bin_labels)
        h_count = sum(h_row >= h_bins(h_bi) & h_row < h_bins(h_bi+1), 'omitnan');
        fprintf('| %5d  ', h_count);
    end
    fprintf('\n');
end

%% 判定
fprintf('\n=========== 判定 ===========\n');
for h_ai = 1:h_n_alpha
    h_row = h_ber(h_ai, :) * 100;
    h_low  = sum(h_row < 5,  'omitnan');
    h_high = sum(h_row > 30, 'omitnan');
    h_mid  = sum(h_row >= 5 & h_row <= 30, 'omitnan');
    fprintf('  α=%+.0e: %d 个 BER<5%% + %d 个 BER>30%% + %d 个中间', ...
        h_alpha_list(h_ai), h_low, h_high, h_mid);
    if h_low + h_high > 0.8 * h_n_seed && h_high > 1
        fprintf(' → ✓ 双峰分布（deterministic 灾难，bug 性质确认）\n');
    elseif h_high == 0
        fprintf(' → ✓ 健康（无灾难触发）\n');
    elseif h_high < 0.05 * h_n_seed
        fprintf(' → 🟡 灾难率 <5%%（seed=1024 可能是离群点）\n');
    else
        fprintf(' → ⚠ 灾难率 %.1f%% 真实，bug 性质确认\n', 100*h_high/h_n_seed);
    end
end

fprintf('\n完成\n');
