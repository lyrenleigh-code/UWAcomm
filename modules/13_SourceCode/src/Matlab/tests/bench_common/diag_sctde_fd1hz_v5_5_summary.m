%% diag_sctde_fd1hz_v5_5_summary.m
% V5.5 fix verify 总结：base (iter=2) vs V5.5 fix (iter=0 fd=1Hz) vs oracle α
%
% 数据源：
%   alpha_err_summary.mat — base (iter=2) 数据（Phase 1.2 跑出）
%   phase2_summary.mat    — V5.5 fix proxy（phase2 cond1: iter=0 + sub=ON）
%   h4_oracle_full.mat    — oracle baseline
%
% 输出：三方头对头对比表 + spec 接受准则达成度
%
% 版本：V1.0.0 (2026-04-25)

clear; close all;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_sctde_fd1hz_out');

%% 加载三方数据
m_base   = load(fullfile(h_out_dir, 'alpha_err_summary.mat'));
m_fix    = load(fullfile(h_out_dir, 'phase2_summary.mat'));
m_oracle = load(fullfile(h_out_dir, 'h4_oracle_full.mat'));

T_base   = m_base.T_fd1;          % iter=2, sub=ON
T_fix    = m_fix.T_on(m_fix.T_on.fd_hz == 1, :);   % iter=0, sub=ON
ber_oracle = m_oracle.h_ber_oracle;     % (3 SNR × 15 seed) oracle α

snr_list = [10, 15, 20];
n_seed   = 15;
thresh_dis = 5;

%% 对比
fprintf('\n========== SC-TDE fd=1Hz V5.5 fix verify ==========\n');
fprintf('数据：default fading_cfgs × 15 seed × SNR={10,15,20}\n');
fprintf('指标：mean BER / 灾难率（>5%%）\n\n');

fprintf('%-5s | %-23s | %-23s | %-23s\n', 'SNR', ...
    'V5.4 baseline (iter=2)', 'V5.5 fix (iter=0)', 'Oracle α');
fprintf('%-5s | mean BER  | 灾难率   | mean BER  | 灾难率   | mean BER  | 灾难率\n', '');
fprintf('%s\n', repmat('-', 1, 110));

for s_i = 1:length(snr_list)
    snr = snr_list(s_i);
    m1 = T_base.snr_db == snr;
    m2 = T_fix.snr_db == snr;
    b_base = T_base.ber_coded(m1) * 100;
    b_fix  = T_fix.ber_coded(m2) * 100;
    b_or   = ber_oracle(s_i, :) * 100;

    mean_base = mean(b_base);  dis_base = sum(b_base > thresh_dis) / n_seed * 100;
    mean_fix  = mean(b_fix);   dis_fix  = sum(b_fix  > thresh_dis) / n_seed * 100;
    mean_or   = mean(b_or, 'omitnan');  dis_or = sum(b_or > thresh_dis, 'omitnan') / n_seed * 100;

    fprintf('  %2d  | %7.2f%% | %6.1f%% | %7.2f%% | %6.1f%% | %7.2f%% | %6.1f%%\n', ...
        snr, mean_base, dis_base, mean_fix, dis_fix, mean_or, dis_or);
end

%% 单调性
fprintf('\n========== 单调性（mean BER）==========\n');
mean_base_arr = nan(1,3); mean_fix_arr = nan(1,3); mean_or_arr = nan(1,3);
for s_i = 1:length(snr_list)
    m1 = T_base.snr_db == snr_list(s_i);
    m2 = T_fix.snr_db  == snr_list(s_i);
    mean_base_arr(s_i) = mean(T_base.ber_coded(m1)) * 100;
    mean_fix_arr(s_i)  = mean(T_fix.ber_coded(m2)) * 100;
    mean_or_arr(s_i)   = mean(ber_oracle(s_i, :), 'omitnan') * 100;
end
mono_base = all(diff(mean_base_arr) <= 0);
mono_fix  = all(diff(mean_fix_arr) <= 0);
mono_or   = all(diff(mean_or_arr) <= 0);
fprintf('  base   mean: %.2f → %.2f → %.2f, 单调 = %d\n', mean_base_arr, mono_base);
fprintf('  V5.5   mean: %.2f → %.2f → %.2f, 单调 = %d\n', mean_fix_arr, mono_fix);
fprintf('  oracle mean: %.2f → %.2f → %.2f, 单调 = %d\n', mean_or_arr, mono_or);

%% Spec 接受准则
fprintf('\n========== Spec 接受准则达成度 ==========\n');
target_mean_20 = 1.5;
target_dis_20  = 15;
m2_20 = T_fix.snr_db == 20;
fix_mean_20 = mean(T_fix.ber_coded(m2_20)) * 100;
fix_dis_20  = sum(T_fix.ber_coded(m2_20) > 0.05) / n_seed * 100;

fprintf('  SNR=15 mean ≤ 3%%   : V5.5=%.2f%%   %s\n', mean_fix_arr(2), tick(mean_fix_arr(2) <= 3));
fprintf('  SNR=15 灾难率 ≤ 25%%: V5.5=%.1f%%   %s\n', ...
    sum(T_fix.ber_coded(T_fix.snr_db==15) > 0.05) / n_seed * 100, ...
    tick(sum(T_fix.ber_coded(T_fix.snr_db==15) > 0.05) / n_seed * 100 <= 25));
fprintf('  SNR=20 mean ≤ %.1f%%: V5.5=%.2f%%   %s\n', target_mean_20, fix_mean_20, tick(fix_mean_20 <= target_mean_20));
fprintf('  SNR=20 灾难率 ≤ %d%% : V5.5=%.1f%%   %s\n', target_dis_20, fix_dis_20, tick(fix_dis_20 <= target_dis_20));
fprintf('  单调性 ✓             : V5.5=%d        %s\n', mono_fix, tick(mono_fix));

%% 持久化
h_mat = fullfile(h_out_dir, 'v5_5_summary.mat');
save(h_mat, 'T_base', 'T_fix', 'ber_oracle', 'mean_base_arr', 'mean_fix_arr', 'mean_or_arr', ...
           'mono_base', 'mono_fix', 'mono_or');
fprintf('\n.mat 持久化：%s\n完成\n', h_mat);

function s = tick(b)
if b, s = '✓ PASS'; else, s = '✗ FAIL'; end
end
