%% test_p3_3_dsss_otfs.m — P3.3 统一 modem API — DSSS + OTFS 回归测试
% 目的：验证 modem_encode/modem_decode 在 DSSS + OTFS 两体制下 BER 符合基线
% 场景：静态 5 径多径 + 基带复 AWGN（bypass passband，聚焦 modem 本身正确性）
% 基线参考：
%   - DSSS: 0%@5dB+（处理增益 ~15dB，Rake MRC, 5径，静态）
%   - OTFS: 0%@15dB+（LMMSE+Turbo×3, 5径，静态）

clc; close all;
fprintf('========================================\n');
fprintf('  P3.3 统一 modem API — DSSS + OTFS\n');
fprintf('========================================\n\n');

this_file  = mfilename('fullpath');
modmat     = fileparts(fileparts(this_file));                 % .../src/Matlab
mod14      = fileparts(fileparts(modmat));                    % .../14_Streaming
modules_root = fileparts(mod14);                             % .../modules
addpath(fullfile(modmat, 'common'));
addpath(fullfile(modmat, 'tx'));
addpath(fullfile(modmat, 'rx'));
addpath(fullfile(modules_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(modules_root, '03_Interleaving',  'src', 'Matlab'));
addpath(fullfile(modules_root, '05_SpreadSpectrum','src', 'Matlab'));
addpath(fullfile(modules_root, '06_MultiCarrier',  'src', 'Matlab'));
addpath(fullfile(modules_root, '07_ChannelEstEq',  'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform',      'src', 'Matlab'));
addpath(fullfile(modules_root, '12_IterativeProc', 'src', 'Matlab'));

sys = sys_params_default();

% 打开 diary
diary_path = fullfile(fileparts(this_file), 'test_p3_3_dsss_otfs_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

results = struct();
pass_count = 0;
fail_count = 0;

%% ============================================================
%% 1. DSSS 测试
%% ============================================================
fprintf('=== DSSS (DBPSK + Gold31 + Rake MRC) ===\n');

snr_list_dsss = [-5, 0, 5, 10];
% DSSS 信道抽头：chip_delays 映射到采样率
% body_bb 经 RRC 成形后采样率 = chip_rate * sps_dsss = 12000 * 4 = 48000
chip_delays = sys.dsss.chip_delays;
gains_dsss  = sys.dsss.gains_raw;
gains_dsss  = gains_dsss / sqrt(sum(abs(gains_dsss).^2));
sps_dsss    = sys.dsss.sps;
delays_samp_dsss = chip_delays * sps_dsss;

% 生成 FIR 信道
h_tap_dsss = zeros(1, max(delays_samp_dsss) + 1);
for p = 1:length(delays_samp_dsss)
    h_tap_dsss(delays_samp_dsss(p) + 1) = gains_dsss(p);
end

% 计算 N_info
codec = sys.codec;
n_code = 2;
mem    = codec.constraint_len - 1;
L_code = sys.dsss.code_len;
train_len = sys.dsss.train_len;
% M_coded = 2*(N_info+mem), N_dsss_sym = M_coded+1, 但 N_info 由上游指定
N_info_dsss = 200;

fprintf('N_info=%d, code_len=%d, train=%d, delays=[%s] chips\n', ...
    N_info_dsss, L_code, train_len, num2str(chip_delays));
fprintf('处理增益: %.1f dB\n\n', 10*log10(L_code));

ber_dsss = zeros(1, length(snr_list_dsss));
fprintf('%-6s |', 'SNR');
for si = 1:length(snr_list_dsss), fprintf(' %6ddB', snr_list_dsss(si)); end
fprintf('\n%s\n', repmat('-', 1, 6 + 8*length(snr_list_dsss)));

rng(200);
info_bits_dsss = randi([0 1], 1, N_info_dsss);

% TX 编码（只做一次）
[body_bb_dsss, meta_dsss] = modem_encode(info_bits_dsss, 'DSSS', sys);

% 信道卷积（无噪声基线）
rx_clean_dsss = conv(body_bb_dsss, h_tap_dsss);
rx_clean_dsss = rx_clean_dsss(1:length(body_bb_dsss));
sig_pwr_dsss  = mean(abs(rx_clean_dsss).^2);

fprintf('%-6s |', 'BER');
for si = 1:length(snr_list_dsss)
    snr_db = snr_list_dsss(si);
    nv_bb  = sig_pwr_dsss * 10^(-snr_db/10);
    rng(300 + si*100);
    noise = sqrt(nv_bb/2) * (randn(size(rx_clean_dsss)) + 1j*randn(size(rx_clean_dsss)));
    rx_noisy = rx_clean_dsss + noise;

    meta_dsss.noise_var = nv_bb;
    [bits_out, info_out] = modem_decode(rx_noisy, 'DSSS', sys, meta_dsss);

    nc = min(length(bits_out), N_info_dsss);
    ber = mean(bits_out(1:nc) ~= info_bits_dsss(1:nc));
    ber_dsss(si) = ber;
    fprintf(' %6.2f%%', ber*100);
end
fprintf('\n\n');

% 断言
for si = 1:length(snr_list_dsss)
    snr_db = snr_list_dsss(si);
    ber = ber_dsss(si);
    if snr_db >= 5
        if ber < 0.01
            pass_count = pass_count + 1;
            fprintf('  [PASS] DSSS @%ddB BER=%.3f%% < 1%%\n', snr_db, ber*100);
        else
            fail_count = fail_count + 1;
            fprintf('  [FAIL] DSSS @%ddB BER=%.3f%% >= 1%%\n', snr_db, ber*100);
        end
    end
end

%% ============================================================
%% 2. OTFS 测试
%% ============================================================
fprintf('\n=== OTFS (QPSK + LMMSE + Turbo×%d) ===\n', sys.otfs.turbo_iter);

snr_list_otfs = [5, 10, 15];
% OTFS body_bb 采样率 = sym_rate = 6000，信道时延单位 = 符号（DD域格点）
sym_delays_otfs = sys.otfs.sym_delays;
gains_otfs      = sys.otfs.gains_raw;

% OTFS 基带信道：delays 已是样本单位（sym_rate 采样）
h_tap_otfs = zeros(1, max(sym_delays_otfs) + 1);
for p = 1:length(sym_delays_otfs)
    h_tap_otfs(sym_delays_otfs(p) + 1) = gains_otfs(p);
end

% 计算 N_info
N_otfs = sys.otfs.N;
M_otfs = sys.otfs.M;
pilot_config_tmp = struct('mode', sys.otfs.pilot_mode, ...
    'guard_k', 4, 'guard_l', max(sym_delays_otfs) + 2, 'pilot_value', 1);
[~, ~, ~, di_tmp] = otfs_pilot_embed(zeros(1,1), N_otfs, M_otfs, pilot_config_tmp);
N_data_slots_otfs = length(di_tmp);
M_coded_otfs = N_data_slots_otfs * 2;  % QPSK
N_info_otfs  = M_coded_otfs / n_code - mem;

fprintf('N_info=%d, N=%d, M=%d, CP=%d, data_slots=%d\n', ...
    N_info_otfs, N_otfs, M_otfs, sys.otfs.cp_len, N_data_slots_otfs);
fprintf('delays=[%s] (DD格点)\n\n', num2str(sym_delays_otfs));

ber_otfs = zeros(1, length(snr_list_otfs));
fprintf('%-6s |', 'SNR');
for si = 1:length(snr_list_otfs), fprintf(' %6ddB', snr_list_otfs(si)); end
fprintf('\n%s\n', repmat('-', 1, 6 + 8*length(snr_list_otfs)));

rng(400);
info_bits_otfs = randi([0 1], 1, N_info_otfs);

% TX 编码
[body_bb_otfs, meta_otfs] = modem_encode(info_bits_otfs, 'OTFS', sys);

% 信道卷积
rx_clean_otfs = conv(body_bb_otfs, h_tap_otfs);
rx_clean_otfs = rx_clean_otfs(1:length(body_bb_otfs));
sig_pwr_otfs  = mean(abs(rx_clean_otfs).^2);

fprintf('%-6s |', 'BER');
for si = 1:length(snr_list_otfs)
    snr_db = snr_list_otfs(si);
    nv_bb  = sig_pwr_otfs * 10^(-snr_db/10);
    rng(500 + si*100);
    noise = sqrt(nv_bb/2) * (randn(size(rx_clean_otfs)) + 1j*randn(size(rx_clean_otfs)));
    rx_noisy = rx_clean_otfs + noise;

    meta_otfs.noise_var = nv_bb;
    [bits_out, info_out] = modem_decode(rx_noisy, 'OTFS', sys, meta_otfs);

    nc = min(length(bits_out), N_info_otfs);
    ber = mean(bits_out(1:nc) ~= info_bits_otfs(1:nc));
    ber_otfs(si) = ber;
    fprintf(' %6.2f%%', ber*100);
end
fprintf('\n\n');

% 断言
for si = 1:length(snr_list_otfs)
    snr_db = snr_list_otfs(si);
    ber = ber_otfs(si);
    if snr_db >= 15
        if ber < 0.05
            pass_count = pass_count + 1;
            fprintf('  [PASS] OTFS @%ddB BER=%.3f%% < 5%%\n', snr_db, ber*100);
        else
            fail_count = fail_count + 1;
            fprintf('  [FAIL] OTFS @%ddB BER=%.3f%% >= 5%%\n', snr_db, ber*100);
        end
    end
end

%% ============================================================
%% 3. 可视化
%% ============================================================
try
    % --- Figure 1: BER 曲线 ---
    figure('Position', [50 400 700 450]);
    semilogy(snr_list_dsss, max(ber_dsss, 1e-5), 'bo-', 'LineWidth', 1.8, ...
        'MarkerSize', 7, 'DisplayName', 'DSSS (Rake MRC)');
    hold on;
    semilogy(snr_list_otfs, max(ber_otfs, 1e-5), 'rs-', 'LineWidth', 1.8, ...
        'MarkerSize', 7, 'DisplayName', sprintf('OTFS (Turbo×%d)', sys.otfs.turbo_iter));
    % BPSK AWGN 理论
    snr_all = -5:1:20;
    snr_lin = 10.^(snr_all/10);
    semilogy(snr_all, max(0.5*erfc(sqrt(snr_lin)), 1e-5), 'k--', ...
        'LineWidth', 1, 'DisplayName', 'BPSK AWGN');
    semilogy(snr_all, max(0.5*erfc(sqrt(snr_lin*L_code)), 1e-5), 'g-.', ...
        'LineWidth', 1, 'DisplayName', sprintf('BPSK+PG(%ddB)', round(10*log10(L_code))));
    grid on; xlabel('SNR (dB)'); ylabel('BER');
    title('P3.3 — DSSS + OTFS 统一 modem BER');
    legend('Location', 'southwest'); ylim([1e-5 1]);
    set(gca, 'FontSize', 12);

    % --- Figure 2: DSSS 星座图 ---
    figure('Position', [50 50 500 350]);
    if exist('info_out', 'var') && isfield(info_out, 'pre_eq_syms')
        s = info_out.pre_eq_syms;
        plot(real(s), imag(s), 'b.', 'MarkerSize', 4);
        hold on; plot([-1 1], [0 0], 'rx', 'MarkerSize', 12, 'LineWidth', 2);
        axis equal; grid on;
        xlabel('I'); ylabel('Q');
        title('DSSS Rake 输出（DBPSK 参考点 ±1）');
    end
catch ME
    fprintf('可视化异常: %s\n', ME.message);
end

%% ============================================================
%% 4. 总结
%% ============================================================
fprintf('\n========================================\n');
fprintf('  PASS: %d    FAIL: %d\n', pass_count, fail_count);
fprintf('========================================\n');

if fail_count == 0
    fprintf('所有断言通过\n');
else
    fprintf('存在失败断言，请检查\n');
end

diary off;
fprintf('结果已保存: %s\n', diary_path);
