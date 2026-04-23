%% diag_D0b_regression_multiseed.m — 多 seed 插桩回归 Gate
%
% 背景：D0 seed=42 在 SNR=15 出现 4.95% BER（非单调），与 SC-FDE Phase J
%   ~10% deterministic 灾难触发形态一致。无法单 seed 判定是"插桩破坏"还是
%   "SC-TDE 本身稀有触发"。
%
% 方法：α=0 static × SNR=[10,15,20] × seed ∈ {1,7,42,100,200}（5 seed）
% 判据（多 seed 放宽版）：
%   mean BER ≤ 2% 且每个 SNR ≥4/5 seed 过严阈值 → 插桩 OK，SC-TDE 稀有触发
%   mean BER > 2% 或 ≤2/5 seed 过 → 插桩可能破坏默认路径
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D0b_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_snr_list = [10, 15, 20];
h_seeds    = [1, 7, 42, 100, 200];
h_n_seed   = length(h_seeds);
h_n_snr    = length(h_snr_list);

h_ber = nan(h_n_seed, h_n_snr);

fprintf('========================================\n');
fprintf('  D0b — 多 seed 回归 Gate（SC-TDE α=0 baseline）\n');
fprintf('  α=0, SNR=[10,15,20], seeds=%s\n', mat2str(h_seeds));
fprintf('========================================\n\n');

h_t0 = tic;
for h_di = 1:h_n_seed
    h_seed = h_seeds(h_di);
    h_csv  = fullfile(h_out_dir, sprintf('D0b_seed%d.csv', h_seed));
    if exist(h_csv, 'file'), delete(h_csv); end

    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = h_snr_list;
    bench_fading_cfgs              = { 'nominal', 'static', 0, 0 };
    bench_channel_profile          = 'custom6';
    bench_seed                     = h_seed;
    bench_stage                    = 'D0b';
    bench_scheme_name              = 'SC-TDE';
    bench_csv_path                 = h_csv;
    bench_diag                     = struct('enable', false);
    bench_toggles                  = struct();
    bench_oracle_alpha             = false;
    bench_oracle_passband_resample = false;
    bench_use_real_doppler         = true;

    diag_oracle_alpha = false;
    diag_oracle_h     = false;
    diag_use_ls       = false;
    diag_turbo_iter   = [];
    diag_dump_h       = false;

    fprintf('seed=%3d: ', h_seed);
    try
        evalc('run(h_runner)');
    catch ME
        fprintf('ERR:%s\n', ME.message(1:min(end,50)));
        continue;
    end

    if exist(h_csv, 'file')
        try
            T = readtable(h_csv);
            for k = 1:h_n_snr
                idx = find(T.snr_db == h_snr_list(k), 1);
                if ~isempty(idx)
                    h_ber(h_di, k) = T.ber_coded(idx);
                end
            end
        catch, end
    end

    for k = 1:h_n_snr
        b = h_ber(h_di, k) * 100;
        if b < 1, mk='.'; elseif b < 5, mk='o'; else, mk='X'; end
        fprintf('%ddB=%5.2f%%[%s]  ', h_snr_list(k), b, mk);
    end
    fprintf('\n');
end
h_elapsed = toc(h_t0);
fprintf('\n总用时：%.1f s\n\n', h_elapsed);

%% Summary
fprintf('=========== D0b 结果矩阵 ===========\n');
fprintf('  seed ');
for k = 1:h_n_snr, fprintf('| %5ddB', h_snr_list(k)); end
fprintf('\n');
fprintf('-------');
for k = 1:h_n_snr, fprintf('+--------'); end
fprintf('\n');
for h_di = 1:h_n_seed
    fprintf('  %3d  ', h_seeds(h_di));
    for k = 1:h_n_snr
        fprintf('| %5.2f%% ', h_ber(h_di, k)*100);
    end
    fprintf('\n');
end

fprintf('\n=========== 统计 per SNR ===========\n');
fprintf('  SNR | mean  | median | max  | >1%% seed\n');
fprintf('------+-------+--------+------+----------\n');
h_strict_thresh = [1.0, 0.5, 0.1];
h_pass_loose = true;
for k = 1:h_n_snr
    r = h_ber(:, k) * 100;
    n_bad = sum(r > h_strict_thresh(k), 'omitnan');
    fprintf('  %2d  | %5.2f | %5.2f  | %5.2f | %d/%d > %.2f%%\n', ...
        h_snr_list(k), mean(r,'omitnan'), median(r,'omitnan'), max(r,[],'omitnan'), ...
        n_bad, h_n_seed, h_strict_thresh(k));
    if mean(r,'omitnan') > 2.0, h_pass_loose = false; end
end

fprintf('\n=========== Gate 判定 ===========\n');
if h_pass_loose
    fprintf('  ✓ 每个 SNR mean ≤ 2%% → 插桩 OK（SNR=15 单 seed 触发属 SC-TDE 本身 ~10%% 灾难率）\n');
    fprintf('    → 进 D1-D4 诊断，多 seed 平均能稀释单点异常\n');
else
    fprintf('  ✗ 有 SNR mean > 2%% → 插桩可能破坏默认路径\n');
    fprintf('    → 建议 git diff HEAD 看插桩改动，或 git stash 后重跑对比\n');
end

fprintf('\n完成\n');
