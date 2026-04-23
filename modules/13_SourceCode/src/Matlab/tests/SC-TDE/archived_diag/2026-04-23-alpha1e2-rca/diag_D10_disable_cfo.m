%% diag_D10_disable_cfo.m — 禁用错误的 post-CFO 补偿，验证根因
%
% D9 决定性发现：
%   - sps scan 在 CFO 补偿前：α=+1e-2 下 |corr(1:50)|=0.817 (好对齐)
%   - DIAG-S 在 CFO 补偿后：  α=+1e-2 下 |corr(1:50)|=0.055 (被破坏)
%   - 结论：runner line 436-441 的 exp(-j·2π·α·fc·t) 补偿在基带 Doppler 模型下
%     是伪操作，α=+1e-2 时凭空添加 120 Hz 频偏破坏对齐。
%
% 验证：toggle `diag_disable_cfo_postcomp=true` 跳过该补偿，看 BER。
%
% 矩阵：3 α × 5 seed × {disable_cfo=false, true} = 30 trial
%   α ∈ {0, +1e-3, +1e-2}  (覆盖历史 work 到灾难区间)
%
% 判据：
%   α=+1e-2 disable=T BER <5%    → 根因确认，fix 方向：删 line 436-441
%   α=+1e-2 disable=T BER >30%   → 假设证伪，进 D11
%   α=0/1e-3 disable 前后 BER 基本一致 → 确认 disable 不破坏其他场景
%
% Spec: specs/active/2026-04-23-sctde-alpha-1e2-disaster-root-cause.md
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D10_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_sctde_timevarying.m');

h_alphas = [0, +1e-3, +1e-2];
h_snr    = 10;
h_seeds  = 1:5;
h_n_seed = length(h_seeds);
h_n_a    = length(h_alphas);

% 2 组：disable_cfo
h_modes = {'baseline', false; 'disable_cfo', true};
h_n_m = size(h_modes, 1);

h_ber = nan(h_n_m, h_n_a, h_n_seed);

