%% diag_sctde_fd1hz_hfm_invariance.m
% V1.2 path A 探索：HFM peak Doppler-invariance 验证
%
% 假设：HFM 是 Doppler-invariant chirp，fd=1Hz Jakes 时变下 peak 位置（dtau）
%       std 应小于 LFM dual-chirp 的 dtau std
%
% 数据：fd={0, 1, 5}Hz × 15 seed × SNR=20 × default 3 fading
% 字段（runner V1.2 path A 暴露）：
%   diag_hfm_dtau_diff  — HFM dtau obs - nom（样本数，整数）
%   diag_dtau_resid_s   — LFM dual-chirp 残差时间差（秒）
% 比较：
%   HFM std (samples)   vs   LFM std (转换为 samples)
%   HFM mean drift      vs   LFM mean drift
%   bad seed HFM/LFM 对比 vs good seed
%
% 输出：HFM-LFM 一致性比较 + 是否值得 V1.2 path A 投资判定
% 版本：V1.0.0 (2026-04-25)

clear functions; clear; close all; clc;

%% 参数
h_this_dir  = fileparts(mfilename('fullpath'));
h_tests_dir = fileparts(h_this_dir);
h_runner    = fullfile(h_tests_dir, 'SC-TDE', 'test_sctde_timevarying.m');
h_out_dir   = fullfile(h_this_dir, 'diag_sctde_fd1hz_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

h_seeds    = 1:15;
h_n_seed   = length(h_seeds);
h_csv_master = fullfile(h_out_dir, 'hfm_invariance_summary.csv');
if exist(h_csv_master, 'file'), delete(h_csv_master); end

fprintf('========================================\n');
fprintf('  V1.2 path A · HFM peak Doppler-invariance 验证\n');
fprintf('  15 seed × SNR=20 × 3 fading（fd={0,1,5}Hz）\n');
fprintf('========================================\n\n');

h_t0 = tic;
for h_di = 1:h_n_seed
    h_seed = h_seeds(h_di);
    h_csv_trial = fullfile(h_out_dir, sprintf('hfm_inv_seed%d_snr20.csv', h_seed));
    if exist(h_csv_trial, 'file'), delete(h_csv_trial); end

    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = 20;
    bench_channel_profile          = 'custom6';
    bench_seed                     = h_seed;
    bench_stage                    = 'v12-hfm-invariance';
    bench_scheme_name              = 'SC-TDE';
    bench_csv_path                 = h_csv_trial;
    bench_diag                     = struct('enable', false);
    bench_toggles                  = struct();
    bench_oracle_alpha             = false;
    bench_oracle_passband_resample = false;
    bench_use_real_doppler         = true;
    diag_oracle_alpha              = false;
    bench_alpha_iter               = 0;     % V5.5 fd=1Hz default

    try
        evalc('run(h_runner)');
    catch ME
        fprintf('s%d[ERR:%s] ', h_seed, ME.identifier);
        continue;
    end

    if exist(h_csv_trial, 'file')
        try
            T_trial = readtable(h_csv_trial);
            if exist(h_csv_master, 'file')
                T_acc = readtable(h_csv_master);
                T_acc = [T_acc; T_trial]; %#ok<AGROW>
                writetable(T_acc, h_csv_master);
            else
                writetable(T_trial, h_csv_master);
            end
        catch
        end
    end
    fprintf('s%d ', h_seed);
    if mod(h_di, 5) == 0 && h_di < h_n_seed, fprintf('\n  '); end
end
fprintf('\n总用时：%.2f min\n\n', toc(h_t0)/60);

%% 分析
T = readtable(h_csv_master);
fprintf('累积行数：%d\n\n', height(T));

% 假设 fs=48000（runner 默认 sym_rate*sps=6000*8）
fs = 48000;

%% 各 fading 分组对比 HFM vs LFM
for h_fd = [0, 1, 5]
    Tf = T(T.fd_hz == h_fd, :);
    if isempty(Tf), continue; end

    % LFM dtau resid（秒 → 样本）
    lfm_dtau_diff_samp = Tf.diag_dtau_resid_s * fs;
    % HFM dtau diff（已经是样本数）
    hfm_dtau_diff_samp = Tf.diag_hfm_dtau_diff;

    fprintf('============ fd=%dHz (n=%d) ============\n', h_fd, height(Tf));
    fprintf('  Metric          | LFM (dtau samples) | HFM (dtau samples)\n');
    fprintf('-----------------+--------------------+--------------------\n');
    fprintf('  mean            | %+18.4f | %+18.4f\n', mean(lfm_dtau_diff_samp), mean(hfm_dtau_diff_samp));
    fprintf('  std             | %18.4f | %18.4f\n',   std(lfm_dtau_diff_samp),  std(hfm_dtau_diff_samp));
    fprintf('  abs(mean)/std   | %18.4f | %18.4f\n',   abs(mean(lfm_dtau_diff_samp))/(std(lfm_dtau_diff_samp)+eps), ...
                                                       abs(mean(hfm_dtau_diff_samp))/(std(hfm_dtau_diff_samp)+eps));
    fprintf('  range           | %.2f .. %.2f       | %d .. %d\n', ...
        min(lfm_dtau_diff_samp), max(lfm_dtau_diff_samp), min(hfm_dtau_diff_samp), max(hfm_dtau_diff_samp));
    fprintf('\n');
end

%% fd=1Hz 详细：bad vs good seed 的 LFM/HFM 表现
fprintf('============ fd=1Hz bad/good seed 对比 ============\n');
T1 = T(T.fd_hz == 1, :);
m_bad  = T1.ber_coded > 0.05;
m_good = T1.ber_coded <= 0.05;

fprintf('  Group | n | LFM dtau samp mean (std) | HFM dtau samp mean (std) | err_L0 mean | BER mean\n');
fprintf('--------+---+--------------------------+--------------------------+-------------+----------\n');
for grp = {'bad', 'good'}
    if strcmp(grp{1}, 'bad'),  Tg = T1(m_bad,  :); else, Tg = T1(m_good, :); end
    lfm_ds = Tg.diag_dtau_resid_s * fs;
    hfm_ds = Tg.diag_hfm_dtau_diff;
    err_L0 = Tg.alpha_lfm_raw - Tg.doppler_rate;
    fprintf('  %-6s | %d | %+10.4f (%.4f)   | %+10.4f (%.4f)   | %+.3e | %.2f%%\n', ...
        grp{1}, height(Tg), mean(lfm_ds), std(lfm_ds), mean(hfm_ds), std(hfm_ds), ...
        mean(err_L0), mean(Tg.ber_coded)*100);
end

%% V1.2 path A 投资判定
fprintf('\n============ V1.2 path A 投资判定 ============\n');
T1 = T(T.fd_hz == 1, :);
lfm_std = std(T1.diag_dtau_resid_s * fs);
hfm_std = std(double(T1.diag_hfm_dtau_diff));
lfm_abs_mean = abs(mean(T1.diag_dtau_resid_s * fs));
hfm_abs_mean = abs(mean(double(T1.diag_hfm_dtau_diff)));
fprintf('  fd=1Hz LFM std   = %.4f samples\n', lfm_std);
fprintf('  fd=1Hz HFM std   = %.4f samples\n', hfm_std);
fprintf('  fd=1Hz LFM |mean| = %.4f samples (deterministic bias)\n', lfm_abs_mean);
fprintf('  fd=1Hz HFM |mean| = %.4f samples\n', hfm_abs_mean);

if hfm_std < lfm_std * 0.5 && hfm_abs_mean < lfm_abs_mean * 0.5
    fprintf('  ✓ HFM 比 LFM 更稳定（std 和 mean 偏差都 ≤ 50%%）→ V1.2 path A 值得投资\n');
elseif hfm_std < lfm_std
    fprintf('  🟡 HFM std 较小但 mean 偏差不显著降低 → V1.2 path A 边际收益\n');
else
    fprintf('  ✗ HFM 不比 LFM 更稳定 → V1.2 path A 假设不成立，转 path D（estimator-外灾难）\n');
end

%% 持久化
h_mat = fullfile(h_out_dir, 'hfm_invariance_summary.mat');
save(h_mat, 'T');
fprintf('\n.mat 持久化：%s\n完成\n', h_mat);
