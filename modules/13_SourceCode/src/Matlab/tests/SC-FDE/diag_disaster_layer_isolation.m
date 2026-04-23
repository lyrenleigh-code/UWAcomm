%% diag_disaster_layer_isolation.m
% L2' Step 1: 5 候选根因层逐层定位（首先看 Channel est 极性，候选 A）
%
% 4 trial（来自 Phase J Monte Carlo 已知）：
%   α=-1e-2 seed=01: BER  0.00% (健康对照)
%   α=-1e-2 seed=15: BER 47.50% (灾难)
%   α=+1e-2 seed=01: BER  0.00% (健康对照)
%   α=+1e-2 seed=23: BER 49.18% (灾难)
%
% 关键观察项（runner 自带 fprintf）：
%   1. [DEBUG cascade] α 估值（应都正常 ~1e-6 误差）
%   2. (lfm=, peak=) 同步状态（候选 C: timing 偏 1 样本）
%   3. --- Oracle H_est --- 每径 |gain|<phase° vs 静态参考
%      → 候选 A: 灾难 case 主径 phase 应翻 ±180°
%   4. --- 多普勒估计 ---  最终 alpha_est
%
% 4 case fprintf 块前后插入 ====== 分隔行，便于人工 diff
%
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_layer_isolation_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

% [α, seed, 预期 BER, 标签]
h_scenarios = {
    -1e-2,  1,  0.00, 'A1 健康对照 (α=-1e-2 s=1)';
    -1e-2, 15, 47.50, 'A2 灾难     (α=-1e-2 s=15)';
    +1e-2,  1,  0.00, 'B1 健康对照 (α=+1e-2 s=1)';
    +1e-2, 23, 49.18, 'B2 灾难     (α=+1e-2 s=23)';
};

h_n = size(h_scenarios, 1);
h_ber = nan(h_n, 1);

for h_si = 1:h_n
    h_alpha_val = h_scenarios{h_si, 1};
    h_seed      = h_scenarios{h_si, 2};
    h_expected  = h_scenarios{h_si, 3};
    h_label     = h_scenarios{h_si, 4};

    h_csv_path = fullfile(h_out_dir, sprintf('s%02d_a%+g.csv', h_seed, h_alpha_val));
    if exist(h_csv_path, 'file'), delete(h_csv_path); end

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('  Trial %d/%d: %s   (预期 %5.2f%%)\n', h_si, h_n, h_label, h_expected);
    fprintf('============================================================\n');

    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = [10];
    bench_fading_cfgs              = { sprintf('a=%g', h_alpha_val), 'static', 0, h_alpha_val, 1024, 128, 4 };
    bench_channel_profile          = 'custom6';
    bench_seed                     = h_seed;
    bench_stage                    = 'diag';
    bench_scheme_name              = 'SC-FDE';
    bench_csv_path                 = h_csv_path;
    bench_diag                     = struct('enable', true, 'out_path', 'unused.mat');   % 让 runner fall through 到 H_est 诊断段
    bench_toggles                  = struct();
    bench_oracle_alpha             = false;
    bench_oracle_passband_resample = false;
    bench_use_real_doppler         = true;

    try
        run(h_runner);   % 不抑制 fprintf
    catch ME
        fprintf('  [ERROR] %s\n', ME.message);
        continue;
    end

    if exist(h_csv_path, 'file')
        try
            h_T = readtable(h_csv_path);
            if height(h_T) >= 1, h_ber(h_si) = h_T.ber_coded(1); end
        catch
        end
    end
    fprintf('\n  >>> 实测 BER=%.2f%%（预期 %.2f%%）\n', h_ber(h_si)*100, h_expected);
end

%% Summary
fprintf('\n');
fprintf('============================================================\n');
fprintf('  L2-Step1 Summary（4 case 对比）\n');
fprintf('============================================================\n');
fprintf('  #   α        seed   实测 BER    预期 BER    label\n');
fprintf('  --- -------- ---- ---------   ---------   ----------------\n');
for h_si = 1:h_n
    fprintf('  %d   %+.0e   %3d   %7.2f%%    %7.2f%%    %s\n', ...
        h_si, h_scenarios{h_si, 1}, h_scenarios{h_si, 2}, ...
        h_ber(h_si)*100, h_scenarios{h_si, 3}, h_scenarios{h_si, 4});
end

fprintf('\n=== 候选 A（Channel est 极性翻转）人工判定 ===\n');
fprintf('  对比 trial 1 vs 2 (α=-1e-2 健康 vs 灾难) Oracle H_est 行：\n');
fprintf('    若灾难 case 各径 phase 与健康 case 相差 ±180° → ✓ 候选 A 确认\n');
fprintf('    若 phase 几乎相同 → ❌ 排 A，进 Step 2 candidate B/C/D/E\n');
fprintf('  同样对比 trial 3 vs 4 (α=+1e-2)\n');
fprintf('\n=== 候选 C（Frame timing 偏移）人工判定 ===\n');
fprintf('  对比 (lfm=..., peak=...) 行：lfm 值跨 trial 是否一致（应都 ≈ 9817）\n');

fprintf('\n完成\n');
