%% diag_50knots.m
% 目的：专项测试 50 节（α=±1.7e-2）工况下 3 种模式的 BER
% v=50 kn = 25.72 m/s, c=1500 m/s, α=v/c=0.01715
% 附加更细 α 网格以内插出曲线
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_results_50knots');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

fprintf('========================================\n');
fprintf('  50 节（α=±1.7e-2）真实 Doppler 专项测试\n');
fprintf('========================================\n\n');

% α 列表：以 50 节为中心 + 细网格
h_alpha_list = [1.7e-2, -1.7e-2, 2e-2, -2e-2, 1.5e-2, -1.5e-2, 1.2e-2, -1.2e-2];
h_modes = {'oracle_passband'};   % 仅测通带 oracle（baseline/oracle_baseband 在真 Doppler 下全崩）

h_n_alpha = length(h_alpha_list);
h_ber = nan(1, h_n_alpha);
h_alpha_est = nan(1, h_n_alpha);

for h_ai = 1:h_n_alpha
    a_val = h_alpha_list(h_ai);
    h_tag = sprintf('passband_a%+g', a_val);
    h_csv_path = fullfile(h_out_dir, sprintf('%s.csv', h_tag));
    if exist(h_csv_path, 'file'), delete(h_csv_path); end

    fprintf('[%d/%d] α=%+g (v=%.1f kn)\n', h_ai, h_n_alpha, a_val, abs(a_val)*1500/0.5144);

    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = [10];
    bench_fading_cfgs              = { sprintf('a=%g', a_val), 'static', 0, a_val, 1024, 128, 4 };
    bench_channel_profile          = 'custom6';
    bench_seed                     = 42;
    bench_stage                    = 'diag';
    bench_scheme_name              = 'SC-FDE';
    bench_csv_path                 = h_csv_path;
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

    clearvars -except h_ai h_n_alpha h_alpha_list h_modes h_ber h_alpha_est ...
                      h_this_dir h_runner h_out_dir
end

%% 输出
fprintf('\n========================================\n');
fprintf('  50 节工况 BER（oracle_passband, SNR=10, real Doppler）\n');
fprintf('========================================\n');
fprintf('%-10s | %-10s | %-12s | %-12s\n', 'α', 'v (kn)', 'BER', 'α_est');
fprintf('%s\n', repmat('-', 1, 54));

% 按 |α| 升序排序
[~, sort_idx] = sort(abs(h_alpha_list));
for h_i = 1:h_n_alpha
    idx = sort_idx(h_i);
    v_kn = abs(h_alpha_list(idx)) * 1500 / 0.5144;
    if h_alpha_list(idx) > 0
        v_kn_str = sprintf('+%.1f', v_kn);
    else
        v_kn_str = sprintf('-%.1f', v_kn);
    end
    if isnan(h_ber(idx))
        fprintf('%-+10.2e | %-10s | %-12s | %-12s\n', h_alpha_list(idx), v_kn_str, '--', '--');
    else
        fprintf('%-+10.2e | %-10s | %-11.4f%% | %-+12.4e\n', ...
                h_alpha_list(idx), v_kn_str, h_ber(idx)*100, h_alpha_est(idx));
    end
end

% 保存
save(fullfile(h_out_dir, 'results.mat'), 'h_ber', 'h_alpha_est', 'h_alpha_list');
try
    T_sum = table(h_alpha_list(:), abs(h_alpha_list(:))*1500/0.5144, h_ber(:), h_alpha_est(:), ...
        'VariableNames', {'alpha','v_knots','BER','alpha_est'});
    writetable(T_sum, fullfile(h_out_dir, 'summary.csv'));
catch
end

fprintf('\n保存：%s\n', h_out_dir);
fprintf('\n========================================\n');
fprintf('  完成\n');
fprintf('========================================\n');
