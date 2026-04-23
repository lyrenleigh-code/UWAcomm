%% diag_D2_oracle_h.m — SC-TDE α=+1e-2 灾难 RCA 第 2 步
%
% 目的：剥离 GAMP 估计误差，看 Turbo 在"完美信道"下是否仍灾难。
% 4 组正交组合（α × h）覆盖所有 oracle 组合，区分 α 和 h 哪个占主导。
%
% 配置：α=+1e-2 / SNR=10 / custom6 / static / seed 1..5
% 矩阵：(oracle_α, oracle_h) ∈ {(F,F), (T,F), (F,T), (T,T)} × 5 seed = 20 trial
%
% 判据：
%   (F,T) mean<5%   → GAMP 是直接根因（H1 confirmed）
%   (T,T) mean>30%  → α 和 h 都给 oracle 仍灾难 → Turbo 本身问题，进 D3
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D2_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_alpha  = +1e-2;
h_snr    = 10;
h_seeds  = 1:5;
h_n_seed = length(h_seeds);

% 4 组：(oracle_α, oracle_h)
h_groups = {
    'FF_baseline',  false, false;
    'TF_oracle_a',  true,  false;
    'FT_oracle_h',  false, true;
    'TT_oracle_ah', true,  true;
};
h_n_grp = size(h_groups, 1);

h_ber = nan(h_n_grp, h_n_seed);

fprintf('========================================\n');
fprintf('  D2 — Oracle h diag（SC-TDE α=+1e-2 RCA）\n');
fprintf('  α=%+.0e, SNR=%d dB, seeds=%d..%d, 4×5=%d trial\n', ...
    h_alpha, h_snr, h_seeds(1), h_seeds(end), h_n_grp*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_gi = 1:h_n_grp
    h_group_name = h_groups{h_gi, 1};
    h_oracle_a   = h_groups{h_gi, 2};
    h_oracle_h   = h_groups{h_gi, 3};
    fprintf('--- %s (oracle_α=%d, oracle_h=%d) ---\n  ', h_group_name, h_oracle_a, h_oracle_h);

    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv = fullfile(h_out_dir, sprintf('D2_%s_seed%d.csv', h_group_name, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'D2';
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
        % 仅第一个 seed 的第一组 dump h（避免日志爆炸）
        diag_dump_h       = (h_di == 1 && h_gi == 1);

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('s%d[ERR:%s] ', h_seed, ME.message(1:min(end,30)));
            continue;
        end

        if exist(h_csv, 'file')
            try
                T = readtable(h_csv);
                if height(T) >= 1, h_ber(h_gi, h_di) = T.ber_coded(1); end
            catch, end
        end

        b = h_ber(h_gi, h_di) * 100;
        if b < 1, mk='.'; elseif b < 30, mk='o'; else, mk='X'; end
        fprintf('s%d=%.1f%%[%s] ', h_seed, b, mk);
    end
    fprintf('\n\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Summary
fprintf('=========== D2 结果（α=+1e-2, SNR=%d dB）===========\n', h_snr);
fprintf('  group         | mean  | median | std   | min  | max   | 灾难率\n');
fprintf('----------------+-------+--------+-------+------+-------+--------\n');
for h_gi = 1:h_n_grp
    r = h_ber(h_gi, :) * 100;
    h_dis = sum(r > 30, 'omitnan');
    fprintf('  %-13s | %5.2f | %5.2f  | %5.2f | %4.1f | %5.2f | %d/%d\n', ...
        h_groups{h_gi,1}, ...
        mean(r,'omitnan'), median(r,'omitnan'), std(r,'omitnan'), ...
        min(r,[],'omitnan'), max(r,[],'omitnan'), ...
        h_dis, h_n_seed);
end

fprintf('\n=========== 判据 ===========\n');
m_ff = mean(h_ber(1,:)*100,'omitnan');
m_tf = mean(h_ber(2,:)*100,'omitnan');
m_ft = mean(h_ber(3,:)*100,'omitnan');
m_tt = mean(h_ber(4,:)*100,'omitnan');

fprintf('  FF (baseline)  : %.2f%%\n', m_ff);
fprintf('  TF (oracle α)  : %.2f%%\n', m_tf);
fprintf('  FT (oracle h)  : %.2f%%\n', m_ft);
fprintf('  TT (oracle α+h): %.2f%%\n', m_tt);
fprintf('\n');

if m_tt < 5
    if m_ft < 5
        fprintf('  ✓ FT=%.2f%% + TT=%.2f%% → GAMP 是主因（H1 confirmed）\n', m_ft, m_tt);
        fprintf('    → 下一步：SC-TDE GAMP guard / LS fallback（新 fix spec）\n');
    elseif m_tf < 5
        fprintf('  ✓ TF=%.2f%% → α 估计是主因（与 D1 一致）\n', m_tf);
    else
        fprintf('  ✓ 仅 TT 恢复 → α 和 h 共同作用（耦合误差）\n');
    end
else
    fprintf('  ✗ TT=%.2f%% > 30%% → α+h 都 oracle 仍灾难 → Turbo 本身问题\n', m_tt);
    fprintf('    → 进 D3 (turbo_iter sweep)\n');
end

fprintf('\n完成\n');
