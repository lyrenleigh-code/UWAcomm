%% diag_neg_1e2_root_cause.m
% 追因 SC-FDE α=-1e-2 单点 BER 13.7% 异常
%
% 同时回答两问：
%   H1（SNR 受限）：SNR ∈ {10, 15, 20} dB 下 α=-1e-2 BER 是否随 SNR 改善
%   H2（单 seed 不幸）：5 个 seed 平均，看 BER 方差
%
% 对照组：α=+1e-2（baseline 0%）— 排除其它体制问题
%
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_neg_1e2_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

fprintf('========================================\n');
fprintf('  α=-1e-2 单点根因追查（SNR + seed 双维度）\n');
fprintf('========================================\n\n');

h_alpha_list = [-1e-2, +1e-2];   % 受测 + 对照
h_snr_list   = [10, 15, 20];
h_seed_list  = [42, 137, 256, 511, 1024];

h_n_alpha = length(h_alpha_list);
h_n_snr   = length(h_snr_list);
h_n_seed  = length(h_seed_list);

% 结果矩阵：[α_idx][snr_idx][seed_idx]
h_ber       = nan(h_n_alpha, h_n_snr, h_n_seed);
h_alpha_est = nan(h_n_alpha, h_n_snr, h_n_seed);

for h_ai = 1:h_n_alpha
    h_alpha_val = h_alpha_list(h_ai);
    for h_si = 1:h_n_snr
        h_snr = h_snr_list(h_si);
        for h_di = 1:h_n_seed
            h_seed = h_seed_list(h_di);
            h_csv_path = fullfile(h_out_dir, ...
                sprintf('a%+g_snr%d_seed%d.csv', h_alpha_val, h_snr, h_seed));
            if exist(h_csv_path, 'file'), delete(h_csv_path); end

            fprintf('[α=%+.0e SNR=%2ddB seed=%4d]', h_alpha_val, h_snr, h_seed);

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
                evalc('run(h_runner)');   % 抑制 runner 内部 fprintf
            catch ME
                fprintf(' ERR: %s\n', ME.message);
                continue;
            end

            if exist(h_csv_path, 'file')
                try
                    h_T = readtable(h_csv_path);
                    if height(h_T) >= 1
                        h_ber(h_ai, h_si, h_di) = h_T.ber_coded(1);
                        if ismember('alpha_est', h_T.Properties.VariableNames)
                            h_alpha_est(h_ai, h_si, h_di) = h_T.alpha_est(1);
                        end
                    end
                catch
                end
            end
            fprintf(' BER=%.2f%%\n', h_ber(h_ai, h_si, h_di) * 100);
        end
    end
end

%% Summary
fprintf('\n=========== BER Summary (%%) ===========\n');
fprintf('              ');
for h_di = 1:h_n_seed
    fprintf('seed%-5d', h_seed_list(h_di));
end
fprintf('| mean   | std\n');
fprintf('--------------');
for h_di = 1:h_n_seed
    fprintf('---------');
end
fprintf('|--------|------\n');

for h_ai = 1:h_n_alpha
    for h_si = 1:h_n_snr
        h_row = squeeze(h_ber(h_ai, h_si, :)) * 100;
        fprintf('α=%+.0e SNR%2d ', h_alpha_list(h_ai), h_snr_list(h_si));
        for h_di = 1:h_n_seed
            fprintf('%7.2f  ', h_row(h_di));
        end
        fprintf('| %5.2f  | %4.2f\n', mean(h_row, 'omitnan'), std(h_row, 'omitnan'));
    end
end

%% 判定
fprintf('\n=========== 判定 ===========\n');

% H1: SNR 受限？
h_neg_means = squeeze(mean(h_ber(1, :, :) * 100, 3));   % α=-1e-2 各 SNR 平均
h_pos_means = squeeze(mean(h_ber(2, :, :) * 100, 3));
fprintf('H1（SNR 受限）: α=-1e-2 mean BER 随 SNR: ');
fprintf('%.2f%% → %.2f%% → %.2f%%\n', h_neg_means(1), h_neg_means(2), h_neg_means(3));
if h_neg_means(end) < 1.0
    fprintf('  → ✓ SNR 受限确认（高 SNR 自然恢复）\n');
elseif h_neg_means(end) < h_neg_means(1) * 0.3
    fprintf('  → 🟡 部分 SNR 受限（高 SNR 显著改善但未恢复）\n');
else
    fprintf('  → ❌ 非 SNR 受限（高 SNR 仍异常）\n');
end

% H2: 单 seed 不幸？
h_neg_seed_var = squeeze(std(h_ber(1, 1, :) * 100, 'omitnan'));   % SNR=10dB 下 seed std
h_neg_seed_mean = squeeze(mean(h_ber(1, 1, :) * 100, 'omitnan'));
fprintf('H2（单 seed 不幸）: α=-1e-2 SNR=10 5-seed BER mean=%.2f%% std=%.2f%%\n', ...
        h_neg_seed_mean, h_neg_seed_var);
if h_neg_seed_var > h_neg_seed_mean
    fprintf('  → ✓ 高方差，单 seed 不幸可能\n');
else
    fprintf('  → ❌ 系统性偏差（5 seed 稳定异常）\n');
end

fprintf('\n完成\n');
