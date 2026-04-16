%% test_p3_unified_modem.m — P3.1 统一 modem API 回归测试
% 目的：验证 modem_encode/modem_decode 在 FH-MFSK + SC-FDE 两体制下 BER 符合基线
% 场景：静态 6 径多径 + 基带复 AWGN（bypass passband，聚焦 modem 本身正确性）
% 基线参考：
%   - FH-MFSK: 0%@5dB+（13_SourceCode/tests/FH-MFSK/test_fhmfsk_timevarying.m, static）
%   - SC-FDE : 0%@10dB+（13_SourceCode/tests/SC-FDE/test_scfde_timevarying.m, static）

clc; close all;
fprintf('========================================\n');
fprintf('  P3.1 统一 modem API — FH-MFSK + SC-FDE\n');
fprintf('========================================\n\n');

this_file = mfilename('fullpath');
modmat    = fileparts(fileparts(this_file));                 % ...\src\Matlab
mod14     = fileparts(fileparts(modmat));                    % ...\14_Streaming
modules_root = fileparts(mod14);                             % ...\modules
proj_root = fileparts(modules_root);                         % UWAcomm
addpath(fullfile(modmat, 'common'));
addpath(fullfile(modmat, 'tx'));
addpath(fullfile(modmat, 'rx'));
addpath(fullfile(modules_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(modules_root, '03_Interleaving',  'src', 'Matlab'));
addpath(fullfile(modules_root, '05_SpreadSpectrum','src', 'Matlab'));
addpath(fullfile(modules_root, '07_ChannelEstEq',  'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform',      'src', 'Matlab'));

sys = sys_params_default();
sys.scfde.fading_type = 'static';
sys.scfde.fd_hz       = 0;

snr_list = [5, 10, 15];
sym_delays_smp = sys.scfde.sym_delays;   % 以 symbol 周期为单位
gains_raw      = sys.scfde.gains_raw;

% 打开 diary
diary_path = fullfile(fileparts(this_file), 'test_p3_unified_modem_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

results = struct();

for s_idx = 1:2
    if s_idx == 1
        scheme = 'FH-MFSK';
        N_info = sys.frame.body_bits;                 % 2192 比特
    else
        scheme = 'SC-FDE';
        % SC-FDE 的 N_info 受分块约束：M_total = 2*blk_fft*N_blocks, N_info = M_total/2 - mem
        mem = sys.codec.constraint_len - 1;
        N_info = 2 * sys.scfde.blk_fft * sys.scfde.N_blocks / 2 - mem;
    end

    fprintf('\n===== 体制: %s (N_info=%d) =====\n', scheme, N_info);
    rng(123 + s_idx);
    info_bits = randi([0 1], 1, N_info);

    %% TX
    [body_bb, meta_tx] = modem_encode(info_bits, scheme, sys);
    fprintf('[TX] body_bb 样本数=%d, scheme=%s\n', length(body_bb), scheme);

    ber_vec = zeros(size(snr_list));
    for k_snr = 1:length(snr_list)
        snr_db = snr_list(k_snr);

        %% 信道：基带复多径卷积（以 symbol 采样 × sps 为单位）
        switch upper(strrep(scheme, '-', ''))
            case 'FHMFSK'
                % FH-MFSK 直接按 body_bb 样本点为信道时延单位
                delays_samp = round(sym_delays_smp * sys.fhmfsk.samples_per_sym / 8);
            case 'SCFDE'
                % 与 SC-FDE baseline 一致：delays_s = sym_delays/sym_rate
                delays_samp = round(sym_delays_smp * sys.sps);
        end
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

        % 注入噪声方差给 decoder（SC-FDE 信道估计需要）
        meta_rx = meta_tx;
        meta_rx.noise_var = noise_var;

        %% RX
        [bits_out, info] = modem_decode(body_rx_bb, scheme, sys, meta_rx);

        nc = min(length(bits_out), length(info_bits));
        ber = mean(bits_out(1:nc) ~= info_bits(1:nc));
        ber_vec(k_snr) = ber;

        fprintf('  SNR=%2ddB  BER=%.4f (%.2f%%)  iter=%d conv=%d est_snr=%.1fdB est_ber=%.3e\n', ...
            snr_db, ber, ber*100, info.turbo_iter, info.convergence_flag, ...
            info.estimated_snr, info.estimated_ber);
    end

    results.(matlab.lang.makeValidName(scheme)).snr = snr_list;
    results.(matlab.lang.makeValidName(scheme)).ber = ber_vec;
end

%% 汇总
fprintf('\n========================================\n');
fprintf('P3.1 BER 汇总\n');
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
fprintf('\n--- 验收 (基线: FH-MFSK 0%%@5dB+, SC-FDE 0%%@10dB+, ±0.5%%) ---\n');
pass_count = 0; total_checks = 0;

fhm_ber_10 = results.FH_MFSK.ber(snr_list == 10);
if ~isempty(fhm_ber_10)
    total_checks = total_checks + 1;
    if fhm_ber_10 < 0.005
        pass_count = pass_count + 1;
        fprintf('  [PASS] FH-MFSK @10dB BER=%.3f%% (<0.5%%)\n', fhm_ber_10*100);
    else
        fprintf('  [FAIL] FH-MFSK @10dB BER=%.3f%% (期望<0.5%%)\n', fhm_ber_10*100);
    end
end

scf_ber_15 = results.SC_FDE.ber(snr_list == 15);
if ~isempty(scf_ber_15)
    total_checks = total_checks + 1;
    if scf_ber_15 < 0.005
        pass_count = pass_count + 1;
        fprintf('  [PASS] SC-FDE @15dB BER=%.3f%% (<0.5%%)\n', scf_ber_15*100);
    else
        fprintf('  [FAIL] SC-FDE @15dB BER=%.3f%% (期望<0.5%%)\n', scf_ber_15*100);
    end
end

fprintf('\n结果：%d/%d 通过\n', pass_count, total_checks);

diary off;
fprintf('\n日志写入: %s\n', diary_path);
