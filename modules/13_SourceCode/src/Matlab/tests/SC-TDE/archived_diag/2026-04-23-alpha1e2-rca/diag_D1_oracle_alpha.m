%% diag_D1_oracle_alpha.m — SC-TDE α=+1e-2 灾难 RCA 第 1 步
%
% 目的：剥离 α 估计误差，看 GAMP+Turbo 在"完美 α 补偿"下是否仍灾难。
%
% 配置：α=+1e-2 / SNR=10 dB / custom6 信道 / static fading / seed 1..5
% 对比：{diag_oracle_alpha=false, true} × 5 seed = 10 trial
%
% 判据（运行后检查）：
%   若 oracle_α 组 mean BER < 5%  → α 估计是主因，H5 confirmed
%   若 oracle_α 组 mean BER > 30% → α 估计无关，进 D2
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_tests_dir = fileparts(h_this_dir);
h_out_dir  = fullfile(h_this_dir, 'diag_D1_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_alpha  = +1e-2;
h_snr    = 10;
h_seeds  = 1:5;
h_n_seed = length(h_seeds);

% 两组：baseline（oracle_alpha=false） vs oracle_α（true）
h_groups = {
    'baseline',  false;
    'oracle_a',  true;
};
h_n_grp = size(h_groups, 1);

h_ber = nan(h_n_grp, h_n_seed);

fprintf('========================================\n');
fprintf('  D1 — Oracle α diag（SC-TDE α=+1e-2 RCA）\n');
fprintf('  α=%+.0e, SNR=%d dB, seeds=%d..%d\n', h_alpha, h_snr, h_seeds(1), h_seeds(end));
fprintf('========================================\n\n');

h_t0 = tic;
for h_gi = 1:h_n_grp
    h_group_name = h_groups{h_gi, 1};
    h_oracle_a   = h_groups{h_gi, 2};
    fprintf('--- %s (oracle_alpha=%d) ---\n  ', h_group_name, h_oracle_a);

    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv = fullfile(h_out_dir, sprintf('D1_%s_seed%d.csv', h_group_name, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'D1';
        bench_scheme_name              = 'SC-TDE';
        bench_csv_path                 = h_csv;
        bench_diag                     = struct('enable', false);
        bench_toggles                  = struct();
        bench_oracle_alpha             = false;        % 不走 e2e benchmark 的 oracle α（runner 没实现）
        bench_oracle_passband_resample = false;
        bench_use_real_doppler         = true;

        % diag toggles（本 spec 新增）
        diag_oracle_alpha = h_oracle_a;
        diag_oracle_h     = false;
        diag_use_ls       = false;
        diag_turbo_iter   = [];
        diag_dump_h       = false;

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
fprintf('=========== D1 结果（α=+1e-2, SNR=%d dB）===========\n', h_snr);
fprintf('  group    | mean  | median | std   | min  | max   | 灾难率 (>30%%)\n');
fprintf('-----------+-------+--------+-------+------+-------+----------------\n');
for h_gi = 1:h_n_grp
    r = h_ber(h_gi, :) * 100;
    h_dis = sum(r > 30, 'omitnan');
    fprintf('  %-8s | %5.2f | %5.2f  | %5.2f | %4.1f | %5.2f | %d/%d (%4.1f%%)\n', ...
        h_groups{h_gi,1}, ...
        mean(r,'omitnan'), median(r,'omitnan'), std(r,'omitnan'), ...
        min(r,[],'omitnan'), max(r,[],'omitnan'), ...
        h_dis, h_n_seed, 100*h_dis/h_n_seed);
end

fprintf('\n=========== 判据 ===========\n');
r_oracle = h_ber(2, :) * 100;
m_oracle = mean(r_oracle, 'omitnan');
if m_oracle < 5
    fprintf('  ✓ oracle_α mean=%.2f%% < 5%% → α 估计是主因（H5 confirmed）\n', m_oracle);
    fprintf('    → 建议：est_alpha_dual_chirp 在 SC-TDE 场景偏差专项（新 spec）\n');
    fprintf('    → D2/D3/D4 可跳过（但建议跑 D2 交叉验证）\n');
elseif m_oracle > 30
    fprintf('  ✗ oracle_α mean=%.2f%% > 30%% → α 估计无关\n', m_oracle);
    fprintf('    → 进 D2 (oracle h)\n');
else
    fprintf('  ⚠ oracle_α mean=%.2f%% 介于 5-30%% → 部分恢复\n', m_oracle);
    fprintf('    → 进 D2 + D3 定位次因\n');
end

fprintf('\n完成\n');
