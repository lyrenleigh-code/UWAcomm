%% diag_seed1024_oracle_isolation.m
% Phase I-2：oracle α 隔离诊断 — 定位 seed=1024 灾难根因
%
% 3 灾难场景 × 2 模式 = 6 trial：
%   模式 A: cascade 盲估（baseline）— 之前已知 BER ~50%
%   模式 B: oracle_alpha = true（基带用 dop_rate 真值）— 跳过 cascade
%
% 对比：
%   - 若 oracle_alpha 也 50% → cascade 完全无关，bug 在 decode/eq 链路
%   - 若 oracle_alpha → 0% → cascade 估值"看似准但实际有隐藏偏置"
%   - 若部分救活 → 混合根因
%
% 测试矩阵（seed=1024 全部）：
%   1A. α=-1e-2, SNR=10, cascade        → 预期 50.66%
%   1B. α=-1e-2, SNR=10, oracle_alpha   → ?
%   2A. α=+1e-2, SNR=10, cascade        → 预期 51.42%
%   2B. α=+1e-2, SNR=10, oracle_alpha   → ?
%   3A. α=-1e-2, SNR=15, cascade        → 预期 50.46%
%   3B. α=-1e-2, SNR=15, oracle_alpha   → ?
%
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_oracle_isolation_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

% [α, SNR, oracle_alpha_flag, 标签]
h_scenarios = {
    -1e-2, 10, false, '1A 受灾 cascade (α=-1e-2 SNR=10 预期 ~50%)';
    -1e-2, 10, true,  '1B 同条件 oracle_α (α=-1e-2 SNR=10)';
    +1e-2, 10, false, '2A 受灾 cascade (α=+1e-2 SNR=10 预期 ~51%)';
    +1e-2, 10, true,  '2B 同条件 oracle_α (α=+1e-2 SNR=10)';
    -1e-2, 15, false, '3A 顽固灾难 cascade (α=-1e-2 SNR=15 预期 ~50%)';
    -1e-2, 15, true,  '3B 同条件 oracle_α (α=-1e-2 SNR=15)';
};

h_n   = size(h_scenarios, 1);
h_ber = nan(h_n, 1);

for h_si = 1:h_n
    h_alpha_val = h_scenarios{h_si, 1};
    h_snr       = h_scenarios{h_si, 2};
    h_oracle    = h_scenarios{h_si, 3};
    h_label     = h_scenarios{h_si, 4};

    h_csv_path = fullfile(h_out_dir, sprintf('s1024_a%+g_snr%d_oracle%d.csv', ...
        h_alpha_val, h_snr, h_oracle));
    if exist(h_csv_path, 'file'), delete(h_csv_path); end

    fprintf('\n');
    fprintf('============================================================\n');
    fprintf('  场景 %d/%d: %s\n', h_si, h_n, h_label);
    fprintf('============================================================\n');

    benchmark_mode                 = true; %#ok<*NASGU>
    bench_snr_list                 = [h_snr];
    bench_fading_cfgs              = { sprintf('a=%g', h_alpha_val), 'static', 0, h_alpha_val, 1024, 128, 4 };
    bench_channel_profile          = 'custom6';
    bench_seed                     = 1024;
    bench_stage                    = 'diag';
    bench_scheme_name              = 'SC-FDE';
    bench_csv_path                 = h_csv_path;
    bench_diag                     = struct('enable', false);
    bench_toggles                  = struct();
    bench_oracle_alpha             = h_oracle;
    bench_oracle_passband_resample = false;
    bench_use_real_doppler         = true;

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
            end
        catch
        end
    end
end

%% Summary
fprintf('\n');
fprintf('============================================================\n');
fprintf('  Phase I-2 Summary（seed=1024 oracle 隔离）\n');
fprintf('============================================================\n');
fprintf('  #    α       SNR  模式             BER         label\n');
fprintf('  --- ------- ---  ---------------  ----------  -----------------\n');
for h_si = 1:h_n
    h_mode = '盲估 cascade';
    if h_scenarios{h_si, 3}, h_mode = 'oracle α 真值 '; end
    fprintf('  %d   %+.0e  %2d  %s   %7.2f%%    %s\n', ...
        h_si, h_scenarios{h_si, 1}, h_scenarios{h_si, 2}, ...
        h_mode, h_ber(h_si)*100, h_scenarios{h_si, 4});
end

fprintf('\n=== 配对对比（cascade vs oracle）===\n');
for h_pi = 1:2:h_n-1
    h_a = h_ber(h_pi)   * 100;
    h_b = h_ber(h_pi+1) * 100;
    h_diff = h_a - h_b;
    fprintf('  α=%+.0e SNR=%2ddB: cascade %5.2f%% → oracle %5.2f%% (Δ=%+6.2f%%)\n', ...
        h_scenarios{h_pi, 1}, h_scenarios{h_pi, 2}, h_a, h_b, h_diff);
end

%% 判定
fprintf('\n=== 根因判定 ===\n');
h_oracle_bers = h_ber(2:2:end) * 100;
if all(h_oracle_bers > 30)
    fprintf('  → ❌ oracle α 全部 >30%% — cascade 完全无辜\n');
    fprintf('     根因在解码/均衡链路，与 bench_seed=1024 RX 噪声 pattern 触发\n');
    fprintf('     建议 Phase I-3：调高 SNR 隔离 / 检查 BCJR LLR / 检查 channel est\n');
elseif all(h_oracle_bers < 1)
    fprintf('  → ✓ oracle α 全部 <1%% — cascade 有隐藏偏置\n');
    fprintf('     虽然 err 看似 <1e-5，但与 RX 噪声组合触发"假准"现象\n');
    fprintf('     建议 Phase I-3：用 bench_alpha_override 精扫 α±1e-5 看 BER 曲线\n');
else
    fprintf('  → 🟡 混合根因 — oracle α 部分救活\n');
    fprintf('     cascade + decode 双重影响；需细化 oracle_passband_resample 进一步隔离\n');
end

fprintf('\n完成\n');
