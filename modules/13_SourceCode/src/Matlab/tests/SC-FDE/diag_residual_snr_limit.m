%% diag_residual_snr_limit.m
% L6 步：剩余 2/30 灾难是否 SNR 受限？
%
% L6e 修复后还剩 α=+1e-2 seed=17 (30.6%) / seed=26 (30.6%) 灾难。
% 测试这两个是否在 SNR=15/20 dB 自然恢复（→ 归 SNR limitation）。
%
% 矩阵：α=+1e-2 × seed ∈ {17, 26} × SNR ∈ {10, 15, 20} = 6 trial
%
% 对照：α=+1e-2 seed=1（已知健康）× SNR ∈ {10, 15, 20} = 3 trial
%
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_residual_snr_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

h_alpha   = +1e-2;
h_seeds   = [1, 17, 26];   % 1=对照，17/26=L6e 残余灾难
h_snrs    = [10, 15, 20];
h_n_seed  = length(h_seeds);
h_n_snr   = length(h_snrs);

h_ber = nan(h_n_seed, h_n_snr);

fprintf('========================================\n');
fprintf('  L6e 残余灾难 × 高 SNR 验证（α=+1e-2）\n');
fprintf('========================================\n\n');

for h_di = 1:h_n_seed
    h_seed = h_seeds(h_di);
    fprintf('--- seed=%d ---\n', h_seed);
    for h_si = 1:h_n_snr
        h_snr = h_snrs(h_si);
        h_csv = fullfile(h_out_dir, sprintf('s%d_snr%d.csv', h_seed, h_snr));
        if exist(h_csv, 'file'), delete(h_csv); end

        fprintf('  SNR=%2d ', h_snr);

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha, 1024, 128, 4 };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'diag';
        bench_scheme_name              = 'SC-FDE';
        bench_csv_path                 = h_csv;
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

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                if height(T) >= 1, h_ber(h_di, h_si) = T.ber_coded(1); end
            catch
            end
        end
        fprintf('BER=%6.2f%%\n', h_ber(h_di, h_si) * 100);
    end
    fprintf('\n');
end

%% Summary
fprintf('=========== 矩阵 ===========\n');
fprintf('  seed   | SNR=10  | SNR=15  | SNR=20\n');
fprintf('---------+---------+---------+---------\n');
for h_di = 1:h_n_seed
    fprintf('  %-5d  ', h_seeds(h_di));
    for h_si = 1:h_n_snr
        fprintf('| %6.2f%% ', h_ber(h_di, h_si) * 100);
    end
    fprintf('\n');
end

%% 判定
fprintf('\n=========== 判定 ===========\n');
for h_di = 2:h_n_seed   % 跳过 s1 对照
    h_row = h_ber(h_di, :) * 100;
    fprintf('  seed=%d: BER %.2f → %.2f → %.2f', ...
        h_seeds(h_di), h_row(1), h_row(2), h_row(3));
    if h_row(end) < 1
        fprintf(' → ✓ SNR 受限（高 SNR 救活，归档为 limitation）\n');
    elseif h_row(end) < h_row(1) * 0.3
        fprintf(' → 🟡 部分 SNR 受限\n');
    else
        fprintf(' → ❌ 非 SNR 受限（仍灾难）→ 继续 L6f \\|h\\| sanity check\n');
    end
end

fprintf('\n完成\n');
