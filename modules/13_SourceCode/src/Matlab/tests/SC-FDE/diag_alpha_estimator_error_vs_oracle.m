%% diag_alpha_estimator_error_vs_oracle.m
% 目的：严谨量化 SC-FDE 多普勒系数估计误差 + oracle 代入解码作为参照组
%
% 核心问题分解（每个 α_true 一行）：
%   1. α_est − α_true           → 估计器精度
%   2. BER(oracle)              → pipeline 下限（代入真值的理论最佳）
%   3. BER(baseline) − BER(oracle) → 估计误差传递到 BER 的性能损失 gap
%
% V1.1（2026-04-22）：所有 harness 内部变量加 h_ 前缀
%   根因：run(runner) 是 script-mode 共享 workspace，runner 里 alpha_est / this_dir
%   等变量会覆盖 harness 同名变量，clearvars -except 保留的是被污染后的值

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_results_estimator');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

fprintf('========================================\n');
fprintf('  SC-FDE α 估计误差 vs oracle 对照 V1.1\n');
fprintf('========================================\n\n');

%% 扫描参数
h_alpha_list = [0, 1e-4, -1e-4, 5e-4, -5e-4, 1e-3, -1e-3, ...
                3e-3, -3e-3, 1e-2, -1e-2, 3e-2, -3e-2];
h_modes = {'baseline', 'oracle'};

h_n_alpha = length(h_alpha_list);
h_n_modes = length(h_modes);

% 记录矩阵（harness state，h_ 前缀避免与 runner 同名变量冲突）
h_ber       = nan(h_n_alpha, h_n_modes);
h_alpha_est = nan(h_n_alpha, h_n_modes);

h_total = h_n_alpha * h_n_modes;
h_k = 0;

%% 主循环
for h_ai = 1:h_n_alpha
    for h_mi = 1:h_n_modes
        h_k = h_k + 1;
        h_alpha_val = h_alpha_list(h_ai);
        h_mode_str  = h_modes{h_mi};
        h_tag       = sprintf('%s_a%+g', h_mode_str, h_alpha_val);
        h_csv_path  = fullfile(h_out_dir, sprintf('%s.csv', h_tag));
        if exist(h_csv_path, 'file'), delete(h_csv_path); end

        fprintf('[%2d/%d] mode=%-8s α_true=%+.0e\n', ...
                h_k, h_total, h_mode_str, h_alpha_val);

        % Runner workspace 变量（按 runner 约定命名，不加 h_ 前缀）
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

        if strcmp(h_mode_str, 'oracle')
            bench_oracle_alpha = true;
        end

        try
            run(h_runner);
        catch ME
            fprintf('  [ERROR] %s\n', ME.message);
        end

        % 读 CSV 取 BER + alpha_est（直接从文件，不依赖 runner 残留变量）
        if exist(h_csv_path, 'file')
            try
                h_T = readtable(h_csv_path);
                if height(h_T) >= 1
                    h_ber(h_ai, h_mi) = h_T.ber_coded(1);
                    if ismember('alpha_est', h_T.Properties.VariableNames)
                        h_alpha_est(h_ai, h_mi) = h_T.alpha_est(1);
                    end
                end
            catch ME2
                fprintf('  [WARN] 读 CSV 失败: %s\n', ME2.message);
            end
        end

        % clearvars 用 h_ 前缀保护 harness state（runner 内同名变量被清理）
        clearvars -except h_ai h_mi h_k h_total h_n_alpha h_n_modes ...
                          h_alpha_list h_modes h_ber h_alpha_est ...
                          h_this_dir h_runner h_out_dir
    end
end

%% ============ 结果表 1：α 估计误差（baseline） ============
fprintf('\n============================================================\n');
fprintf('  表 1：估计器精度（baseline 模式）\n');
fprintf('============================================================\n');
fprintf('%-12s | %-14s | %-14s | %-14s\n', ...
        'α_true', 'α_est', '|abs err|', 'rel err (%)');
