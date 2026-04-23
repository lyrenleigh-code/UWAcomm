%% diag_D5_signal_layer.m — SC-TDE α=+1e-2 Turbo 输入信号层诊断
%
% 触发原因：D1+D2+D3 全部证伪 5 个原假设。D2 TT 组（α+h 双 oracle）BER 仍 50.5%，
% D3 iter=1 单独 50% → rx_sym_recv 送入 Turbo 之前信号层已失去信息。
%
% 目的：量化 4 组 oracle 配置下信号层质量（同步/提取/sps/对齐/SNR_emp）
%
% 输出：每组第 1 seed 打印信号层 diag（lfm_pos / alpha_err / corr / SNR_emp），
%       全组 5 seed 收集 BER。
%
% 判据：
%   |corr(1:50)|<0.3     → 数据段提取错位（sync/α 补偿层）
%   corr(1:50)>0.8 但 corr(tail)<0.3 → 中途失锁（累积相位漂移）
%   corr 全程>0.8, SNR_emp≪noise_var_db → 信道残差问题
%   corr 全程>0.8, SNR_emp 合理 → 输入 OK，Turbo 死循环
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D5_out');
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
fprintf('  D5 — 信号层对齐诊断（SC-TDE α=+1e-2 RCA）\n');
fprintf('  α=%+.0e, SNR=%d dB, seeds=%d..%d, 4×5=%d trial\n', ...
    h_alpha, h_snr, h_seeds(1), h_seeds(end), h_n_grp*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_gi = 1:h_n_grp
    h_group_name = h_groups{h_gi, 1};
    h_oracle_a   = h_groups{h_gi, 2};
    h_oracle_h   = h_groups{h_gi, 3};
    fprintf('==========================================\n');
    fprintf('--- %s (oracle_α=%d, oracle_h=%d) ---\n', h_group_name, h_oracle_a, h_oracle_h);
    fprintf('==========================================\n');

    for h_di = 1:h_n_seed
        h_seed = h_seeds(h_di);
        h_csv = fullfile(h_out_dir, sprintf('D5_%s_seed%d.csv', h_group_name, h_seed));
        if exist(h_csv, 'file'), delete(h_csv); end

        benchmark_mode                 = true; %#ok<*NASGU>
        bench_snr_list                 = [h_snr];
        bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
        bench_channel_profile          = 'custom6';
        bench_seed                     = h_seed;
        bench_stage                    = 'D5';
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
        % 仅每组首 seed 打印信号层 diag（避免日志爆炸）
        diag_dump_signal  = (h_di == 1);

        if diag_dump_signal
            % 直接 run（不 evalc），让 diag 输出到 diary
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
            fprintf('  seed=%d: BER=%.1f%%[%s]\n', h_seed, b, mk);
        else
            b = h_ber(h_gi, h_di) * 100;
            fprintf('  → BER=%.1f%%\n', b);
        end
    end
    fprintf('\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Summary
fprintf('=========== D5 BER 汇总（α=+1e-2, SNR=%d dB）===========\n', h_snr);
fprintf('  group         | mean  | median | std   | 灾难率\n');
fprintf('----------------+-------+--------+-------+--------\n');
for h_gi = 1:h_n_grp
    r = h_ber(h_gi, :) * 100;
    h_dis = sum(r > 30, 'omitnan');
    fprintf('  %-13s | %5.2f | %5.2f  | %5.2f | %d/%d\n', ...
        h_groups{h_gi,1}, ...
        mean(r,'omitnan'), median(r,'omitnan'), std(r,'omitnan'), ...
        h_dis, h_n_seed);
end

fprintf('\n=========== 分析提示 ===========\n');
fprintf('  查看上方 [DIAG-S] 输出，按以下优先级分析：\n');
fprintf('  1. lfm_pos 偏差 > 10 sample          → 同步层错\n');
fprintf('  2. |corr(1:50)| < 0.3                 → 数据段提取完全错位\n');
fprintf('  3. corr(1:50)>0.8, corr(451:500)<0.3  → 中途失锁（累积相位）\n');
fprintf('  4. corr 全程>0.8, SNR_emp 远低期望    → 信道残差\n');
fprintf('  5. corr 全程>0.8, SNR_emp 合理        → 输入 OK，Turbo 死循环\n');

fprintf('\n完成\n');
