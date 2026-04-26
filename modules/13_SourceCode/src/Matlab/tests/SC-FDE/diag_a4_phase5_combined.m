function diag_a4_phase5_combined()
% DIAG_A4_PHASE5_COMBINED
%
% Phase 4+5 组合验证：多 train block (K) × block-pilot (pilot_per_blk) 双维度
%
% 重点：K=4 + pilot=64 case（A+E 组合，预期 fd=1Hz < 5% + 吞吐损失 ~44%）
%
% 接受准则：
%   K=4 + pilot=64 fd=1Hz BER < 5%
%   K=4 + pilot=64 fd=5Hz BER < 10%
%   static 任意组合不退化

clc; close all;
this_dir       = fileparts(mfilename('fullpath'));
sc_fde_dir     = this_dir;
tests_dir      = fileparts(sc_fde_dir);
sourcecode_dir = fileparts(tests_dir);
matlab_dir     = fileparts(sourcecode_dir);
mod13_root     = fileparts(matlab_dir);
modules_root   = fileparts(mod13_root);

addpath(fullfile(modules_root, '14_Streaming', 'src', 'Matlab', 'common'));
addpath(fullfile(modules_root, '14_Streaming', 'src', 'Matlab', 'tx'));
addpath(fullfile(modules_root, '14_Streaming', 'src', 'Matlab', 'rx'));
addpath(fullfile(modules_root, '13_SourceCode', 'src', 'Matlab', 'common'));
addpath(fullfile(modules_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(modules_root, '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(modules_root, '04_Modulation', 'src', 'Matlab'));
addpath(fullfile(modules_root, '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(modules_root, '12_IterativeProc', 'src', 'Matlab'));

diary_file = fullfile(this_dir, 'diag_a4_phase5_combined_results.txt');
if exist(diary_file, 'file'), delete(diary_file); end
diary(diary_file);
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('========================================\n');
fprintf('  A4 Phase 4+5 组合：K × pilot 双维度\n');
fprintf('  时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('========================================\n\n');

%% --- 1. 系统参数 ---
sys = sys_params_default();
sys.scfde.blk_fft   = 256;
sys.scfde.blk_cp    = 128;
sys.scfde.N_blocks  = 16;
sys.scfde.turbo_iter = 6;
sym_delays = sys.scfde.sym_delays;
gains_raw  = sys.scfde.gains_raw;
fs       = sys.fs;
fc       = sys.fc;
sym_rate = sys.sym_rate;
n_code = 2;
mem    = sys.codec.constraint_len - 1;

fprintf('系统: fs=%dHz fc=%dHz sps=%d sym_rate=%d\n', fs, fc, sys.sps, sym_rate);
fprintf('SC-FDE: blk_fft=%d blk_cp=%d N_blocks=%d turbo_iter=%d max_tau=%d\n', ...
        sys.scfde.blk_fft, sys.scfde.blk_cp, sys.scfde.N_blocks, sys.scfde.turbo_iter, max(sym_delays));

%% --- 2. 测试矩阵 ---
% (K, pilot) 组合：精选 baseline + key 实验点
combos = {
    'K15_p0',     15,   0,   'baseline (Phase 1)';
    'K15_p128',   15,   128, '方案 E 纯版本 50%';
    'K4_p0',      4,    0,   'Phase 4-revision (4 train, no pilot)';
    'K4_p64',     4,    64,  'A+E 组合（推荐）';
    'K4_p32',     4,    32,  'A+E 组合 (轻 pilot)';
    'K8_p64',     8,    64,  'A+E 中等 train + pilot';
};

fading_cfgs = {
    'static', 'static', 0, 0;
    'fd=1Hz', 'slow',   1, 0;
    'fd=5Hz', 'slow',   5, 0;
};
snr_list = [5, 10, 15, 20];
seed_list = [1, 2, 3];

n_combo = size(combos, 1);
n_fad   = size(fading_cfgs, 1);
n_snr   = length(snr_list);
n_seed  = length(seed_list);

ber_matrix = zeros(n_combo, n_fad, n_snr, n_seed);

%% --- 3. 主循环 ---
for ci = 1:n_combo
    label = combos{ci, 1};
    K = combos{ci, 2};
    pilot_per_blk = combos{ci, 3};
    desc = combos{ci, 4};

    sys.scfde.train_period_K = K;
    sys.scfde.pilot_per_blk = pilot_per_blk;

    % N_train / N_data 派生
    if K >= sys.scfde.N_blocks - 1
        N_train_blocks_actual = 1;
        train_indices_tmp = 1;
    else
        N_train_blocks_actual = floor(sys.scfde.N_blocks/(K+1)) + 1;
        train_indices_tmp = round(linspace(1, sys.scfde.N_blocks, N_train_blocks_actual));
        train_indices_tmp = unique(train_indices_tmp);
        N_train_blocks_actual = length(train_indices_tmp);
    end
    N_data_blocks_actual = sys.scfde.N_blocks - N_train_blocks_actual;
    N_data_per_blk_actual = sys.scfde.blk_fft - pilot_per_blk;
    M_total_actual = 2 * N_data_per_blk_actual * N_data_blocks_actual;
    N_info_actual = M_total_actual / n_code - mem;

    % 吞吐：(N_data 块 × data 段) / (N_blocks × blk_fft)
    throughput = 100 * (N_data_blocks_actual * N_data_per_blk_actual) / (sys.scfde.N_blocks * sys.scfde.blk_fft);

    fprintf('\n========================================\n');
    fprintf('  [%s] K=%d pilot=%d (N_train=%d, N_data=%d, 吞吐 %.1f%%)\n', ...
            label, K, pilot_per_blk, N_train_blocks_actual, N_data_blocks_actual, throughput);
    fprintf('  %s\n', desc);
    fprintf('========================================\n');

    for fi = 1:n_fad
        fname = fading_cfgs{fi, 1};
        ftype = fading_cfgs{fi, 2};
        fd_hz = fading_cfgs{fi, 3};
        dop_rate = fading_cfgs{fi, 4};

        fprintf('\n--- fading=%s (fd=%g Hz) ---\n', fname, fd_hz);

        for seed = 1:n_seed
            s = seed_list(seed);
            rng(uint32(100 + ci*10000 + fi*1000 + s*10), 'twister');
            info_bits = randi([0 1], 1, N_info_actual);

            [body_bb, meta] = modem_encode_scfde(info_bits, sys);

            ch_params = struct('fs', fs, 'delay_profile', 'custom', ...
                'delays_s', sym_delays / sym_rate, 'gains', gains_raw, ...
                'num_paths', length(sym_delays), 'doppler_rate', dop_rate, ...
                'fading_type', ftype, 'fading_fd_hz', fd_hz, ...
                'snr_db', Inf, 'seed', 200 + ci*1000 + fi*100 + s);
            [rx_bb_clean, ~] = gen_uwa_channel(body_bb, ch_params);

            [rx_pb_clean, ~] = upconvert(rx_bb_clean, fs, fc);
            sig_pwr = mean(rx_pb_clean.^2);

            for si = 1:n_snr
                snr_db = snr_list(si);
                noise_var = sig_pwr * 10^(-snr_db/10);
                rng(uint32(300 + ci*10000 + fi*1000 + si*100 + s), 'twister');
                rx_pb = rx_pb_clean + sqrt(noise_var) * randn(size(rx_pb_clean));

                lpf_bw = sym_rate * (1 + sys.scfde.rolloff) / 2;
                [bb_rx, ~] = downconvert(rx_pb, fs, fc, lpf_bw);

                try
                    [bits_decoded, ~] = modem_decode_scfde(bb_rx, sys, meta);
                    ber = mean(bits_decoded(1:N_info_actual) ~= info_bits);
                    ber_matrix(ci, fi, si, seed) = ber;
                catch ME
                    fprintf('  [ERR] ci=%d fi=%d si=%d seed=%d: %s\n', ci, fi, si, seed, ME.message);
                    ber_matrix(ci, fi, si, seed) = NaN;
                end

                fprintf('  [%s] seed=%d SNR=%2ddB  BER=%6.2f%%\n', ...
                        label, s, snr_db, ber_matrix(ci,fi,si,seed)*100);
            end
        end
    end
end

%% --- 4. 汇总 ---
fprintf('\n\n========================================\n');
fprintf('  汇总：BER mean across %d seeds\n', n_seed);
fprintf('========================================\n');
for ci = 1:n_combo
    label = combos{ci, 1};
    K = combos{ci, 2};
    pilot_per_blk = combos{ci, 3};
    if K >= sys.scfde.N_blocks - 1
        N_train_b = 1;
    else
        N_train_b = floor(sys.scfde.N_blocks/(K+1)) + 1;
        ti_tmp = round(linspace(1, sys.scfde.N_blocks, N_train_b));
        N_train_b = length(unique(ti_tmp));
    end
    N_data_b = sys.scfde.N_blocks - N_train_b;
    throughput = 100 * (N_data_b * (sys.scfde.blk_fft - pilot_per_blk)) / (sys.scfde.N_blocks * sys.scfde.blk_fft);
    fprintf('\n--- [%s] K=%d pilot=%d (吞吐 %.1f%%) ---\n', label, K, pilot_per_blk, throughput);
    fprintf('%-10s |', '');
    for si = 1:n_snr, fprintf(' %6ddB', snr_list(si)); end
    fprintf('\n%s\n', repmat('-', 1, 10 + 8*n_snr));
    for fi = 1:n_fad
        fprintf('%-10s |', fading_cfgs{fi, 1});
        for si = 1:n_snr
            ber_mean = mean(ber_matrix(ci, fi, si, :), 'omitnan') * 100;
            fprintf(' %6.2f%%', ber_mean);
        end
        fprintf('\n');
    end
end

%% --- 5. 趋势 ---
fprintf('\n\n========================================\n');
fprintf('  combo vs BER 趋势（mean SNR={5,10,15,20} × 3 seed）\n');
fprintf('========================================\n');
fprintf('%-12s |', '');
for ci = 1:n_combo, fprintf(' %-10s |', combos{ci,1}); end
fprintf('\n');
for fi = 1:n_fad
    fprintf('%-12s |', fading_cfgs{fi, 1});
    for ci = 1:n_combo
        ber_mean = mean(ber_matrix(ci, fi, :, :), 'all', 'omitnan') * 100;
        fprintf(' %8.2f%%  |', ber_mean);
    end
    fprintf('\n');
end

%% --- 6. 接受准则 ---
fprintf('\n\n========================================\n');
fprintf('  Phase 4+5 组合接受准则\n');
fprintf('========================================\n');

% 找最佳组合（fd=1Hz BER 最低 + 吞吐最高）
best_ci = -1;
best_ber = 100;
best_throughput = 0;
for ci = 1:n_combo
    K = combos{ci, 2};
    pilot_per_blk = combos{ci, 3};
    if K >= sys.scfde.N_blocks - 1, N_train_b = 1;
    else, N_train_b = length(unique(round(linspace(1, sys.scfde.N_blocks, floor(sys.scfde.N_blocks/(K+1)) + 1))));
    end
    N_data_b = sys.scfde.N_blocks - N_train_b;
    throughput = 100 * (N_data_b * (sys.scfde.blk_fft - pilot_per_blk)) / (sys.scfde.N_blocks * sys.scfde.blk_fft);

    ber_fd1 = mean(ber_matrix(ci, 2, :, :), 'all', 'omitnan') * 100;
    ber_fd5 = mean(ber_matrix(ci, 3, :, :), 'all', 'omitnan') * 100;
    ber_static = mean(ber_matrix(ci, 1, 3:4, :), 'all', 'omitnan') * 100;
    pass_fd1 = ber_fd1 < 5;
    pass_fd5 = ber_fd5 < 10;
    pass_static = ber_static < 5;
    fprintf('[%-10s] static SNR15+={%5.2f%%} %s | fd=1Hz=%5.2f%% %s | fd=5Hz=%5.2f%% %s | 吞吐=%5.1f%%\n', ...
            combos{ci,1}, ber_static, tern(pass_static), ...
            ber_fd1, tern(pass_fd1), ber_fd5, tern(pass_fd5), throughput);

    % best：fd=1Hz < 5% + fd=5Hz < 10% + 吞吐最高
    if pass_fd1 && pass_fd5 && pass_static && throughput > best_throughput
        best_throughput = throughput;
        best_ci = ci;
    end
end

if best_ci > 0
    fprintf('\n最佳组合 [%s]: K=%d pilot=%d, 吞吐 %.1f%%\n', ...
            combos{best_ci,1}, combos{best_ci,2}, combos{best_ci,3}, best_throughput);
else
    fprintf('\n无组合同时通过 fd=1Hz<5%% + fd=5Hz<10%% + static<5%%\n');
end

fprintf('\n日志: %s\n', diary_file);
fprintf('========================================\n');

end


function s = tern(ok)
if ok, s = '✅'; else, s = '❌'; end
end
