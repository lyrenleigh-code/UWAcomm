%% diag_alpha_sensitivity.m
% 目的：量化 SC-FDE 下游 pipeline 对残余 α 的 BER 敏感度
%
% 方法：
%   固定信道 α_true = 0.03（触发 +3e-2 5.4% 场景）
%   用 bench_alpha_override 代入一系列不同的 α_est 值，看 BER 响应曲线
%   residual_α = α_override − α_true = {-4e-4, -3e-4, ..., 0, ..., +3e-4, +4e-4}
%
% 能回答：
%   - pipeline 在真值附近的可容忍残余 α 阈值是多少
%   - BER 敏感度是线性还是台阶型
%   - estimator 残余 +1.4e-4 对应 5.4% BER 是否 reproducible
%   - 正负残余的 BER 是否对称
%
% 版本：V1.0.0（2026-04-22）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_results_sensitivity');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

fprintf('========================================\n');
fprintf('  SC-FDE α 灵敏度扫描（α_true=+3e-2）V1.0.0\n');
fprintf('========================================\n\n');

%% 扫描参数
h_alpha_true = 0.03;                        % 信道真 α
% α_override 点：围绕真值 ±4e-4，步长 5e-5；再加几个远点验证
h_residual_list = [-4e-4, -3e-4, -2e-4, -1.5e-4, -1e-4, -5e-5, ...
                    0, ...
                    5e-5, 1e-4, 1.5e-4, 2e-4, 3e-4, 4e-4];
h_alpha_override_list = h_alpha_true + h_residual_list;

h_n = length(h_alpha_override_list);
h_ber = nan(1, h_n);

%% 扫描
for h_i = 1:h_n
    a_ov = h_alpha_override_list(h_i);
    h_tag = sprintf('override_a%+.2e', a_ov);
    h_csv_path = fullfile(h_out_dir, sprintf('%s.csv', h_tag));
    if exist(h_csv_path, 'file'), delete(h_csv_path); end

    fprintf('[%2d/%d] α_override=%+.5f, residual=%+.1e\n', ...
            h_i, h_n, a_ov, h_residual_list(h_i));

    % Runner workspace
    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = [10];
    bench_fading_cfgs              = { sprintf('a=%g', h_alpha_true), 'static', 0, h_alpha_true, 1024, 128, 4 };
    bench_channel_profile          = 'custom6';
    bench_seed                     = 42;
    bench_stage                    = 'diag';
    bench_scheme_name              = 'SC-FDE';
    bench_csv_path                 = h_csv_path;
    bench_diag                     = struct('enable', false);
    bench_toggles                  = struct();
    bench_oracle_alpha             = false;
    bench_oracle_passband_resample = false;
    bench_alpha_override           = a_ov;   % 关键：强制覆盖 alpha_est

    try
        run(h_runner);
    catch ME
        fprintf('  [ERROR] %s\n', ME.message);
    end

    % 读 BER
    if exist(h_csv_path, 'file')
        try
            h_T = readtable(h_csv_path);
            if height(h_T) >= 1
                h_ber(h_i) = h_T.ber_coded(1);
            end
        catch ME2
            fprintf('  [WARN] 读 CSV 失败: %s\n', ME2.message);
        end
    end

    clearvars -except h_i h_n h_alpha_true h_residual_list h_alpha_override_list ...
                      h_ber h_this_dir h_runner h_out_dir
end

%% 结果表
fprintf('\n============================================================\n');
fprintf('  BER 响应曲线（α_true=%+.3f, SNR=10dB, custom6）\n', h_alpha_true);
fprintf('============================================================\n');
fprintf('%-15s | %-15s | %-15s\n', 'α_override', 'residual α', 'BER');
fprintf('%s\n', repmat('-', 1, 51));
for h_i = 1:h_n
    a_ov = h_alpha_override_list(h_i);
    res  = h_residual_list(h_i);
    if isnan(h_ber(h_i))
        fprintf('%-+15.5f | %-+15.2e | %-15s\n', a_ov, res, '--');
    elseif h_ber(h_i) == 0
        fprintf('%-+15.5f | %-+15.2e | %-15s\n', a_ov, res, '0 (无误码)');
    else
        fprintf('%-+15.5f | %-+15.2e | %-15.4f%%\n', a_ov, res, h_ber(h_i)*100);
    end
end

%% 图
try
    fig = figure('Name','BER vs residual α @ α_true=+3e-2','Position',[100 100 900 550]);

    subplot(2,1,1);
    plot(h_residual_list*1e4, h_ber*100, 'bo-', 'LineWidth', 2, 'MarkerSize', 10, ...
         'MarkerFaceColor', [0.3 0.6 1]);
    grid on;
    xlabel('residual α  (×10^{-4})');
    ylabel('coded BER (%)');
    title(sprintf('SC-FDE BER 对残余 α 的敏感度（α\\_true=+%.3f, SNR=10）', h_alpha_true));
    yline(5.4, 'r--', 'baseline BER 5.4%');
    xline(1.4, 'k--', 'baseline α_{est} residual');

    subplot(2,1,2);
    semilogy(h_residual_list*1e4, max(h_ber, 1e-6)*100, 'bo-', 'LineWidth', 2, ...
             'MarkerSize', 10, 'MarkerFaceColor', [0.3 0.6 1]);
    grid on;
    xlabel('residual α  (×10^{-4})');
    ylabel('coded BER (%) — log 轴');
    title('同上 log 轴视图（0% 由 1e-6 代替以显示）');

    saveas(fig, fullfile(h_out_dir, 'sensitivity_curve.png'));
    fprintf('\n图：%s/sensitivity_curve.png\n', h_out_dir);
catch ME
    fprintf('\n[WARN] 绘图失败：%s\n', ME.message);
end

%% 保存
save(fullfile(h_out_dir, 'results.mat'), 'h_ber', 'h_residual_list', ...
     'h_alpha_override_list', 'h_alpha_true');

try
    T_sum = table(h_alpha_override_list(:), h_residual_list(:), h_ber(:), ...
        'VariableNames', {'alpha_override','residual_alpha','BER_coded'});
    writetable(T_sum, fullfile(h_out_dir, 'summary.csv'));
catch ME
    fprintf('\n[WARN] summary.csv 保存失败：%s\n', ME.message);
end

fprintf('\n结果保存：\n');
fprintf('  %s/summary.csv\n', h_out_dir);
fprintf('  %s/sensitivity_curve.png\n', h_out_dir);
fprintf('  %s/results.mat\n', h_out_dir);

fprintf('\n========================================\n');
fprintf('  完成\n');
fprintf('========================================\n');
