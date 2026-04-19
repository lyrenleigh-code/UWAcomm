%% test_p3_2_ofdm_sctde.m — P3.2 统一 modem API 回归测试（去oracle V2）
% 目的：验证 OFDM + SC-TDE 两体制下 BER 符合基线
% 去oracle：RX 不接收 TX 数据 / noise_var，只接收协议参数

clc; close all;
fprintf('========================================\n');
fprintf('  P3.2 统一 modem API — OFDM + SC-TDE（去oracle）\n');
fprintf('========================================\n\n');

this_file = mfilename('fullpath');
modmat    = fileparts(fileparts(this_file));
mod14     = fileparts(fileparts(modmat));
modules_root = fileparts(mod14);
addpath(fullfile(modmat, 'common'));
addpath(fullfile(modmat, 'tx'));
addpath(fullfile(modmat, 'rx'));
addpath(fullfile(modules_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(modules_root, '03_Interleaving',  'src', 'Matlab'));
addpath(fullfile(modules_root, '06_MultiCarrier',  'src', 'Matlab'));
addpath(fullfile(modules_root, '07_ChannelEstEq',  'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform',      'src', 'Matlab'));
addpath(fullfile(modules_root, '12_IterativeProc', 'src', 'Matlab'));

sys = sys_params_default();
sys.ofdm.fading_type  = 'static';
sys.ofdm.fd_hz        = 0;
sys.sctde.fading_type = 'static';
sys.sctde.fd_hz       = 0;

snr_list = [5, 10, 15];
sym_delays_smp = sys.ofdm.sym_delays;
gains_raw      = sys.ofdm.gains_raw;

diary_path = fullfile(fileparts(this_file), 'test_p3_2_ofdm_sctde_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

results = struct();

for s_idx = 1:2
    if s_idx == 1
        scheme = 'OFDM';
        null_idx  = 1:sys.ofdm.null_spacing:sys.ofdm.blk_fft;
        data_idx  = setdiff(1:sys.ofdm.blk_fft, null_idx);
        N_data_sc = length(data_idx);
        N_data_blocks = sys.ofdm.N_blocks - 1;  % V2: block 1 = 导频
        M_total   = 2 * N_data_sc * N_data_blocks;
        mem       = sys.codec.constraint_len - 1;
        N_info    = M_total / 2 - mem;
    else
        scheme = 'SC-TDE';
        N_data_sym = 2000;
        M_coded    = 2 * N_data_sym;
        mem        = sys.codec.constraint_len - 1;
        N_info     = M_coded / 2 - mem;
    end

    fprintf('\n===== 体制: %s (N_info=%d) =====\n', scheme, N_info);
    rng(123 + s_idx);
    info_bits = randi([0 1], 1, N_info);

    [body_bb, meta_tx] = modem_encode(info_bits, scheme, sys);
    fprintf('[TX] body_bb 样本数=%d, scheme=%s\n', length(body_bb), scheme);

    ber_vec = zeros(size(snr_list));
    for k_snr = 1:length(snr_list)
        snr_db = snr_list(k_snr);

        delays_samp = round(sym_delays_smp * sys.sps);
        h_tap = zeros(1, max(delays_samp)+1);
        for p = 1:length(delays_samp)
            h_tap(delays_samp(p)+1) = h_tap(delays_samp(p)+1) + gains_raw(p);
        end
        h_tap = h_tap / norm(h_tap);

        rx_bb_clean = conv(body_bb, h_tap);
        rx_bb_clean = rx_bb_clean(1:length(body_bb));

        sig_pwr = mean(abs(rx_bb_clean).^2);
        noise_var = sig_pwr * 10^(-snr_db/10);
        rng(500 + s_idx*10 + k_snr);
        noise = sqrt(noise_var/2) * (randn(size(rx_bb_clean)) + 1j*randn(size(rx_bb_clean)));
        body_rx_bb = rx_bb_clean + noise;

        % 去oracle：meta_tx V2 已不含 all_cp_data / all_sym / noise_var
        meta_rx = meta_tx;

        [bits_out, info] = modem_decode(body_rx_bb, scheme, sys, meta_rx);

        nc = min(length(bits_out), length(info_bits));
        ber = mean(bits_out(1:nc) ~= info_bits(1:nc));
        ber_vec(k_snr) = ber;

        fprintf('  SNR=%2ddB  BER=%.4f (%.2f%%)  iter=%d conv=%d est_snr=%.1fdB\n', ...
            snr_db, ber, ber*100, info.turbo_iter, info.convergence_flag, ...
            info.estimated_snr);
    end

    results.(matlab.lang.makeValidName(scheme)).snr = snr_list;
    results.(matlab.lang.makeValidName(scheme)).ber = ber_vec;
end

%% 汇总
fprintf('\n========================================\n');
fprintf('P3.2 BER 汇总（去oracle）\n');
fprintf('========================================\n');
fprintf('%-10s |', 'scheme');
for si = 1:length(snr_list), fprintf(' %5ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-', 1, 10 + 8*length(snr_list)));

fields = fieldnames(results);
for fi = 1:length(fields)
    fprintf('%-10s |', fields{fi});
    for si = 1:length(snr_list)
        fprintf(' %5.2f%%', results.(fields{fi}).ber(si) * 100);
    end
    fprintf('\n');
end

%% 验收
fprintf('\n--- 验收 (OFDM ≤1%%@15dB, SC-TDE ≤1%%@15dB) ---\n');
pass_count = 0; total_checks = 0;

ofdm_ber_15 = results.OFDM.ber(snr_list == 15);
if ~isempty(ofdm_ber_15)
    total_checks = total_checks + 1;
    if ofdm_ber_15 < 0.01
        pass_count = pass_count + 1;
        fprintf('  [PASS] OFDM @15dB BER=%.3f%% (<1%%)\n', ofdm_ber_15*100);
    else
        fprintf('  [FAIL] OFDM @15dB BER=%.3f%% (期望<1%%)\n', ofdm_ber_15*100);
    end
end

sctde_ber_15 = results.SC_TDE.ber(snr_list == 15);
if ~isempty(sctde_ber_15)
    total_checks = total_checks + 1;
    if sctde_ber_15 < 0.01
        pass_count = pass_count + 1;
        fprintf('  [PASS] SC-TDE @15dB BER=%.3f%% (<1%%)\n', sctde_ber_15*100);
    else
        fprintf('  [FAIL] SC-TDE @15dB BER=%.3f%% (期望<1%%)\n', sctde_ber_15*100);
    end
end

fprintf('\n结果：%d/%d 通过\n', pass_count, total_checks);

diary off;
fprintf('\n日志写入: %s\n', diary_path);
