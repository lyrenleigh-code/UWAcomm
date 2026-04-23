%% diag_seed1024_disaster.m
% Phase I：诊断 seed=1024 灾难（17% trial ~50% BER 根因追查）
%
% 5 关键场景对比（不抑制 runner fprintf，从 diary 抓 cascade DEBUG + 同步行）：
%   1. α=-1e-2, SNR=10, seed=  42  → 13.14% baseline
%   2. α=-1e-2, SNR=10, seed=1024  → 50.66% 受灾
%   3. α=+1e-2, SNR=10, seed=1024  → 51.42% （同 seed 受灾，排 α 因素）
%   4. α=+1e-2, SNR=15, seed=1024  →  0.00% （同 seed 高 SNR 救活）
%   5. α=-1e-2, SNR=15, seed=1024  → 50.46% （高 SNR 救不了 α=-1e-2+seed=1024）
%
% 切 3 维：seed / α / SNR，定位灾难根因（同步失败 / 估计反向 / 解码反向）
%
% 关键诊断信号（runner 内部已 fprintf）：
%   - [DEBUG cascade] α1=... α_p2=... err=...      → cascade 估值是否正常
%   - [DEBUG bb_raw]  checksum=...                  → 信号链路指纹
%   - (blk=..., lfm=..., peak=...)                  → 同步状态（lfm_pos 应 ≈ 9817）
%   - --- 多普勒估计 ---  est=..., true=...         → 末尾估值表
%
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_seed1024_disaster_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

% 5 场景定义：[α, SNR, seed, 标签]
h_scenarios = {
    -1e-2, 10,   42, 'baseline (α=-1e-2 s=42 SNR=10 → 13.14%)';
    -1e-2, 10, 1024, '受灾 (α=-1e-2 s=1024 SNR=10 → 50.66%)';
    +1e-2, 10, 1024, '排 α (α=+1e-2 s=1024 SNR=10 → 51.42%)';
    +1e-2, 15, 1024, '高 SNR 救活 (α=+1e-2 s=1024 SNR=15 → 0.00%)';
    -1e-2, 15, 1024, '高 SNR 不救 (α=-1e-2 s=1024 SNR=15 → 50.46%)';
};

h_n = size(h_scenarios, 1);
h_ber       = nan(h_n, 1);
h_alpha_est = nan(h_n, 1);

for h_si = 1:h_n
    h_alpha_val = h_scenarios{h_si, 1};
    h_snr       = h_scenarios{h_si, 2};
    h_seed      = h_scenarios{h_si, 3};
    h_label     = h_scenarios{h_si, 4};

    h_csv_path = fullfile(h_out_dir, sprintf('s%d_a%+g_snr%d.csv', ...
        h_seed, h_alpha_val, h_snr));
    if exist(h_csv_path, 'file'), delete(h_csv_path); end

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('  场景 %d/%d: %s\n', h_si, h_n, h_label);
    fprintf('============================================================\n');

    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = [h_snr];
    bench_fading_cfgs              = { sprintf('a=%g', h_alpha_val), 'static', 0, h_alpha_val, 1024, 128, 4 };
    bench_channel_profile          = 'custom6';
    bench_seed                     = h_seed;
    bench_stage                    = 'diag';
    bench_scheme_name              = 'SC-FDE';
    bench_csv_path                 = h_csv_path;
    bench_diag                     = struct('enable', false);
    bench_toggles                  = struct();
    bench_oracle_alpha             = false;
    bench_oracle_passband_resample = false;
    bench_use_real_doppler         = true;

    % 不抑制 fprintf（要看 [DEBUG cascade] / [DEBUG bb_raw] / 同步行）
    try
        run(h_runner);
    catch ME
        fprintf('  [ERROR] %s\n', ME.message);
        continue;
    end

    if exist(h_csv_path, 'file')
        try
            h_T = readtable(h_csv_path);
            if height(h_T) >= 1
                h_ber(h_si) = h_T.ber_coded(1);
                if ismember('alpha_est', h_T.Properties.VariableNames)
                    h_alpha_est(h_si) = h_T.alpha_est(1);
                end
            end
        catch
        end
    end
end

%% Summary
fprintf('\n');
fprintf('============================================================\n');
fprintf('  Phase I Summary\n');
fprintf('============================================================\n');
fprintf('  #   α        SNR  seed   BER         α_est       label\n');
fprintf('  --- -------- ---- ----   ---------   ---------   ----------------\n');
for h_si = 1:h_n
    fprintf('  %d   %+.0e  %2d   %4d   %7.2f%%    %+.4e   %s\n', ...
        h_si, h_scenarios{h_si, 1}, h_scenarios{h_si, 2}, ...
        h_scenarios{h_si, 3}, h_ber(h_si)*100, h_alpha_est(h_si), h_scenarios{h_si, 4});
end

fprintf('\n=== 关键 diff（请人工读 diary 抓 [DEBUG cascade] + sync 行）===\n');
fprintf('  对比 1↔2 (seed 42 vs 1024)：固定 α/SNR 看 cascade 估值是否变\n');
fprintf('  对比 2↔3 (-1e-2 vs +1e-2)：固定 seed/SNR 看 α 是否影响\n');
fprintf('  对比 3↔4 (SNR 10 vs 15)  ：α=+1e-2 seed=1024 是否 SNR 救活\n');
fprintf('  对比 2↔5 (SNR 10 vs 15)  ：α=-1e-2 seed=1024 高 SNR 救不了\n');

fprintf('\n完成\n');
