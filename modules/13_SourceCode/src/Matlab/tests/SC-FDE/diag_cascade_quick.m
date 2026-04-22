%% diag_cascade_quick.m
% 快速 smoke test：只跑 baseline 模式 + 失败/代表性 α 点，1~2 分钟内判断 cascade 改动效果
%
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_cascade_quick_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

fprintf('========================================\n');
fprintf('  Cascade Quick Smoke Test (baseline only)\n');
fprintf('========================================\n\n');

h_alpha_list = [-1e-2, 1e-2, 3e-2, -3e-2, 5e-4];   % 含之前失败 & 代表性通过
h_n_alpha = length(h_alpha_list);
h_ber       = nan(1, h_n_alpha);
h_alpha_est = nan(1, h_n_alpha);

for h_ai = 1:h_n_alpha
    h_alpha_val = h_alpha_list(h_ai);
    h_csv_path  = fullfile(h_out_dir, sprintf('quick_a%+g.csv', h_alpha_val));
    if exist(h_csv_path, 'file'), delete(h_csv_path); end

    fprintf('[%d/%d] α=%+.1e ...\n', h_ai, h_n_alpha, h_alpha_val);

    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = [10];
    bench_fading_cfgs              = { sprintf('a=%g', h_alpha_val), 'static', 0, h_alpha_val, 1024, 128, 4 };
    bench_channel_profile          = 'custom6';
    bench_seed                     = 42;
    bench_stage                    = 'diag';
    bench_scheme_name              = 'SC-FDE';
    bench_csv_path                 = h_csv_path;
    bench_diag                     = struct('enable', false);
    bench_toggles                  = struct();
    bench_oracle_alpha             = false;
    bench_oracle_passband_resample = false;
    bench_use_real_doppler         = true;

    try
        run(h_runner);
    catch ME
        fprintf('  [ERROR] %s\n', ME.message);
    end

    if exist(h_csv_path, 'file')
        try
            h_T = readtable(h_csv_path);
            if height(h_T) >= 1
                h_ber(h_ai) = h_T.ber_coded(1);
                if ismember('alpha_est', h_T.Properties.VariableNames)
                    h_alpha_est(h_ai) = h_T.alpha_est(1);
                end
            end
        catch
        end
    end

    clearvars -except h_ai h_n_alpha h_alpha_list h_ber h_alpha_est ...
                      h_this_dir h_runner h_out_dir
end

fprintf('\n--- Quick BER Summary (real Doppler, baseline w/ real cascade) ---\n');
fprintf('%-12s | %-10s | %-12s\n', 'α_true', 'BER', 'α_est_final');
fprintf('%s\n', repmat('-', 1, 42));
for h_ai = 1:h_n_alpha
    v = h_ber(h_ai);
    if isnan(v)
        fprintf('%-+12.1e | %-10s | %-12s\n', h_alpha_list(h_ai), 'ERR', '--');
    elseif v == 0
        fprintf('%-+12.1e | %-10s | %-+12.4e\n', h_alpha_list(h_ai), '0', h_alpha_est(h_ai));
    else
        fprintf('%-+12.1e | %-9.2f%% | %-+12.4e\n', h_alpha_list(h_ai), v*100, h_alpha_est(h_ai));
    end
end

fprintf('\n完成\n');
