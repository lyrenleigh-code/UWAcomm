%% diag_D0_regression_check.m — SC-TDE 插桩不破坏默认路径 gate
%
% 目的：diag_* 全 false 时，插桩后的 runner 在 α=0 干净 static 场景下 BER 必须接近 0。
% 任何插桩破坏默认路径会在 α=0 场景暴露。
%
% 期望（参考 SC-TDE V5.1 调试日志）：
%   SNR=10 → BER ≤ 1.0%
%   SNR=15 → BER ≤ 0.5%
%   SNR=20 → BER ≤ 0.1%
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D0_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_snr_list = [10, 15, 20];
h_seed     = 42;
h_csv      = fullfile(h_out_dir, 'D0_regression.csv');
if exist(h_csv, 'file'), delete(h_csv); end

fprintf('========================================\n');
fprintf('  D0 — 回归 Gate（SC-TDE 插桩 α=0 baseline）\n');
fprintf('  α=0, SNR=[10,15,20] dB, seed=%d\n', h_seed);
fprintf('========================================\n\n');

benchmark_mode                 = true; %#ok<*NASGU>
bench_snr_list                 = h_snr_list;
bench_fading_cfgs              = { 'nominal', 'static', 0, 0 };
bench_channel_profile          = 'custom6';
bench_seed                     = h_seed;
bench_stage                    = 'D0';
bench_scheme_name              = 'SC-TDE';
bench_csv_path                 = h_csv;
bench_diag                     = struct('enable', false);
bench_toggles                  = struct();
bench_oracle_alpha             = false;
bench_oracle_passband_resample = false;
bench_use_real_doppler         = true;

% diag_* 全 false → 默认路径
diag_oracle_alpha = false;
diag_oracle_h     = false;
diag_use_ls       = false;
diag_turbo_iter   = [];
diag_dump_h       = false;

h_t0 = tic;
try
    run(h_runner);
catch ME
    fprintf('运行失败：%s\n', ME.message);
    return;
end
h_elapsed = toc(h_t0);
fprintf('\n总用时：%.1f s\n\n', h_elapsed);

%% Summary
fprintf('=========== D0 回归 Gate 结果 ===========\n');
if ~exist(h_csv, 'file')
    fprintf('  ✗ CSV 未生成：%s\n', h_csv);
    return;
end

T = readtable(h_csv);
h_ber   = T.ber_coded * 100;
h_snrs  = T.snr_db;

h_thresholds = [1.0, 0.5, 0.1];   % 对应 SNR=10/15/20 上限
h_pass = true;

fprintf('  SNR (dB) | BER (%%) | 上限 (%%) | 状态\n');
fprintf('-----------+---------+----------+------\n');
for k = 1:length(h_snr_list)
    idx = find(h_snrs == h_snr_list(k), 1);
    if isempty(idx)
        fprintf('    %2d     | ERR     |   %.2f   | ✗ 无数据\n', h_snr_list(k), h_thresholds(k));
        h_pass = false;
        continue;
    end
    b = h_ber(idx);
    if b <= h_thresholds(k)
        fprintf('    %2d     | %5.2f   |   %.2f   | ✓\n', h_snr_list(k), b, h_thresholds(k));
    else
        fprintf('    %2d     | %5.2f   |   %.2f   | ✗ 超限\n', h_snr_list(k), b, h_thresholds(k));
        h_pass = false;
    end
end

fprintf('\n=========== Gate 判定 ===========\n');
if h_pass
    fprintf('  ✓ 回归通过，插桩未破坏默认路径，可进 D1-D4 诊断\n');
else
    fprintf('  ✗ 回归失败！插桩破坏了默认路径，先修插桩再跑 diag\n');
end

fprintf('\n完成\n');
