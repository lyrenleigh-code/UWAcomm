%% diag_D6_precomp_cfo.m — 验证 fc·α 频偏在 sps 搜索前补偿能否拯救 BER
%
% 假设：D5 发现 rx_sym_recv 与 training 相关系数 ≈ 0.055（噪声级），SNR_emp=-3.2dB。
% 推断：bb_raw 里的 fc·α=120 Hz 频偏未在 sps 相位搜索之前消除，导致相干累加被
% 相位旋转稀释。comp_resample 只做时间伸缩，不处理频偏。
%
% 验证方法：toggle `diag_precomp_cfo=true` 在 bb_comp 上做 `exp(-j·2π·α·fc·t)` 频偏
% 补偿（sps 搜索之前），同时禁用原 line 437 符号级补偿（避免双重）。
%
% 矩阵：4 组 × 5 seed = 20 trial
%   G1: baseline              (precomp=F, oracle_α=F, oracle_h=F)
%   G2: +precomp_cfo          (precomp=T, oracle_α=F, oracle_h=F)  ← 关键对比
%   G3: +precomp + oracle_α   (precomp=T, oracle_α=T, oracle_h=F)
%   G4: +precomp + oracle_α+h (precomp=T, oracle_α=T, oracle_h=T)
%
% 判据：
%   G2 mean BER <5%  → 假设成立，根因锁定（fc·α 残余频偏 + 补偿顺序错）
%   G2 mean BER 5-30% → 部分救回，还有次因
%   G2 mean BER >30% → 假设证伪，重审
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D6_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_alpha  = +1e-2;
h_snr    = 10;
h_seeds  = 1:5;
h_n_seed = length(h_seeds);

% 4 组：(precomp_cfo, oracle_α, oracle_h)
h_groups = {
    'G1_baseline',     false, false, false;
    'G2_precomp',      true,  false, false;
    'G3_precomp_oa',   true,  true,  false;
    'G4_precomp_oa_oh',true,  true,  true;
};
h_n_grp = size(h_groups, 1);

h_ber = nan(h_n_grp, h_n_seed);

fprintf('========================================\n');
fprintf('  D6 — pre-CFO 验证（SC-TDE α=+1e-2 RCA）\n');
fprintf('  α=%+.0e, SNR=%d dB, seeds=%d..%d, 4×5=%d trial\n', ...
    h_alpha, h_snr, h_seeds(1), h_seeds(end), h_n_grp*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_gi = 1:h_n_grp
    h_group_name = h_groups{h_gi, 1};
    h_precomp    = h_groups{h_gi, 2};
    h_oracle_a   = h_groups{h_gi, 3};
    h_oracle_h   = h_groups{h_gi, 4};
    fprintf('==========================================\n');
    fprintf('--- %s (precomp=%d, oa=%d, oh=%d) ---\n', h_group_name, h_precomp, h_oracle_a, h_oracle_h);
    fprintf('==========================================\n');

    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv  = fullfile(h_out_dir, sprintf('D6_%s_seed%d.csv', h_group_name, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'D6';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;

        diag_oracle_alpha = h_oracle_a;
        diag_oracle_h     = h_oracle_h;
        diag_use_ls       = false;
        diag_turbo_iter   = [];
        diag_dump_h       = false;
        diag_precomp_cfo  = h_precomp;
        % 每组首 seed 打印信号层 diag（验证 corr 是否从 0.055 恢复到 ~0.7）
        diag_dump_signal  = (h_di == 1);

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
fprintf('=========== D6 BER 汇总（α=+1e-2, SNR=%d dB）===========\n', h_snr);
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
fprintf('  G2 +precomp_cfo         : %.2f%%\n', m_g2);
fprintf('  G3 +precomp + oracle_α  : %.2f%%\n', m_g3);
fprintf('  G4 +precomp + oracle_α+h: %.2f%%\n', m_g4);
fprintf('\n');

if m_g2 < 5
    fprintf('  ✓✓ G2 mean=%.2f%% <5%% → 根因锁定：fc·α 残余频偏 + 补偿顺序错\n', m_g2);
    fprintf('      → 下一步：开 fix spec，把 pre-CFO 补偿固化到 runner\n');
    fprintf('      → 同时检查其他 5 体制是否有同问题（DSSS/OFDM/FH-MFSK/SC-FDE）\n');
elseif m_g2 < 30
    fprintf('  ⚠ G2 mean=%.2f%% 部分恢复 → 主因正确，但还有次因\n', m_g2);
    if m_g3 < 5
        fprintf('      → G3 回到 <5%%，说明 α 估计残差 %.1e 也有影响\n', 1e-5);
    end
elseif m_g2 >= 30
    fprintf('  ✗ G2 mean=%.2f%% 仍灾难 → 假设证伪，重审（可能是 group delay/多径耦合/其他）\n', m_g2);
end

if m_g4 < 5 && m_g2 > 30
    fprintf('  注：G4 mean=%.2f%% <5%% 但 G2 >30%% → 需要 oracle α+h 才能救，pre-CFO 不够\n', m_g4);
end

fprintf('\n完成\n');