fprintf('%s\n', repmat('-', 1, 62));

h_mi_base = find(strcmp(h_modes, 'baseline'));
for h_ai = 1:h_n_alpha
    a_true = h_alpha_list(h_ai);
    a_est  = h_alpha_est(h_ai, h_mi_base);
    if isnan(a_est)
        fprintf('%-+12.1e | %-14s | %-14s | %-14s\n', a_true, '--', '--', '--');
    else
        abs_err = a_est - a_true;
        if abs(a_true) > 1e-12
            rel_err = abs_err / abs(a_true) * 100;
            fprintf('%-+12.1e | %-+14.4e | %-14.3e | %-+14.2f\n', ...
                    a_true, a_est, abs(abs_err), rel_err);
        else
            fprintf('%-+12.1e | %-+14.4e | %-14.3e | %-14s\n', ...
                    a_true, a_est, abs(abs_err), '(α=0, N/A)');
        end
    end
end

%% ============ 结果表 2：BER 对比 + gap ============
fprintf('\n============================================================\n');
fprintf('  表 2：BER baseline vs oracle + 性能 gap\n');
fprintf('============================================================\n');
fprintf('%-12s | %-15s | %-15s | %-15s | %-20s\n', ...
        'α_true', 'BER(baseline)', 'BER(oracle)', 'gap (diff)', '诊断');
fprintf('%s\n', repmat('-', 1, 85));

h_mi_orc = find(strcmp(h_modes, 'oracle'));
for h_ai = 1:h_n_alpha
    a_true = h_alpha_list(h_ai);
    ber_b  = h_ber(h_ai, h_mi_base);
    ber_o  = h_ber(h_ai, h_mi_orc);
    gap    = ber_b - ber_o;

    % 诊断类别（数据驱动）
    if isnan(ber_b) || isnan(ber_o)
        diag_str = '<缺失>';
    elseif ber_o < 1e-6 && ber_b < 1e-6
        diag_str = '全通';
    elseif ber_o < 1e-6 && ber_b >= 1e-6
        diag_str = '估计误差主导';
    elseif ber_o >= 1e-6 && abs(gap) < 0.005
        diag_str = 'pipeline 下限';
    elseif ber_o >= 1e-6 && gap >= 0.005
        diag_str = '两者都贡献';
    else
        diag_str = '其他';
    end

    fprintf('%-+12.1e | %-14.4f%% | %-14.4f%% | %-+14.4f%% | %-20s\n', ...
            a_true, ber_b*100, ber_o*100, gap*100, diag_str);
end

%% ============ 保存 ============
save(fullfile(h_out_dir, 'results.mat'), 'h_ber', 'h_alpha_est', ...
     'h_alpha_list', 'h_modes');

try
    T_sum = table(h_alpha_list(:), h_alpha_est(:,h_mi_base), ...
                  h_alpha_est(:,h_mi_base) - h_alpha_list(:), ...
                  h_ber(:,h_mi_base), h_ber(:,h_mi_orc), ...
                  h_ber(:,h_mi_base) - h_ber(:,h_mi_orc), ...
        'VariableNames', {'alpha_true','alpha_est_baseline','abs_err', ...
                          'BER_baseline','BER_oracle','BER_gap'});
    writetable(T_sum, fullfile(h_out_dir, 'summary.csv'));
catch ME
    fprintf('\n[WARN] summary.csv 保存失败：%s\n', ME.message);
end

fprintf('\n结果保存：\n');
fprintf('  %s/results.mat\n', h_out_dir);
fprintf('  %s/summary.csv\n', h_out_dir);
fprintf('  %s/<mode>_a<α>.csv（%d 份 per-run CSV）\n', h_out_dir, h_total);

fprintf('\n========================================\n');
fprintf('  完成\n');
fprintf('========================================\n');
