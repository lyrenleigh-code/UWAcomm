%% diag_50knots_multi_seed.m
% 目的：确认 α=±1.7e-2 非单调 BER 是否是 seed 共振
% 跑 5 个 seed × 4 关键 α，看稳定性

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_results_50knots_seeds');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

fprintf('========================================\n');
fprintf('  50 节多 seed 扫描（验证跳变是否稳定）\n');
fprintf('========================================\n\n');

h_alpha_list = [+1.5e-2, -1.5e-2, +1.7e-2, -1.7e-2, +2.0e-2, -2.0e-2];
h_seeds = [42, 101, 202, 303, 404];

h_n_alpha = length(h_alpha_list);
h_n_seed = length(h_seeds);
h_ber = nan(h_n_alpha, h_n_seed);

h_total = h_n_alpha * h_n_seed;
h_k = 0;

for h_ai = 1:h_n_alpha
    for h_si = 1:h_n_seed
        h_k = h_k + 1;
        a_val = h_alpha_list(h_ai);
        sd = h_seeds(h_si);
        h_tag = sprintf('a%+g_sd%d', a_val, sd);
        h_csv = fullfile(h_out_dir, sprintf('%s.csv', h_tag));
        if exist(h_csv, 'file'), delete(h_csv); end

        fprintf('[%d/%d] α=%+g seed=%d\n', h_k, h_total, a_val, sd);

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [10];
        bench_fading_cfgs              = { sprintf('a=%g', a_val), 'static', 0, a_val, 1024, 128, 4 };
        bench_channel_profile          = 'custom6';
        bench_seed                     = sd;
        bench_stage                    = 'diag';
        bench_scheme_name              = 'SC-FDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = true;
        bench_use_real_doppler         = true;

        try
            run(h_runner);
        catch ME
            fprintf('  [ERROR] %s\n', ME.message);
        end

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                if height(T) >= 1
                    h_ber(h_ai, h_si) = T.ber_coded(1);
                end
            catch
            end
        end

        clearvars -except h_ai h_si h_k h_total h_n_alpha h_n_seed ...
                          h_alpha_list h_seeds h_ber h_this_dir h_runner h_out_dir
    end
end

%% 表
fprintf('\n========================================\n');
fprintf('  BER 矩阵（行=α，列=seed）\n');
fprintf('========================================\n');
fprintf('%-12s', 'α');
for h_si = 1:h_n_seed, fprintf(' | sd=%-6d', h_seeds(h_si)); end
fprintf(' | %-9s | %-9s\n', 'mean', 'max');
fprintf('%s\n', repmat('-', 1, 12 + h_n_seed*12 + 24));
for h_ai = 1:h_n_alpha
    fprintf('%-+12.2e', h_alpha_list(h_ai));
    row = h_ber(h_ai, :);
    for h_si = 1:h_n_seed
        v = h_ber(h_ai, h_si);
        if isnan(v), fprintf(' | %-9s', '--');
        else, fprintf(' | %-8.4f%%', v*100); end
    end
    valid = row(~isnan(row));
    if ~isempty(valid)
        fprintf(' | %-8.4f%% | %-8.4f%%\n', mean(valid)*100, max(valid)*100);
    else
        fprintf(' | %-9s | %-9s\n', '--', '--');
    end
end

save(fullfile(h_out_dir, 'results.mat'), 'h_ber', 'h_alpha_list', 'h_seeds');
try
    T = array2table([h_alpha_list', h_ber], ...
        'VariableNames', ['alpha', arrayfun(@(s) sprintf('seed_%d',s), h_seeds, 'UniformOutput', false)]);
    writetable(T, fullfile(h_out_dir, 'summary.csv'));
catch
end

fprintf('\n保存：%s\n', h_out_dir);
