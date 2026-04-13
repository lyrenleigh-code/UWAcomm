%% measure_papr_baseline.m — OTFS vs OFDM vs SC PAPR基线测量
% Phase 0: 量化当前PAPR问题严重程度
% 用法: cd到本目录后直接 run('measure_papr_baseline.m')

clc; close all;
fprintf('========================================\n');
fprintf('  PAPR Baseline 测量 (OTFS vs OFDM vs SC)\n');
fprintf('========================================\n\n');

proj_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(proj_root, '04_Modulation', 'src', 'Matlab'));
addpath(fullfile(proj_root, '09_Waveform', 'src', 'Matlab'));

%% 参数设置
N_mc = 200;          % Monte Carlo 次数
N = 8;               % OTFS: 多普勒格点数
M = 32;              % OTFS: 时延格点数 / OFDM: 子载波数
cp_len = 8;          % CP长度
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);  % QPSK

% 存储
papr_otfs = zeros(1, N_mc);
papr_ofdm = zeros(1, N_mc);
papr_sc   = zeros(1, N_mc);

%% Monte Carlo
for trial = 1:N_mc
    rng(trial);

    %% 1. OTFS: N×M DD域QPSK → otfs_modulate
    bits_otfs = randi([0 3], 1, N*M);
    dd_syms = constellation(bits_otfs + 1);
    dd_mat = reshape(dd_syms, N, M);
    [sig_otfs, ~] = otfs_modulate(dd_mat, N, M, cp_len, 'dft');
    papr_otfs(trial) = papr_calculate(sig_otfs);

    %% 2. OFDM: N_ofdm个符号 × M子载波 (总符号数 = N*M)
    bits_ofdm = randi([0 3], 1, N*M);
    freq_syms = constellation(bits_ofdm + 1);
    [sig_ofdm, ~] = ofdm_modulate(freq_syms, M, cp_len, 'cp');
    papr_ofdm(trial) = papr_calculate(sig_ofdm);

    %% 3. SC (RRC成形): 同样符号数, sps=4
    bits_sc = randi([0 3], 1, N*M);
    sc_syms = constellation(bits_sc + 1);
    sps = 4; rolloff_sc = 0.35; span_sc = 6;
    [sig_sc, ~, ~] = pulse_shape(sc_syms, sps, 'rrc', rolloff_sc, span_sc);
    papr_sc(trial) = papr_calculate(sig_sc);
end

%% 统计结果
fprintf('--- PAPR 统计 (%d次Monte Carlo, QPSK, N=%d, M=%d) ---\n\n', N_mc, N, M);
fprintf('  %-12s | %8s | %8s | %8s | %8s\n', '体制', '均值(dB)', '中位数', '最大(dB)', 'std(dB)');
fprintf('  %s\n', repmat('-', 1, 56));

schemes = {'OTFS', 'OFDM(CP)', 'SC(RRC)'};
paprs = {papr_otfs, papr_ofdm, papr_sc};
for i = 1:3
    p = paprs{i};
    fprintf('  %-12s | %8.2f | %8.2f | %8.2f | %8.2f\n', ...
        schemes{i}, mean(p), median(p), max(p), std(p));
end

%% 不同 N, M 参数下的OTFS PAPR
fprintf('\n--- OTFS PAPR vs 帧参数 ---\n\n');
fprintf('  %-6s %-6s %-8s | %8s | %8s | %8s\n', 'N', 'M', 'cp_len', '均值(dB)', '最大(dB)', 'std(dB)');
fprintf('  %s\n', repmat('-', 1, 52));

configs = [4 16 4; 4 32 8; 8 32 8; 8 64 16; 16 32 8; 16 64 16];
for ci = 1:size(configs, 1)
    Nc = configs(ci, 1);
    Mc = configs(ci, 2);
    cpc = configs(ci, 3);
    papr_cfg = zeros(1, N_mc);
    for trial = 1:N_mc
        rng(trial + 1000);
        bits = randi([0 3], 1, Nc*Mc);
        dd = reshape(constellation(bits+1), Nc, Mc);
        [sig, ~] = otfs_modulate(dd, Nc, Mc, cpc, 'dft');
        papr_cfg(trial) = papr_calculate(sig);
    end
    fprintf('  %-6d %-6d %-8d | %8.2f | %8.2f | %8.2f\n', ...
        Nc, Mc, cpc, mean(papr_cfg), max(papr_cfg), std(papr_cfg));
end

%% CCDF 可视化
try
    figure('Name', 'PAPR CCDF', 'NumberTitle', 'off', 'Position', [100 100 900 500]);

    % CCDF: P(PAPR > x)
    subplot(1,2,1);
    x_axis = 0:0.1:15;
    ccdf_otfs = zeros(size(x_axis));
    ccdf_ofdm = zeros(size(x_axis));
    ccdf_sc   = zeros(size(x_axis));
    for xi = 1:length(x_axis)
        ccdf_otfs(xi) = mean(papr_otfs > x_axis(xi));
        ccdf_ofdm(xi) = mean(papr_ofdm > x_axis(xi));
        ccdf_sc(xi)   = mean(papr_sc > x_axis(xi));
    end
    semilogy(x_axis, max(ccdf_otfs, 1/N_mc), 'b-', 'LineWidth', 1.5); hold on;
    semilogy(x_axis, max(ccdf_ofdm, 1/N_mc), 'r--', 'LineWidth', 1.5);
    semilogy(x_axis, max(ccdf_sc, 1/N_mc), 'g-.', 'LineWidth', 1.5);
    xlabel('PAPR_0 (dB)'); ylabel('P(PAPR > PAPR_0)');
    title('CCDF'); legend('OTFS', 'OFDM', 'SC(RRC)'); grid on;
    ylim([1/N_mc 1]);

    % 直方图
    subplot(1,2,2);
    histogram(papr_otfs, 20, 'FaceAlpha', 0.5, 'FaceColor', 'b'); hold on;
    histogram(papr_ofdm, 20, 'FaceAlpha', 0.5, 'FaceColor', 'r');
    histogram(papr_sc, 20, 'FaceAlpha', 0.5, 'FaceColor', 'g');
    xlabel('PAPR (dB)'); ylabel('Count');
    title('PAPR Distribution'); legend('OTFS', 'OFDM', 'SC(RRC)');

    fprintf('\n可视化完成 (CCDF + 直方图)\n');
catch
    fprintf('\n可视化跳过\n');
end

%% 保存结果
result_file = fullfile(fileparts(mfilename('fullpath')), 'measure_papr_baseline_results.txt');
fid = fopen(result_file, 'w');
fprintf(fid, 'PAPR Baseline (N_mc=%d, QPSK)\n', N_mc);
fprintf(fid, 'OTFS(N=%d,M=%d): mean=%.2f max=%.2f std=%.2f\n', N, M, mean(papr_otfs), max(papr_otfs), std(papr_otfs));
fprintf(fid, 'OFDM(M=%d):     mean=%.2f max=%.2f std=%.2f\n', M, mean(papr_ofdm), max(papr_ofdm), std(papr_ofdm));
fprintf(fid, 'SC(RRC):        mean=%.2f max=%.2f std=%.2f\n', mean(papr_sc), max(papr_sc), std(papr_sc));
fclose(fid);
fprintf('\n结果已保存: %s\n', result_file);
