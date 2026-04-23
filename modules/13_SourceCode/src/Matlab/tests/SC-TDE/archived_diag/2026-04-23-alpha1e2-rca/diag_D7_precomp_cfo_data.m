%% diag_D7_precomp_cfo_data.m — 数据段级 pre-CFO（保留 LFM 定时）
%
% 背景：D6 发现 bb_comp 级 pre-CFO 破坏 LFM 定时 36 samples
%   （120 Hz/chirp_rate=162000 Hz/s = 7.4e-4s × 48kHz = 35.6 sample）。
% 修正：pre-CFO 改在 `rx_data_bb = bb_comp(ds:de)` 提取之后做，LFM 定时完整。
% 时间轴从帧原点 (ds-1)/fs 起算，保持与原 bb_comp 时间基准一致。
%
% 矩阵：4 组 × 5 seed = 20 trial
%   G1: baseline              (全 false)
%   G2: +precomp_cfo_data     (仅 D7 toggle)  ← 关键对比
%   G3: +D7 + oracle_α        (D7 + oracle_α)
%   G4: +D7 + oracle_α + oracle_h
%
% 判据：
%   G2 mean BER <5%  → 根因锁定（pre-CFO 位置修正后）
%   G2 mean 5-30%    → 方向对但有次因
%   G2 mean >30%     → 仍不对，考虑 sps 相位搜索本身问题 / 多径耦合
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D7_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_alpha  = +1e-2;
h_snr    = 10;
h_seeds  = 1:5;
h_n_seed = length(h_seeds);

% 4 组：(precomp_data, oracle_α, oracle_h)
h_groups = {
    'G1_baseline',       false, false, false;
    'G2_D7only',         true,  false, false;
    'G3_D7_oa',          true,  true,  false;
    'G4_D7_oa_oh',       true,  true,  true;
};
h_n_grp = size(h_groups, 1);

h_ber = nan(h_n_grp, h_n_seed);

fprintf('========================================\n');
fprintf('  D7 — 数据段级 pre-CFO（保留 LFM 定时）\n');
fprintf('  α=%+.0e, SNR=%d dB, seeds=%d..%d, 4×5=%d trial\n', ...
    h_alpha, h_snr, h_seeds(1), h_seeds(end), h_n_grp*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_gi = 1:h_n_grp
    h_group_name = h_groups{h_gi, 1};
    h_precomp_d  = h_groups{h_gi, 2};
    h_oracle_a   = h_groups{h_gi, 3};
    h_oracle_h   = h_groups{h_gi, 4};
    fprintf('==========================================\n');
    fprintf('--- %s (D7_precomp=%d, oa=%d, oh=%d) ---\n', ...
        h_group_name, h_precomp_d, h_oracle_a, h_oracle_h);
    fprintf('==========================================\n');

    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv  = fullfile(h_out_dir, sprintf('D7_%s_seed%d.csv', h_group_name, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'D7';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;

        diag_oracle_alpha     = h_oracle_a;
        diag_oracle_h         = h_oracle_h;
        diag_use_ls           = false;
        diag_turbo_iter       = [];
        diag_dump_h           = false;
        diag_precomp_cfo      = false;         % D6 模式关
        diag_precomp_cfo_data = h_precomp_d;   % D7 模式按组开
        diag_dump_signal      = (h_di == 1);

        if diag_dump_signal
            fprintf('\nseed=%d:\n', h_seed);
            try
                run(h_runner);
            catch ME
                fprintf('ERR:%s\n', ME.message(1:min(end,50)));
                continue;
            end
        else
            try
                evalc('run(h_runner)');
            catch ME
                fprintf('  seed=%d ERR:%s\n', h_seed, ME.message(1:min(end,50)));
                continue;
            end
        end

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                if height(T) >= 1, h_ber(h_gi, h_di) = T.ber_coded(1); end
            catch, end
        end

        if ~diag_dump_signal
            b = h_ber(h_gi, h_di) * 100;
            if b < 1, mk='.'; elseif b < 30, mk='o'; else, mk='X'; end
            fprintf('  seed=%d: BER=%.2f%%[%s]\n', h_seed, b, mk);
        else
            b = h_ber(h_gi, h_di) * 100;
            fprintf('  → BER=%.2f%%\n', b);
        end
    end
    fprintf('\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Summary
fprintf('=========== D7 BER 汇总（α=+1e-2, SNR=%d dB）===========\n', h_snr);
fprintf('  group             | mean  | median | std   | min   | max   | 灾难率\n');
fprintf('--------------------+-------+--------+-------+-------+-------+--------\n');
for h_gi = 1:h_n_grp
    r = h_ber(h_gi, :) * 100;
    h_dis = sum(r > 30, 'omitnan');
    fprintf('  %-17s | %5.2f | %5.2f  | %5.2f | %5.2f | %5.2f | %d/%d\n', ...
        h_groups{h_gi,1}, ...
        mean(r,'omitnan'), median(r,'omitnan'), std(r,'omitnan'), ...
        min(r,[],'omitnan'), max(r,[],'omitnan'), ...
        h_dis, h_n_seed);
end

fprintf('\n=========== 判据 ===========\n');
m_g1 = mean(h_ber(1,:)*100,'omitnan');
m_g2 = mean(h_ber(2,:)*100,'omitnan');
m_g3 = mean(h_ber(3,:)*100,'omitnan');
m_g4 = mean(h_ber(4,:)*100,'omitnan');
fprintf('  G1 baseline             : %.2f%%\n', m_g1);
fprintf('  G2 D7 only              : %.2f%%  ← 关键\n', m_g2);
fprintf('  G3 D7 + oracle_α        : %.2f%%\n', m_g3);
fprintf('  G4 D7 + oracle_α+h      : %.2f%%\n', m_g4);
fprintf('\n');

if m_g2 < 5
    fprintf('  ✓✓✓ G2=%.2f%% <5%% → 根因锁定且位置正确\n', m_g2);
    fprintf('      → 开 fix spec：把数据段级 pre-CFO 固化到 SC-TDE runner（默认开）\n');
    fprintf('      → 横向检查：DSSS/OFDM/FH-MFSK/SC-FDE 是否有同类 bug\n');
elseif m_g2 < 30
    fprintf('  ⚠ G2=%.2f%% 部分救回 → 主因正确，剩余来自：\n', m_g2);
    if m_g3 < 5
        fprintf('      α 估计残差（G3 好于 G2 → %.2f%% vs %.2f%%）\n', m_g3, m_g2);
    end
    if m_g4 < m_g3
        fprintf('      信道估计残差（G4 好于 G3 → %.2f%% vs %.2f%%）\n', m_g4, m_g3);
    end
elseif m_g2 >= 30
    fprintf('  ✗ G2=%.2f%% 仍灾难 → 数据段级 pre-CFO 也不够\n', m_g2);
    fprintf('      → 深入考虑：sps 相位搜索用 tx_sym（含 data）本身的合理性\n');
    fprintf('        / 多径 ISI 与 CFO 耦合 / training 随机生成的稀疏 rng 影响\n');
    fprintf('      → 观察上方 [DIAG-S] 的 corr(1:50) 是否恢复到 >0.5\n');
end

fprintf('\n完成\n');
