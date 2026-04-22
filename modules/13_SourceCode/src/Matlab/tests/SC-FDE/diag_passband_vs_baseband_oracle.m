%% diag_passband_vs_baseband_oracle.m
% 目的：对比 SC-FDE 在 3 种 α 补偿策略下的 BER，回答"通带 resample 是否有优势"
%
% 3 种模式：
%   A. baseline          — estimator + 迭代 + CP 精修（默认，α 未知）
%   B. oracle_baseband   — α_est = dop_rate 真值，基带 resample（bench_oracle_alpha=true）
%   C. oracle_passband   — 通带 rx_pb 先用 dop_rate 真值 resample，基带跳过（bench_oracle_passband_resample=true）
%
% 实验控制：
%   - 5 体制 × 10 α × 1 SNR 过宽；聚焦 SC-FDE × 10 α × SNR=10
%   - α 扫描对称双向：±5e-4, ±1e-3, ±3e-3, ±1e-2, ±3e-2
%   - 固定 custom6 profile, seed=42，fd=0（静态多径 + 纯常值 α）
%
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;
this_dir = fileparts(mfilename('fullpath'));
runner   = fullfile(this_dir, 'test_scfde_timevarying.m');
out_dir  = fullfile(this_dir, 'diag_results_passband');
if ~exist(out_dir, 'dir'), mkdir(out_dir); end

fprintf('========================================\n');
fprintf('  SC-FDE: 通带 vs 基带 oracle resample 对比 V1.0.0\n');
fprintf('========================================\n\n');

%% 扫描参数
alpha_list = [5e-4, -5e-4, 1e-3, -1e-3, 3e-3, -3e-3, 1e-2, -1e-2, 3e-2, -3e-2];
modes = {'baseline', 'oracle_baseband', 'oracle_passband'};
n_modes = length(modes);
n_alpha = length(alpha_list);

ber_results    = nan(n_modes, n_alpha);
alpha_est_log  = nan(n_modes, n_alpha);

total = n_modes * n_alpha;
k = 0;

%% 主循环：3 种模式 × 10 α
for mi = 1:n_modes
    for ai = 1:n_alpha
        mode_str = modes{mi};   % 每次 iter 重新取（clearvars 会清局部变量）
        k = k + 1;
        alpha_val = alpha_list(ai);
        tag = sprintf('%s_a%+g', mode_str, alpha_val);
        csv_path = fullfile(out_dir, sprintf('%s.csv', tag));
        if exist(csv_path, 'file'), delete(csv_path); end

        fprintf('[%2d/%d] mode=%-16s α=%+.0e\n', k, total, mode_str, alpha_val);

        % Runner workspace 变量
        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [10];
        bench_fading_cfgs              = { sprintf('a=%g', alpha_val), 'static', 0, alpha_val, 1024, 128, 4 };
        bench_channel_profile          = 'custom6';
        bench_seed                     = 42;
        bench_stage                    = 'diag';
        bench_scheme_name              = 'SC-FDE';
        bench_csv_path                 = csv_path;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;

        switch mode_str
            case 'baseline'
                % 默认：estimator + 迭代 + CP 精修
            case 'oracle_baseband'
                bench_oracle_alpha = true;
            case 'oracle_passband'
                bench_oracle_passband_resample = true;
        end

        try
            run(runner);
        catch ME
            fprintf('  [ERROR] %s\n', ME.message);
        end

        % 读 CSV 取 BER
        if exist(csv_path, 'file')
            try
                T = readtable(csv_path);
                if height(T) >= 1
                    ber_results(mi, ai) = T.ber_coded(1);
                    if ismember('alpha_est', T.Properties.VariableNames)
                        alpha_est_log(mi, ai) = T.alpha_est(1);
                    end
                end
            catch
                fprintf('  [WARN] 无法读取 %s\n', csv_path);
            end
        end

        clearvars -except mi ai k total alpha_list modes n_modes n_alpha ...
                          ber_results alpha_est_log this_dir runner out_dir
    end
end

%% 输出对比表
fprintf('\n============================================================\n');
fprintf('  BER 对比表（SC-FDE, SNR=10, custom6, seed=42）\n');
fprintf('============================================================\n');
fprintf('%-10s', 'α');
for mi = 1:n_modes, fprintf(' | %-18s', modes{mi}); end
fprintf('\n%s\n', repmat('-', 1, 10 + n_modes*21));

for ai = 1:n_alpha
    fprintf('%-+10.1e', alpha_list(ai));
    for mi = 1:n_modes
        v = ber_results(mi, ai);
        if isnan(v)
            fprintf(' | %-18s', '--');
        elseif v == 0
            fprintf(' | %-18s', '0');
        else
            fprintf(' | %-18.4f%%', v*100);
        end
    end
    fprintf('\n');
end

%% 差异表：oracle_baseband vs oracle_passband
fprintf('\n--- 差异：BER(oracle_passband) − BER(oracle_baseband) ---\n');
mb = find(strcmp(modes,'oracle_baseband'));
mp = find(strcmp(modes,'oracle_passband'));
for ai = 1:n_alpha
    db = ber_results(mb, ai);
    dp = ber_results(mp, ai);
    if isnan(db) || isnan(dp)
        fprintf('  α=%+.1e  --\n', alpha_list(ai));
    else
        fprintf('  α=%+.1e  %+.4f%%  (baseband=%.4f%%, passband=%.4f%%)\n', ...
                alpha_list(ai), (dp-db)*100, db*100, dp*100);
    end
end

%% 保存
save(fullfile(out_dir, 'results.mat'), 'ber_results', 'alpha_est_log', ...
     'alpha_list', 'modes');
try
    T_summary = array2table([alpha_list', ber_results'], ...
        'VariableNames', ['alpha', modes]);
    writetable(T_summary, fullfile(out_dir, 'summary.csv'));
catch ME
    fprintf('\n[WARN] summary.csv 保存失败: %s\n', ME.message);
end

fprintf('\n结果保存：\n');
fprintf('  %s/results.mat\n', out_dir);
fprintf('  %s/summary.csv\n', out_dir);
fprintf('  %s/<mode>_a<α>.csv（%d 份 per-run CSV）\n', out_dir, total);

fprintf('\n========================================\n');
fprintf('  完成\n');
fprintf('========================================\n');
