%% diag_D10_dsss_disable_cfo.m — DSSS 禁用 post-CFO 补偿根因验证
%
% 背景：
%   2026-04-23 Phase c 首次定量 DSSS α=+1e-2 SNR=10 下 15/15 seed 全灾难
%   （median BER 46.2%）。SC-TDE 同模式被 RCA 锁定为 post-CFO 伪补偿根因
%   （spec archive/2026-04-23-sctde-alpha-1e2-disaster-root-cause）。
%
%   Audit spec `2026-04-24-cfo-postcomp-cross-scheme-audit` 命中 DSSS runner
%   同 bug（`test_dsss_timevarying.m:344-348`），需要 D10 式验证确认是否
%   为 DSSS 100% 灾难的主根因还是与 Sun-2020 独立根因叠加。
%
% 方法：
%   2 模式（legacy_cfo ON/OFF）× 3 α × 5 seed = 30 trial
%   α ∈ {0, +1e-3, +1e-2}, SNR=10 dB
%
% 判据：
%   α=+1e-2 legacy=OFF mean BER < 5%   → DSSS 主根因 = post-CFO 伪补偿
%   α=+1e-2 legacy=OFF mean BER 10-30% → 部分改善，与 Sun-2020 根因叠加
%   α=+1e-2 legacy=OFF mean BER > 30%  → post-CFO 非 DSSS 主根因，Sun-2020 独立问题
%   α=0 / α=+1e-3 legacy=ON/OFF 接近   → 确认 disable 不破坏其他场景
%
% Spec : specs/active/2026-04-24-cfo-postcomp-cross-scheme-audit.md
% 版本 : V1.0.0 (2026-04-24)

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_out_dir  = fullfile(h_this_dir, 'diag_D10_dsss_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end
h_runner = fullfile(h_this_dir, 'test_dsss_timevarying.m');

h_alphas = [0, +1e-3, +1e-2];
h_snr    = 10;
h_seeds  = 1:5;
h_n_seed = length(h_seeds);
h_n_a    = length(h_alphas);

% 2 模式：legacy_cfo ON（历史行为 = apply post-CFO）vs OFF（V1.2 新默认 = skip）
h_modes = {'legacy_on', true; 'legacy_off', false};
h_n_m = size(h_modes, 1);

h_ber   = nan(h_n_m, h_n_a, h_n_seed);
h_ber_u = nan(h_n_m, h_n_a, h_n_seed);
h_aest  = nan(h_n_m, h_n_a, h_n_seed);

fprintf('========================================\n');
fprintf('  D10-DSSS — 禁用 post-CFO 补偿（audit 命中验证）\n');
fprintf('  α ∈ %s, SNR=%d dB, seeds=%d..%d, 2×%d×%d=%d trial\n', ...
    mat2str(h_alphas), h_snr, h_seeds(1), h_seeds(end), h_n_a, h_n_seed, ...
    h_n_m*h_n_a*h_n_seed);
fprintf('========================================\n\n');

h_t0 = tic;
for h_mi = 1:h_n_m
    h_mode_name = h_modes{h_mi, 1};
    h_enable    = h_modes{h_mi, 2};
    fprintf('=== %s (enable_legacy_cfo=%d) ===\n', h_mode_name, h_enable);

    for h_ai = 1:h_n_a
        h_alpha = h_alphas(h_ai);
        fprintf('  α=%+.0e: ', h_alpha);

        for h_di = 1:h_n_seed
            h_seed = h_seeds(h_di);
            h_csv = fullfile(h_out_dir, sprintf('D10dsss_%s_a%+.0e_seed%d.csv', ...
                h_mode_name, h_alpha, h_seed));
            if exist(h_csv, 'file'), delete(h_csv); end

            benchmark_mode                 = true;           %#ok<*NASGU>
            bench_snr_list                 = h_snr;
            bench_fading_cfgs              = { sprintf('a=%g', h_alpha), 'static', 0, h_alpha };
            bench_channel_profile          = 'custom6';
            bench_seed                     = h_seed;
            bench_stage                    = 'D10dsss';
            bench_scheme_name              = 'DSSS';
            bench_csv_path                 = h_csv;
            bench_diag                     = struct('enable', false);
            bench_toggles                  = struct();
            bench_oracle_alpha             = false;
            bench_oracle_passband_resample = false;
            bench_use_real_doppler         = true;

            diag_enable_legacy_cfo = h_enable;

            try
                evalc('run(h_runner)');
            catch ME
                fprintf('s%d[ERR:%s] ', h_seed, ME.identifier);
                continue;
            end

            if exist(h_csv, 'file')
                try
                    T = readtable(h_csv);
                    if height(T) >= 1
                        h_ber(h_mi, h_ai, h_di)   = T.ber_coded(1);
                        if ismember('ber_uncoded', T.Properties.VariableNames)
                            h_ber_u(h_mi, h_ai, h_di) = T.ber_uncoded(1);
                        end
                        if ismember('alpha_est', T.Properties.VariableNames)
                            h_aest(h_mi, h_ai, h_di)  = T.alpha_est(1);
                        end
                    end
                catch
                end
            end

            b = h_ber(h_mi, h_ai, h_di) * 100;
            if b < 1,      mk='.';
            elseif b < 5,  mk='o';
            elseif b < 30, mk='O';
            else,          mk='X';
            end
            fprintf('s%d=%.1f%%[%s] ', h_seed, b, mk);
        end
        fprintf('\n');
    end
    fprintf('\n');
end
h_elapsed = toc(h_t0);
fprintf('总用时：%.1f min\n\n', h_elapsed/60);

%% Summary
fprintf('=========== D10-DSSS 汇总（SNR=%d dB）===========\n', h_snr);
fprintf('  mode       | α=0            | α=+1e-3         | α=+1e-2\n');
fprintf('-------------+----------------+-----------------+----------------\n');
for h_mi = 1:h_n_m
    fprintf('  %-10s |', h_modes{h_mi,1});
    for h_ai = 1:h_n_a
        r = squeeze(h_ber(h_mi, h_ai, :)) * 100;
        fprintf(' %5.2f±%5.2f%%   |', mean(r,'omitnan'), std(r,'omitnan'));
    end
    fprintf('\n');
end

fprintf('\n  α_est mean (legacy_off 模式):\n');
for h_ai = 1:h_n_a
    r = squeeze(h_aest(2, h_ai, :));
    fprintf('    α=%+.0e → est=%+.3e\n', h_alphas(h_ai), mean(r,'omitnan'));
end

fprintf('\n=========== 判据评估 ===========\n');
m_on_1e2  = mean(squeeze(h_ber(1, 3, :))*100, 'omitnan');  % legacy ON @ α=+1e-2
m_off_1e2 = mean(squeeze(h_ber(2, 3, :))*100, 'omitnan');  % legacy OFF @ α=+1e-2
m_on_0    = mean(squeeze(h_ber(1, 1, :))*100, 'omitnan');  % legacy ON @ α=0
m_off_0   = mean(squeeze(h_ber(2, 1, :))*100, 'omitnan');  % legacy OFF @ α=0

fprintf('  α=+1e-2 legacy_on  mean BER = %.2f%%（apply post-CFO，历史行为）\n', m_on_1e2);
fprintf('  α=+1e-2 legacy_off mean BER = %.2f%%（skip post-CFO，V1.2 新默认）\n', m_off_1e2);
fprintf('  改善幅度：%.1f%%\n', m_on_1e2 - m_off_1e2);

fprintf('\n  α=0     legacy_on  mean BER = %.3f%%\n', m_on_0);
fprintf('  α=0     legacy_off mean BER = %.3f%%\n', m_off_0);

fprintf('\n  判据结论：\n');
if m_off_1e2 < 5
    fprintf('    ✓ DSSS α=+1e-2 主根因 = post-CFO 伪补偿（disable mean BER < 5%%）\n');
elseif m_off_1e2 < 30
    fprintf('    ⚠ DSSS α=+1e-2 部分改善，可能与 Sun-2020 根因叠加（disable mean BER 5-30%%）\n');
else
    fprintf('    ✗ post-CFO 非 DSSS 主根因（disable mean BER > 30%%），Sun-2020 spec 独立处理\n');
end

%% 保存 mat
h_mat = fullfile(h_out_dir, 'diag_D10_dsss_results.mat');
save(h_mat, 'h_alphas', 'h_snr', 'h_seeds', 'h_modes', ...
    'h_ber', 'h_ber_u', 'h_aest', 'h_elapsed');
fprintf('\n已保存到 %s\n', h_mat);
