%% diag_D9_rxfilt_compare.m — rx_filt 波形对比 α=0 vs α=+1e-2
%
% 目的：在 comp_resample 和 CFO 补偿都被证实正确、pre-CFO 位置也排除后，
%   直接 dump rx_filt 前 48 个样本的幅度/相位 + rx_sym_recv 前 10 符号 +
%   扫描 8 个 sps 相位，对比两个 α 的差异。让数据说话。
%
% 矩阵：2 组（α=0 / α=+1e-2）× seed=1，每组 dump rx_filt
%
% 重点观察：
%   1. rx_filt(1:48) 的幅度包络：α=0 下应有 6 个符号的脉冲响应（sps=8）
%      是否 α=+1e-2 下该包络形状改变？
%   2. sps phase scan：8 个相位下哪个 corr 最高？baseline、跳 group_delay 后差异？
%   3. rx_sym_recv(1:10) vs training(1:10)：是否存在固定相位偏移？
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D9_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_snr   = 10;
h_seed  = 1;

h_groups = {
    'alpha_0',    0;
    'alpha_p1e2', +1e-2;
};

for h_gi = 1:size(h_groups,1)
    h_group_name = h_groups{h_gi, 1};
    h_alpha      = h_groups{h_gi, 2};
    h_csv = fullfile(h_out_dir, sprintf('D9_%s.csv', h_group_name));
    if exist(h_csv, 'file'), delete(h_csv); end

    fprintf('\n');
    fprintf('==========================================\n');
    fprintf('=== %s (α=%+.0e) seed=%d ===\n', h_group_name, h_alpha, h_seed);
    fprintf('==========================================\n');

    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = [h_snr];
    bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
    bench_channel_profile          = 'custom6';
    bench_seed                     = h_seed;
    bench_stage                    = 'D9';
    bench_scheme_name              = 'SC-TDE';
    bench_csv_path                 = h_csv;
    bench_diag                     = struct('enable', false);
    bench_toggles                  = struct();
    bench_oracle_alpha             = false;
    bench_oracle_passband_resample = false;
    bench_use_real_doppler         = true;

    diag_oracle_alpha     = false;
    diag_oracle_h         = false;
    diag_use_ls           = false;
    diag_turbo_iter       = [];
    diag_dump_h           = false;
    diag_precomp_cfo      = false;
    diag_precomp_cfo_data = false;
    diag_dump_signal      = true;   % 也 dump signal layer
    diag_dump_rxfilt      = true;   % D9 新 toggle

    try
        run(h_runner);
    catch ME
        fprintf('ERR: %s\n', ME.message(1:min(end,80)));
        continue;
    end

    if exist(h_csv, 'file')
        try
            T = readtable(h_csv);
            if height(T) >= 1
                fprintf('\n  → BER = %.2f%%\n', T.ber_coded(1)*100);
            end
        catch, end
    end
end

fprintf('\n=========== D9 分析提示 ===========\n');
fprintf('  1. rx_filt(1:48) abs：α=0 下前 48 sample（6 sps 周期）应有清晰 RRC 脉冲响应\n');
fprintf('  2. sps phase scan：α=0 下应有 1 个 phase |corr|≈0.7，其他 <0.3\n');
fprintf('     α=+1e-2 下若 8 个 phase 都低 → 不是 sps 相位问题\n');
fprintf('  3. 跳 group_delay 对齐：若跳后 α=+1e-2 corr 大幅提升 → match_filter 没内部补偿 GD\n');
fprintf('  4. rx_sym_recv(1:10) 的相位分布：若全 0° 或常数偏移 → 对齐 OK；若乱 → 对齐差\n');

fprintf('\n完成\n');