fprintf('========================================\n');
fprintf('  D10 — 禁用 post-CFO 补偿（根因验证）\n');
fprintf('  α ∈ %s, SNR=%d, seeds=%d..%d, 2×3×5=%d trial\n', ...
    mat2str(h_alphas), h_snr, h_seeds(1), h_seeds(end), h_n_m*h_n_a*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_mi = 1:h_n_m
    h_mode_name = h_modes{h_mi, 1};
    h_disable   = h_modes{h_mi, 2};
    fprintf('=== %s (disable_cfo=%d) ===\n', h_mode_name, h_disable);

    for h_ai = 1:h_n_a
        h_alpha = h_alphas(h_ai);
        fprintf('  α=%+.0e: ', h_alpha);

        for h_di = 1:h_n_seed
            h_seed = h_seeds(h_di);
            h_csv = fullfile(h_out_dir, sprintf('D10_%s_a%+.0e_seed%d.csv', h_mode_name, h_alpha, h_seed));
            if exist(h_csv, 'file'), delete(h_csv); end

            benchmark_mode                 = true; %#ok<*NASGU>
            bench_snr_list                 = [h_snr];
            bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
            bench_channel_profile          = 'custom6';
            bench_seed                     = h_seed;
            bench_stage                    = 'D10';
            bench_scheme_name              = 'SC-TDE';
            bench_csv_path                 = h_csv;
            bench_diag                     = struct('enable', false);
            bench_toggles                  = struct();
            bench_oracle_alpha             = false;
            bench_oracle_passband_resample = false;
            bench_use_real_doppler         = true;

            diag_oracle_alpha         = false;
            diag_oracle_h             = false;
            diag_use_ls               = false;
            diag_turbo_iter           = [];
            diag_dump_h               = false;
            diag_precomp_cfo          = false;
            diag_precomp_cfo_data     = false;
            diag_dump_signal          = false;
            diag_dump_rxfilt          = false;
            diag_disable_cfo_postcomp = h_disable;

            try
                evalc('run(h_runner)');
            catch ME
                fprintf('s%d[ERR] ', h_seed);
                continue;
            end

            if exist(h_csv, 'file')
                try
                    T = readtable(h_csv);
                    if height(T) >= 1, h_ber(h_mi, h_ai, h_di) = T.ber_coded(1); end
                catch, end
            end

            b = h_ber(h_mi, h_ai, h_di) * 100;
            if b < 1, mk='.'; elseif b < 30, mk='o'; else, mk='X'; end
            fprintf('s%d=%.1f%%[%s] ', h_seed, b, mk);
        end
        fprintf('\n');
    end
    fprintf('\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Summary
fprintf('=========== D10 汇总（SNR=%d dB）===========\n', h_snr);
fprintf('  mode        | α=0       | α=+1e-3   | α=+1e-2\n');
fprintf('--------------+-----------+-----------+----------\n');
for h_mi = 1:h_n_m
    fprintf('  %-11s |', h_modes{h_mi,1});
    for h_ai = 1:h_n_a
        r = squeeze(h_ber(h_mi, h_ai, :)) * 100;
        fprintf(' %5.2f±%.2f |', mean(r,'omitnan'), std(r,'omitnan'));
    end
    fprintf('\n');
end

fprintf('\n=========== 判据 ===========\n');
m_base_1e2   = mean(squeeze(h_ber(1, 3, :))*100, 'omitnan');
m_disable_1e2= mean(squeeze(h_ber(2, 3, :))*100, 'omitnan');
m_base_0     = mean(squeeze(h_ber(1, 1, :))*100, 'omitnan');
m_disable_0  = mean(squeeze(h_ber(2, 1, :))*100, 'omitnan');
m_base_1e3   = mean(squeeze(h_ber(1, 2, :))*100, 'omitnan');
m_disable_1e3= mean(squeeze(h_ber(2, 2, :))*100, 'omitnan');

fprintf('  α=0   baseline=%.2f%%  vs  disable=%.2f%%\n', m_base_0, m_disable_0);
fprintf('  α=1e-3 baseline=%.2f%%  vs  disable=%.2f%%\n', m_base_1e3, m_disable_1e3);
fprintf('  α=1e-2 baseline=%.2f%%  vs  disable=%.2f%%\n', m_base_1e2, m_disable_1e2);
fprintf('\n');

if m_disable_1e2 < 5
    fprintf('  ✓✓✓ α=+1e-2 disable=T mean=%.2f%% <5%% → 根因确认！\n', m_disable_1e2);
    fprintf('      → 真根因：runner line 436-441 的 exp(-j·2π·α·fc·t) 补偿是伪操作\n');
    fprintf('      → 物理解释：gen_uwa_channel 基带 Doppler 模型不产生 fc·α 频偏\n');
    fprintf('      → Fix 方向：删除该段 CFO 补偿（或根据信道模型选择性启用）\n');
    fprintf('      → 横向检查：其他 5 体制 runner 是否有同操作\n');
elseif m_disable_1e2 < 30
    fprintf('  ⚠ α=+1e-2 disable=T mean=%.2f%% 部分恢复 → 主因正确，剩余次因\n', m_disable_1e2);
else
    fprintf('  ✗ α=+1e-2 disable=T mean=%.2f%% 仍灾难 → 假设证伪，重审\n', m_disable_1e2);
end

% 副作用检查：disable 不能破坏 α=0 和 α=1e-3 的性能
if m_disable_0 > 2 * m_base_0 + 0.5
    fprintf('  ⚠ α=0 disable=T 比 baseline 差 %.2f%% → disable 有副作用\n', m_disable_0 - m_base_0);
end
if m_disable_1e3 > 2 * m_base_1e3 + 0.5
    fprintf('  ⚠ α=1e-3 disable=T 比 baseline 差 %.2f%% → disable 有副作用\n', m_disable_1e3 - m_base_1e3);
end

fprintf('\n完成\n');
