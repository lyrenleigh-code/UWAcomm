%% diag_passband_real_doppler.m
% 目的：在【真实 Doppler】仿真（gen_doppler_channel V1.1）下重测 3 种 α 补偿策略
%
% 3 模式（与 diag_passband_vs_baseband_oracle.m 同结构，便于纵向对比）：
%   A. baseline          — estimator + iter + CP（默认）
%   B. oracle_baseband   — α_est = dop_rate（基带 resample with 真值）
%   C. oracle_passband   — 通带用 dop_rate resample（无需基带 CFO 补偿，因 rx_pb 载波本在 fc(1+α)）
%
% 与 fake Doppler 版本的区别：
%   - bench_use_real_doppler = true → 信道走 gen_doppler_channel
%   - oracle_passband 路径不再触发 CFO rotate（runner 已条件判断）
%
% 预期：A/B 行为可能因有真实 CFO 而恶化（baseband estimator/CP 没显式 CFO 模块）；
%       C 应在真实 Doppler 下接近 0
%
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_results_passband_real');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

fprintf('========================================\n');
fprintf('  SC-FDE × 真实 Doppler（gen_doppler_channel）3-mode 对比 V1.0\n');
fprintf('========================================\n\n');

%% 扫描参数
h_alpha_list = [5e-4, -5e-4, 1e-3, -1e-3, 3e-3, -3e-3, 1e-2, -1e-2, 3e-2, -3e-2];
h_modes = {'baseline', 'oracle_baseband', 'oracle_passband'};
h_n_alpha = length(h_alpha_list);
h_n_modes = length(h_modes);

h_ber       = nan(h_n_modes, h_n_alpha);
h_alpha_est = nan(h_n_modes, h_n_alpha);

h_total = h_n_modes * h_n_alpha;
h_k = 0;

%% 主循环
for h_mi = 1:h_n_modes
    for h_ai = 1:h_n_alpha
        h_mode_str  = h_modes{h_mi};
        h_alpha_val = h_alpha_list(h_ai);
        h_k = h_k + 1;
        h_tag       = sprintf('%s_a%+g', h_mode_str, h_alpha_val);
        h_csv_path  = fullfile(h_out_dir, sprintf('%s.csv', h_tag));
        if exist(h_csv_path, 'file'), delete(h_csv_path); end

        fprintf('[%2d/%d] mode=%-16s α=%+.0e (real Doppler)\n', ...
                h_k, h_total, h_mode_str, h_alpha_val);

        % Runner workspace
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
        bench_use_real_doppler         = true;    % ★ 关键：切换到真实 Doppler

        switch h_mode_str
            case 'baseline'
                % default
            case 'oracle_baseband'
                bench_oracle_alpha = true;
            case 'oracle_passband'
                bench_oracle_passband_resample = true;
        end

        try
            run(h_runner);
        catch ME
            fprintf('  [ERROR] %s\n', ME.message);
        end

        if exist(h_csv_path, 'file')
            try
                h_T = readtable(h_csv_path);
                if height(h_T) >= 1
                    h_ber(h_mi, h_ai) = h_T.ber_coded(1);
                    if ismember('alpha_est', h_T.Properties.VariableNames)
                        h_alpha_est(h_mi, h_ai) = h_T.alpha_est(1);
                    end
                end
            catch ME2
                fprintf('  [WARN] 读 CSV 失败: %s\n', ME2.message);
            end
        end

        clearvars -except h_mi h_ai h_k h_total h_n_alpha h_n_modes ...
                          h_alpha_list h_modes h_ber h_alpha_est ...
                          h_this_dir h_runner h_out_dir
    end
end

%% 输出对比表
fprintf('\n============================================================\n');
fprintf('  BER 对比表（SC-FDE × 真实 Doppler, SNR=10, custom6, seed=42）\n');
fprintf('============================================================\n');
fprintf('%-10s', 'α');
for h_mi = 1:h_n_modes, fprintf(' | %-18s', h_modes{h_mi}); end
fprintf('\n%s\n', repmat('-', 1, 10 + h_n_modes*21));

for h_ai = 1:h_n_alpha
    fprintf('%-+10.1e', h_alpha_list(h_ai));
    for h_mi = 1:h_n_modes
        v = h_ber(h_mi, h_ai);
        if isnan(v)
            fprintf(' | %-18s', '--');
        elseif v == 0
            fprintf(' | %-18s', '0');
        else
            fprintf(' | %-17.4f%%', v*100);
        end
    end
    fprintf('\n');
end

%% α_est（baseline 列，看 estimator 在真实 Doppler 下精度）
fprintf('\n--- baseline 模式 α_est vs α_true（真实 Doppler）---\n');
h_mi_base = find(strcmp(h_modes,'baseline'));
fprintf('%-12s | %-14s | %-14s | %-14s\n', 'α_true','α_est','|abs err|','rel err (%)');
fprintf('%s\n', repmat('-', 1, 62));
for h_ai = 1:h_n_alpha
    a_true = h_alpha_list(h_ai);
    a_est  = h_alpha_est(h_mi_base, h_ai);
    if isnan(a_est)
        fprintf('%-+12.1e | %-14s | %-14s | %-14s\n', a_true, '--','--','--');
    else
        e = a_est - a_true;
        if abs(a_true) > 1e-12
            fprintf('%-+12.1e | %-+14.4e | %-14.3e | %-+14.2f\n', a_true, a_est, abs(e), e/abs(a_true)*100);
        else
            fprintf('%-+12.1e | %-+14.4e | %-14.3e | %-14s\n', a_true, a_est, abs(e), '(α=0,N/A)');
        end
    end
end

%% 保存
save(fullfile(h_out_dir, 'results.mat'), 'h_ber', 'h_alpha_est', ...
     'h_alpha_list', 'h_modes');
try
    T_sum = array2table([h_alpha_list', h_ber'], ...
        'VariableNames', ['alpha', h_modes]);
    writetable(T_sum, fullfile(h_out_dir, 'summary.csv'));
catch ME
    fprintf('\n[WARN] summary.csv 保存失败：%s\n', ME.message);
end

fprintf('\n结果保存：\n');
fprintf('  %s/summary.csv\n', h_out_dir);
fprintf('  %s/results.mat\n', h_out_dir);
fprintf('  %s/<mode>_a<α>.csv (%d 份 per-run CSV)\n', h_out_dir, h_total);

fprintf('\n========================================\n');
fprintf('  完成\n');
fprintf('========================================\n');
