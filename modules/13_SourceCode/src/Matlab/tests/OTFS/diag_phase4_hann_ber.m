%% diag_phase4_hann_ber.m
% spec 2026-04-13-otfs-pulse-shaping.md Phase 4：Hann 脉冲 vs rect baseline
% 离散/混合 Doppler 信道 BER 验证（acceptance criterion: 0%@10dB+）
%
% 设计：rect / hann × {static, disc-5Hz, hyb-K5} × SNR={10,15}, seed=42
% 输出：BER 矩阵对比 + 是否满足 acceptance criterion
%
% 用法（cd 到 tests/OTFS/）：
%   diary('diag_phase4_results.txt'); diag_phase4_hann_ber; diary off

clear functions; close all;
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))));
addpath(genpath(fullfile(proj_root, '..')));  % addpath all of UWAcomm

fprintf('====================================================\n');
fprintf('  Phase 4 BER validation: rect vs hann (OTFS)\n');
fprintf('  spec: 2026-04-13-otfs-pulse-shaping.md\n');
fprintf('====================================================\n\n');

%% 测试矩阵
pulse_types  = {'rect', 'hann'};
fading_subset = {
    'static',   'static',   zeros(1,5);
    'disc-5Hz', 'discrete', [0, 3, -4, 5, -2];
    'hyb-K5',   'hybrid',   struct('doppler_hz',[0,3,-4,5,-2], 'fd_scatter',1.0, 'K_rice',5);
};
snr_list_local = [10, 15];
seed_local     = 42;

results = cell(length(pulse_types), 1);

for pi = 1:length(pulse_types)
    pulse_type = pulse_types{pi};
    fprintf('\n>>> Pulse: %s <<<\n', pulse_type);

    benchmark_mode         = true;
    bench_seed             = seed_local;
    bench_stage            = sprintf('Phase4_%s', pulse_type);
    bench_scheme_name      = 'OTFS';
    bench_channel_profile  = 'custom6';
    bench_snr_list         = snr_list_local;
    bench_fading_cfgs      = fading_subset;
    bench_otfs_pulse_type  = pulse_type;
    bench_csv_path         = fullfile(tempdir, sprintf('diag_phase4_%s.csv', pulse_type));

    test_otfs_timevarying;  %#ok<NOPRT>

    results{pi}.pulse  = pulse_type;
    results{pi}.ber    = ber_matrix;
    results{pi}.nmse   = nmse_matrix;
    results{pi}.fading = fading_subset(:,1);
    results{pi}.snr    = snr_list_local;

    clearvars -except results pulse_types fading_subset snr_list_local seed_local proj_root pi
end

%% 对比表
fprintf('\n====================================================\n');
fprintf('  BER 对比矩阵（%%）\n');
fprintf('====================================================\n');
fprintf('%-12s', 'Fading');
for si = 1:length(snr_list_local)
    fprintf('  rect@%-2ddB hann@%-2ddB  Δ', snr_list_local(si), snr_list_local(si));
end
fprintf('\n');
fprintf('%s\n', repmat('-', 1, 70));

n_pass = 0; n_fail = 0; n_total = 0;
for fi = 1:size(fading_subset,1)
    fprintf('%-12s', fading_subset{fi,1});
    for si = 1:length(snr_list_local)
        b_rect = results{1}.ber(fi, si) * 100;
        b_hann = results{2}.ber(fi, si) * 100;
        delta  = b_hann - b_rect;
        fprintf('  %7.3f   %7.3f   %+6.3f', b_rect, b_hann, delta);

        % Acceptance: hann BER ≤ rect BER + 1pp 容差（spec 说"不退化"）
        if snr_list_local(si) >= 10 && b_hann <= b_rect + 1.0
            n_pass = n_pass + 1;
        else
            n_fail = n_fail + 1;
        end
        n_total = n_total + 1;
    end
    fprintf('\n');
end
fprintf('%s\n', repmat('-', 1, 70));
fprintf('Acceptance（hann ≤ rect + 1pp 容差，SNR≥10dB）: %d/%d PASS\n', n_pass, n_total);

% 严格 0% 检查
fprintf('\n[严格] hann 是否 0%%@SNR≥10dB（spec acceptance）：\n');
for fi = 1:size(fading_subset,1)
    for si = 1:length(snr_list_local)
        b_hann = results{2}.ber(fi, si) * 100;
        ok_str = '✓'; if b_hann > 0.01, ok_str = '✗'; end
        fprintf('  %s %s @ %ddB: %.3f%%\n', ok_str, fading_subset{fi,1}, snr_list_local(si), b_hann);
    end
end

fprintf('\n=== diag_phase4_hann_ber done ===\n');
