%% diag_sctde_fd1hz_replay_seed42.m
% 阶段 1.5：bench_seed=42 复现验证
%
% 目标：bench_seed=42 时 runner 注入公式 (bench_seed-42)*100000 = 0，
%       等同 default 无注入路径，应能复现 spec 引用的历史表。
%
% spec 历史表（plan A 全 skip post-CFO，fd=1Hz）:
%   SNR=5  → 21.70%
%   SNR=10 → 17.39%
%   SNR=15 → 27.96%
%   SNR=20 →  0.00%   ← 关键"高 SNR 救回"点
%
% 实测 1..15 seed Monte Carlo 全部 40%+ 灾难，违背上表。
% 本脚本以 seed=42 单 trial × 4 SNR 一次跑完判定：
%
%   - 复现 spec 表（误差 <5pp）→ bench_seed 注入对 fd=1Hz 敏感（H_new2）
%   - 不复现（仍 40%+）→ V5.4 整体退化或 spec 历史表本就不可信（H_new1）
%
% 版本：V1.0.0（2026-04-24）

clear functions; clear; close all; clc;

%% 参数
h_this_dir  = fileparts(mfilename('fullpath'));
h_tests_dir = fileparts(h_this_dir);
h_runner    = fullfile(h_tests_dir, 'SC-TDE', 'test_sctde_timevarying.m');
h_out_dir   = fullfile(h_this_dir, 'diag_sctde_fd1hz_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

h_fc       = 12000;
h_snr_list = [5, 10, 15, 20];
h_seed     = 42;
h_n_snr    = length(h_snr_list);
% 不覆盖 bench_fading_cfgs → runner 走 default 3 行 {static, fd=1Hz, fd=5Hz}
% 关键：runner 内部 rng seed 依赖 fi（行号），V5.4 验证时 fd=1Hz 是 fi=2
% 跑完从 CSV 按 fd_hz==1 筛行即可

% spec 历史参考
h_spec_ref = [21.70, 17.39, 27.96, 0.00];

h_ber = nan(1, h_n_snr);

fprintf('========================================\n');
fprintf('  SC-TDE fd=1Hz · 阶段 1.5 · seed=%d 复现\n', h_seed);
fprintf('  SNR=%s, fading=default 3行（筛 fd=1Hz 即 fi=2）\n', mat2str(h_snr_list));
fprintf('========================================\n\n');

h_csv = fullfile(h_out_dir, sprintf('SCTDE_seed%d_snr_sweep.csv', h_seed));
if exist(h_csv, 'file'), delete(h_csv); end

%% 单次 runner 调用：default 3 行 fading × 4 SNR = 12 trial
benchmark_mode                 = true; %#ok<*NASGU>
bench_snr_list                 = h_snr_list;
% 故意不设 bench_fading_cfgs：让 runner 走 default 3 行 {static, fd=1Hz, fd=5Hz}
bench_channel_profile          = 'custom6';
bench_seed                     = h_seed;
bench_stage                    = 'fd1hz-replay-seed42';
bench_scheme_name              = 'SC-TDE';
bench_csv_path                 = h_csv;
bench_diag                     = struct('enable', false);
bench_toggles                  = struct();
bench_oracle_alpha             = false;
bench_oracle_passband_resample = false;
bench_use_real_doppler         = true;

h_t0 = tic;
try
    evalc('run(h_runner)');
catch ME
    fprintf('[ERR] %s\n', ME.message);
    return;
end
h_elapsed = toc(h_t0);
fprintf('runner 用时：%.2f min\n\n', h_elapsed/60);

%% 读 CSV 取 BER（筛 fd_hz==1 即 fi=2 行）
if exist(h_csv, 'file')
    T = readtable(h_csv);
    fprintf('CSV 行数=%d（期望 12 = 3 fading × 4 SNR）\n', height(T));
    for h_si = 1:h_n_snr
        % 按 snr_db + fd_hz==1 双条件匹配
        h_idx = find(T.snr_db == h_snr_list(h_si) & T.fd_hz == 1, 1);
        if ~isempty(h_idx)
            h_ber(h_si) = T.ber_coded(h_idx);
        end
    end
else
    fprintf('[ERR] CSV 未生成：%s\n', h_csv);
    return;
end

%% 对比表
fprintf('=========== 复现对比表（fd=1Hz, seed=%d）===========\n', h_seed);
fprintf('  SNR  | spec 历史 | 实测 BER | 差异(pp) | 判定\n');
fprintf('-------+-----------+----------+----------+--------\n');
h_match_all = true;
for h_si = 1:h_n_snr
    r = h_ber(h_si) * 100;
    d = r - h_spec_ref(h_si);
    if abs(d) < 5
        h_mk = '✓ 复现';
    elseif abs(d) < 15
        h_mk = '~ 偏差';
        h_match_all = false;
    else
        h_mk = '✗ 不符';
        h_match_all = false;
    end
    fprintf('  %3d  | %8.2f%% | %7.2f%% | %+8.2f | %s\n', ...
        h_snr_list(h_si), h_spec_ref(h_si), r, d, h_mk);
end

%% 关键判定（SNR=20 0% 救回点）
fprintf('\n=========== 关键判定 ===========\n');
h_snr20_idx = find(h_snr_list == 20, 1);
if ~isempty(h_snr20_idx) && ~isnan(h_ber(h_snr20_idx))
    h_snr20_ber = h_ber(h_snr20_idx) * 100;
    if h_snr20_ber < 1
        fprintf('  ✓ SNR=20 = %.2f%%（< 1%%）— 复现 spec "高 SNR 救回"\n', h_snr20_ber);
        fprintf('  → bench_seed 注入对 fd=1Hz 敏感（H_new2）\n');
        fprintf('  → 1..15 seed MC 100%% 灾难是 seed≠42 时的真实现象\n');
    elseif h_snr20_ber < 10
        fprintf('  🟡 SNR=20 = %.2f%%（介于）— 部分救回\n', h_snr20_ber);
    else
        fprintf('  ✗ SNR=20 = %.2f%%（> 10%%）— 不复现 spec 0%% 救回\n', h_snr20_ber);
        fprintf('  → V5.4 整体退化（H_new1），需 git checkout V5.3 对照\n');
        fprintf('  → spec 历史 0%% 数据可能来自 bench_seed 注入前的 V5.2 时代\n');
    end
end

%% 综合判定
fprintf('\n=========== 综合判定 ===========\n');
if h_match_all
    fprintf('  ✓ 全 4 SNR 复现 spec 历史表（误差 <5pp 各点）\n');
    fprintf('  → 进 spec H_new2：跑 bench_seed offset 公式诊断\n');
else
    fprintf('  ✗ 复现失败 → 进 spec H_new1：V5.3 git checkout 对照\n');
end

fprintf('\n完成\n');
