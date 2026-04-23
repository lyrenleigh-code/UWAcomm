%% diag_seed1024_high_snr.m
% Phase I-3 (L3)：seed=1024 灾难 + 高 SNR 救活点边界
%
% Phase I-2 已确认 cascade 无辜（oracle/cascade 同样 50%）；本脚本扫高 SNR
% 找出 seed=1024 灾难场景能被救活的最低 SNR（如有）。
%
% 矩阵：α ∈ {-1e-2, +1e-2} × SNR ∈ {10, 15, 20, 25, 30, 40} dB × seed=1024
%       = 12 trial（cascade 模式）
%
% 已知（Phase I）：
%   α=-1e-2 SNR=10/15/20 → 50%（顽固）
%   α=+1e-2 SNR=10 → 51%；SNR=15/20 → 0%（高 SNR 救活）
%
% 本脚本目标：
%   - α=-1e-2 是否需要 SNR=25/30/40 才救活？
%   - α=+1e-2 SNR=10 dB 边界是否提到 11/12 就够
%
% 版本：V1.0.0（2026-04-23）

clear functions; clear; close all; clc;

h_this_dir = fileparts(mfilename('fullpath'));
h_runner   = fullfile(h_this_dir, 'test_scfde_timevarying.m');
h_out_dir  = fullfile(h_this_dir, 'diag_high_snr_out');
if ~exist(h_out_dir, 'dir'), mkdir(h_out_dir); end

h_alpha_list = [-1e-2, +1e-2];
h_snr_list   = [10, 15, 20, 25, 30, 40];
h_seed       = 1024;
h_n_alpha    = length(h_alpha_list);
h_n_snr      = length(h_snr_list);

h_ber = nan(h_n_alpha, h_n_snr);

fprintf('========================================\n');
fprintf('  seed=1024 灾难 × 高 SNR 边界扫描\n');
fprintf('========================================\n\n');

for h_ai = 1:h_n_alpha
    h_alpha_val = h_alpha_list(h_ai);
    fprintf('--- α=%+.0e ---\n', h_alpha_val);
    for h_si = 1:h_n_snr
        h_snr = h_snr_list(h_si);
        h_csv_path = fullfile(h_out_dir, sprintf('s1024_a%+g_snr%d.csv', h_alpha_val, h_snr));
        if exist(h_csv_path, 'file'), delete(h_csv_path); end

        fprintf('  SNR=%2d ', h_snr);

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

        try
            evalc('run(h_runner)');
        catch ME
            fprintf('ERR: %s\n', ME.message);
            continue;
        end

        if exist(h_csv_path, 'file')
            try
                h_T = readtable(h_csv_path);
                if height(h_T) >= 1
                    h_ber(h_ai, h_si) = h_T.ber_coded(1);
                end
            catch
            end
        end
        fprintf('BER=%6.2f%%\n', h_ber(h_ai, h_si) * 100);
    end
    fprintf('\n');
end

%% Summary
fprintf('=========== seed=1024 高 SNR BER 矩阵 ===========\n');
fprintf('  α          ');
for h_si = 1:h_n_snr
    fprintf('| SNR=%2d ', h_snr_list(h_si));
end
fprintf('\n-------------+--------+--------+--------+--------+--------+--------\n');
for h_ai = 1:h_n_alpha
    fprintf('  %+8.0e   ', h_alpha_list(h_ai));
    for h_si = 1:h_n_snr
        fprintf('| %6.2f ', h_ber(h_ai, h_si) * 100);
    end
    fprintf('\n');
end

%% 救活点定位
fprintf('\n=========== 救活点（首个 BER<1%% 的 SNR）===========\n');
for h_ai = 1:h_n_alpha
    h_ok = h_ber(h_ai, :) * 100 < 1;
    if any(h_ok)
        h_idx = find(h_ok, 1, 'first');
        fprintf('  α=%+.0e: SNR=%d dB （%5.2f%%）\n', ...
            h_alpha_list(h_ai), h_snr_list(h_idx), h_ber(h_ai, h_idx) * 100);
    else
        fprintf('  α=%+.0e: ❌ 全部 SNR 仍灾难（高于 SNR=%d 也救不了）\n', ...
            h_alpha_list(h_ai), h_snr_list(end));
    end
end

fprintf('\n完成\n');
