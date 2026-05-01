function diag_p4_v40_preset_validation()
% DIAG_P4_V40_PRESET_VALIDATION
%
% 目的：验证 P4 UI "V4.0 推荐预设" 按钮值是否真能激活 V4.0 突破
%       通过直接调 modem_encode/decode_scfde（绕开 UI 同步链）
%
% 对比 4 套配置 × jakes fd=1Hz × SNR={10, 15, 20} × 3 seed：
%   PRESET_v0 — UI 默认 (V1.0 兼容: blk_fft=128, blk_cp=128, pilot=0,  K=31, N_blocks=32)
%   PRESET_v1 — 我的预设 (blk_fft=256, blk_cp=128, pilot=128, K=8,  N_blocks=32) ← 待验证
%   PRESET_v2 — Archive 配置 (blk_fft=256, blk_cp=128, pilot=128, K=15, N_blocks=16) ← 黄金标准
%   PRESET_v3 — N=32 单训 (blk_fft=256, blk_cp=128, pilot=128, K=31, N_blocks=32) ← 替代候选
%
% Archive 实测 (V5b PASS): PRESET_v2 fd=1Hz BER mean = 3.37%
% 期望：PRESET_v0 ~50%，PRESET_v2 ~3.37%，v1 / v3 待测

clc; close all;
this_dir       = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
mod14_root     = fileparts(fileparts(streaming_root));
modules_root   = fileparts(mod14_root);

addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(modules_root, '13_SourceCode', 'src', 'Matlab', 'common'));
addpath(fullfile(modules_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(modules_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(modules_root, '04_Modulation', 'src', 'Matlab'));
addpath(fullfile(modules_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(modules_root, '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(modules_root, '12_IterativeProc', 'src', 'Matlab'));

diary_file = fullfile(this_dir, 'diag_p4_v40_preset_validation_results.txt');
if exist(diary_file, 'file'), delete(diary_file); end
diary(diary_file);
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('========================================\n');
fprintf('  P4 V4.0 预设验证 (jakes fd=1Hz)\n');
fprintf('  时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('========================================\n\n');

%% --- 系统参数 ---
sys_base = sys_params_default();
sym_delays = sys_base.scfde.sym_delays;
gains_raw  = sys_base.scfde.gains_raw;
fs       = sys_base.fs;
fc       = sys_base.fc;
sym_rate = sys_base.sym_rate;
n_code = 2;
mem    = sys_base.codec.constraint_len - 1;

%% --- 4 套预设 ---
presets = {
    'v0_default',      128, 128, 0,   31, 32;
    'v1_my_preset',    256, 128, 128, 8,  32;
    'v2_archive_gold', 256, 128, 128, 15, 16;
    'v3_N32_singletr', 256, 128, 128, 31, 32;
};

snr_list = [10, 15, 20];
seed_list = [1, 2, 3];

n_pre = size(presets, 1);
n_snr = length(snr_list);
n_seed = length(seed_list);

ber_matrix = zeros(n_pre, n_snr, n_seed);

%% --- 主循环 ---
for pri = 1:n_pre
    pname    = presets{pri, 1};
    blk_fft  = presets{pri, 2};
    blk_cp   = presets{pri, 3};
    pilot    = presets{pri, 4};
    K        = presets{pri, 5};
    N_blocks = presets{pri, 6};

    sys = sys_base;
    sys.scfde.blk_fft         = blk_fft;
    sys.scfde.blk_cp          = blk_cp;
    sys.scfde.N_blocks        = N_blocks;
    sys.scfde.pilot_per_blk   = pilot;
    sys.scfde.train_period_K  = K;
    sys.scfde.fading_type     = 'jakes';
    sys.scfde.fd_hz           = 1;
    sys.scfde.turbo_iter      = 6;

    fprintf('\n========================================\n');
    fprintf('  PRESET %s: blk_fft=%d blk_cp=%d pilot=%d K=%d N_blocks=%d\n', ...
        pname, blk_fft, blk_cp, pilot, K, N_blocks);
    fprintf('========================================\n');

    % N_info derive (与 modem_encode_scfde V4.0 公式一致)
    if K >= N_blocks - 1
        N_train_blocks = 1;
    else
        train_idx = round(linspace(1, N_blocks, floor(N_blocks/(K+1))+1));
        N_train_blocks = length(unique(train_idx));
    end
    N_data_blocks  = N_blocks - N_train_blocks;
    N_data_per_blk = blk_fft - pilot;
    M_total = 2 * N_data_per_blk * N_data_blocks;
    N_info  = M_total / n_code - mem;
    fprintf('  N_train_blocks=%d N_data_blocks=%d N_data_per_blk=%d N_info=%d\n', ...
        N_train_blocks, N_data_blocks, N_data_per_blk, N_info);

    for seed = 1:n_seed
        s = seed_list(seed);
        rng(uint32(100 + pri*10000 + s*10), 'twister');
        info_bits = randi([0 1], 1, N_info);

        try
            [body_bb, meta] = modem_encode_scfde(info_bits, sys);
        catch ME
            fprintf('  [ENC-ERR] seed=%d: %s\n', s, ME.message);
            ber_matrix(pri, :, seed) = NaN;
            continue;
        end

        ch_params = struct('fs', fs, 'delay_profile', 'custom', ...
            'delays_s', sym_delays / sym_rate, 'gains', gains_raw, ...
            'num_paths', length(sym_delays), 'doppler_rate', 0, ...
            'fading_type', 'slow', 'fading_fd_hz', 1, ...
            'snr_db', Inf, 'seed', 200 + pri*1000 + s);
        [rx_bb_clean, ~] = gen_uwa_channel(body_bb, ch_params);

        [rx_pb_clean, ~] = upconvert(rx_bb_clean, fs, fc);
        sig_pwr = mean(rx_pb_clean.^2);

        for si = 1:n_snr
            snr_db = snr_list(si);
            noise_var = sig_pwr * 10^(-snr_db/10);
            rng(uint32(300 + pri*10000 + si*100 + s), 'twister');
            rx_pb = rx_pb_clean + sqrt(noise_var) * randn(size(rx_pb_clean));

            lpf_bw = sym_rate * (1 + sys.scfde.rolloff) / 2;
            [bb_rx, ~] = downconvert(rx_pb, fs, fc, lpf_bw);

            try
                [bits_decoded, ~] = modem_decode_scfde(bb_rx, sys, meta);
                ber = mean(bits_decoded(1:N_info) ~= info_bits);
                ber_matrix(pri, si, seed) = ber;
            catch ME
                fprintf('  [DEC-ERR] seed=%d SNR=%ddB: %s\n', s, snr_db, ME.message);
                ber_matrix(pri, si, seed) = NaN;
            end

            fprintf('  seed=%d SNR=%2ddB  BER=%6.2f%%\n', ...
                s, snr_db, ber_matrix(pri,si,seed)*100);
        end
    end
end

%% --- 汇总 ---
fprintf('\n\n========================================\n');
fprintf('  汇总 (jakes fd=1Hz, %d seed mean)\n', n_seed);
fprintf('========================================\n');
fprintf('%-22s |', 'PRESET');
for si = 1:n_snr, fprintf(' SNR=%2ddB |', snr_list(si)); end
fprintf(' MEAN ALL\n');
fprintf('%s\n', repmat('-', 1, 22 + 12*n_snr + 12));
for pri = 1:n_pre
    fprintf('%-22s |', presets{pri, 1});
    row_sum = 0; row_n = 0;
    for si = 1:n_snr
        ber_mean = mean(ber_matrix(pri, si, :), 'omitnan') * 100;
        fprintf(' %7.2f%% |', ber_mean);
        row_sum = row_sum + ber_mean;
        row_n = row_n + 1;
    end
    fprintf(' %7.2f%%\n', row_sum / row_n);
end

fprintf('\n[archive 标准] v2_archive_gold fd=1Hz BER mean ~3.37%% (V5b PASS)\n');

end
