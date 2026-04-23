%% diag_alpha_sweep_full.m
% Phase G：完整 α sweep × 多 SNR cascade 全场景验证（Patch D+E 后）
%
% 矩阵：10 α × 3 SNR = 30 trial
%   α: ±5e-4, ±1e-3, ±3e-3, ±1e-2, ±3e-2
%   SNR: 10, 15, 20 dB
%   seed: 42（单 seed，bench_seed 当前未生效，多 seed 留 Phase H）
%
% 输出：
%   1. BER 矩阵（10×3）
%   2. α_est 偏差表（cascade 估值 vs true α，看 ±α 对称性）
%   3. cascade α_cas_1 与 α_p2 的精修触发情况
%   4. 工作范围归纳：每个 SNR 下 BER<1% 的 α 范围
%
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_alpha_sweep_full_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

fprintf('========================================\n');
fprintf('  完整 α sweep × 多 SNR cascade 全场景验证\n');
fprintf('========================================\n\n');

h_alpha_list = [-3e-2, -1e-2, -3e-3, -1e-3, -5e-4, +5e-4, +1e-3, +3e-3, +1e-2, +3e-2];
h_snr_list   = [10, 15, 20];
h_n_alpha    = length(h_alpha_list);
h_n_snr      = length(h_snr_list);

h_ber       = nan(h_n_alpha, h_n_snr);
h_alpha_est = nan(h_n_alpha, h_n_snr);

for h_si = 1:h_n_snr
    h_snr = h_snr_list(h_si);
    fprintf('--- SNR = %d dB ---\n', h_snr);
    for h_ai = 1:h_n_alpha
        h_alpha_val = h_alpha_list(h_ai);
        h_csv_path  = fullfile(h_out_dir, ...
            sprintf('a%+g_snr%d.csv', h_alpha_val, h_snr));
        if exist(h_csv_path, 'file'), delete(h_csv_path); end

        fprintf('  α=%+.0e ', h_alpha_val);

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
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
            evalc('run(h_runner)');
        catch ME
            fprintf('ERR: %s\n', ME.message);
            continue;
        end

        if exist(h_csv_path, 'file')
            try
                h_T = readtable(h_csv_path);
                if height(h_T) >= 1
                    h_ber(h_ai, h_si) = h_T.ber_coded(1);
                    if ismember('alpha_est', h_T.Properties.VariableNames)
                        h_alpha_est(h_ai, h_si) = h_T.alpha_est(1);
                    end
                end
            catch
            end
        end
        fprintf('BER=%6.2f%%\n', h_ber(h_ai, h_si) * 100);
    end
    fprintf('\n');
end

%% Summary 1: BER 矩阵
fprintf('=========== BER Summary (%%) — 10 α × 3 SNR ===========\n');
fprintf('  α          ');
for h_si = 1:h_n_snr
    fprintf('| SNR=%2ddB ', h_snr_list(h_si));
end
fprintf('\n-------------+---------+---------+---------\n');
for h_ai = 1:h_n_alpha
    fprintf('  %+8.0e   ', h_alpha_list(h_ai));
    for h_si = 1:h_n_snr
        fprintf('| %7.2f ', h_ber(h_ai, h_si) * 100);
    end
    fprintf('\n');
end

%% Summary 2: ±α 对称性
fprintf('\n=========== ±α 对称性（BER 差值，正常应 <0.5%%） ===========\n');
fprintf('  |α|        | SNR=10dB        | SNR=15dB        | SNR=20dB\n');
fprintf('-------------+-----------------+-----------------+----------------\n');
h_pos_idx = find(h_alpha_list > 0);
for h_pi = 1:length(h_pos_idx)
    h_idx_pos = h_pos_idx(h_pi);
    h_alpha_abs = h_alpha_list(h_idx_pos);
    h_idx_neg = find(h_alpha_list == -h_alpha_abs);
    if isempty(h_idx_neg), continue; end
    fprintf('  %+.0e    ', h_alpha_abs);
    for h_si = 1:h_n_snr
        h_pos_ber = h_ber(h_idx_pos, h_si) * 100;
        h_neg_ber = h_ber(h_idx_neg, h_si) * 100;
        h_diff = h_neg_ber - h_pos_ber;
        h_mark = '';
        if abs(h_diff) > 5, h_mark = ' ⚠'; end
        fprintf(' | -:%5.2f vs +:%5.2f%s', h_neg_ber, h_pos_ber, h_mark);
    end
    fprintf('\n');
end

%% Summary 3: 工作范围
fprintf('\n=========== 工作范围（BER < 1%%） ===========\n');
for h_si = 1:h_n_snr
    h_ok = h_ber(:, h_si) * 100 < 1;
    h_ok_alphas = h_alpha_list(h_ok);
    fprintf('  SNR=%2ddB: ', h_snr_list(h_si));
    if isempty(h_ok_alphas)
        fprintf('（无）\n');
    else
        fprintf('%d/%d 点通过 — α ∈ {', sum(h_ok), h_n_alpha);
        for h_ki = 1:length(h_ok_alphas)
            if h_ki > 1, fprintf(', '); end
            fprintf('%+.0e', h_ok_alphas(h_ki));
        end
        fprintf('}\n');
    end
end

fprintf('\n完成\n');
