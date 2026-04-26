function diag_a3_phase5_block_pilot()
% DIAG_A3_PHASE5_BLOCK_PILOT
%
% Phase 5 V5a/V5b/V5c 验证：14_Streaming production × block-pilot 末尾插入（方案 E）
%
% A3 脚本基于 A1/A2，加 pilot_per_blk 参数循环：
%   pilot_per_blk = 0  → 禁用方案 E（与 A1 baseline 等价）
%   pilot_per_blk = 32 → 12.5% 吞吐损失
%   pilot_per_blk = 64 → 25% 吞吐损失
%   pilot_per_blk = 96 → 37.5% 吞吐损失
%   pilot_per_blk =128 → 50% 吞吐损失（=blk_cp，CP 全 pilot）
%
% 接受准则（spec L88 Phase 5）：
%   V5a static 任意 pilot_per_blk 不退化
%   V5b fd=1Hz pilot_per_blk={32,64,96,128} BER 趋势：恢复 Phase 1 水平
%   V5c fd=5Hz pilot_per_blk=64 BER < 10%

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

diary_file = fullfile(this_dir, 'diag_a3_phase5_block_pilot_results.txt');
if exist(diary_file, 'file'), delete(diary_file); end
diary(diary_file);
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('========================================\n');
fprintf('  A3 Phase 5 验证：block-pilot 末尾插入（方案 E）\n');
fprintf('  时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('========================================\n\n');

%% --- 1. 系统参数 ---
sys = sys_params_default();
sys.scfde.blk_fft   = 256;
sys.scfde.blk_cp    = 128;
sys.scfde.N_blocks  = 16;
sys.scfde.turbo_iter = 6;
sys.scfde.train_period_K = sys.scfde.N_blocks - 1;   % 单训练块（专注 pilot 测试，不混入多 train）
sym_delays = sys.scfde.sym_delays;
gains_raw  = sys.scfde.gains_raw;
fs       = sys.fs;
fc       = sys.fc;
sym_rate = sys.sym_rate;
n_code = 2;
mem    = sys.codec.constraint_len - 1;

fprintf('系统: fs=%dHz fc=%dHz sps=%d sym_rate=%d\n', fs, fc, sys.sps, sym_rate);
fprintf('SC-FDE: blk_fft=%d blk_cp=%d N_blocks=%d turbo_iter=%d\n', ...
        sys.scfde.blk_fft, sys.scfde.blk_cp, sys.scfde.N_blocks, sys.scfde.turbo_iter);
fprintf('多径: sym_delays=[%s], max_tau=%d\n', ...
        strjoin(arrayfun(@(x)sprintf('%d',x),sym_delays,'UniformOutput',false), ' '), max(sym_delays));

%% --- 2. 测试矩阵 ---
% pilot_per_blk 候选：0(baseline) / 32 / 64 / 96 / 128(=blk_cp)
pilot_list = [0, 32, 64, 96, 128];

fading_cfgs = {
    'static', 'static', 0, 0;
    'fd=1Hz', 'slow',   1, 0;
    'fd=5Hz', 'slow',   5, 0;
};
snr_list = [5, 10, 15, 20];
seed_list = [1, 2, 3];

n_pilot = length(pilot_list);
n_fad   = size(fading_cfgs, 1);
n_snr   = length(snr_list);
n_seed  = length(seed_list);

ber_matrix = zeros(n_pilot, n_fad, n_snr, n_seed);

%% --- 3. 主循环 ---
for pi = 1:n_pilot
    pilot_per_blk = pilot_list(pi);
    sys.scfde.pilot_per_blk = pilot_per_blk;
    N_data_per_blk = sys.scfde.blk_fft - pilot_per_blk;
    throughput = 100 * N_data_per_blk / sys.scfde.blk_fft;

    fprintf('\n========================================\n');
    fprintf('  pilot_per_blk=%d (N_data_per_blk=%d, 吞吐 %.1f%%)\n', ...
            pilot_per_blk, N_data_per_blk, throughput);
    fprintf('========================================\n');

    for fi = 1:n_fad
        fname = fading_cfgs{fi, 1};
        ftype = fading_cfgs{fi, 2};
        fd_hz = fading_cfgs{fi, 3};
        dop_rate = fading_cfgs{fi, 4};

        fprintf('\n--- fading=%s (fd=%g Hz) ---\n', fname, fd_hz);

        for seed = 1:n_seed
            s = seed_list(seed);
            rng(uint32(100 + pi*10000 + fi*1000 + s*10), 'twister');

            % N_info derive
            N_data_blocks = sys.scfde.N_blocks - 1;  % 单训练块
            M_total_actual = 2 * N_data_per_blk * N_data_blocks;
            N_info_actual = M_total_actual / n_code - mem;
            info_bits = randi([0 1], 1, N_info_actual);

            [body_bb, meta] = modem_encode_scfde(info_bits, sys);

            ch_params = struct('fs', fs, 'delay_profile', 'custom', ...
                'delays_s', sym_delays / sym_rate, 'gains', gains_raw, ...
                'num_paths', length(sym_delays), 'doppler_rate', dop_rate, ...
                'fading_type', ftype, 'fading_fd_hz', fd_hz, ...
                'snr_db', Inf, 'seed', 200 + pi*1000 + fi*100 + s);
            [rx_bb_clean, ~] = gen_uwa_channel(body_bb, ch_params);

            [rx_pb_clean, ~] = upconvert(rx_bb_clean, fs, fc);
            sig_pwr = mean(rx_pb_clean.^2);

            for si = 1:n_snr
                snr_db = snr_list(si);
                noise_var = sig_pwr * 10^(-snr_db/10);
                rng(uint32(300 + pi*10000 + fi*1000 + si*100 + s), 'twister');
                rx_pb = rx_pb_clean + sqrt(noise_var) * randn(size(rx_pb_clean));

                lpf_bw = sym_rate * (1 + sys.scfde.rolloff) / 2;
                [bb_rx, ~] = downconvert(rx_pb, fs, fc, lpf_bw);

                try
                    [bits_decoded, ~] = modem_decode_scfde(bb_rx, sys, meta);
                    ber = mean(bits_decoded(1:N_info_actual) ~= info_bits);
                    ber_matrix(pi, fi, si, seed) = ber;
                catch ME
                    fprintf('  [ERR] pi=%d fi=%d si=%d seed=%d: %s\n', pi, fi, si, seed, ME.message);
                    ber_matrix(pi, fi, si, seed) = NaN;
                end

                fprintf('  pilot=%-3d seed=%d SNR=%2ddB  BER=%6.2f%%\n', ...
                        pilot_per_blk, s, snr_db, ber_matrix(pi,fi,si,seed)*100);
            end
        end
    end
end

%% --- 4. 汇总 ---
fprintf('\n\n========================================\n');
fprintf('  汇总：BER mean across %d seeds\n', n_seed);
fprintf('========================================\n');

for pi = 1:n_pilot
    pilot_per_blk = pilot_list(pi);
    throughput = 100 * (sys.scfde.blk_fft - pilot_per_blk) / sys.scfde.blk_fft;
    fprintf('\n--- pilot_per_blk=%d (吞吐 %.1f%%) ---\n', pilot_per_blk, throughput);
    fprintf('%-10s |', '');
    for si = 1:n_snr, fprintf(' %6ddB', snr_list(si)); end
    fprintf('\n%s\n', repmat('-', 1, 10 + 8*n_snr));
    for fi = 1:n_fad
        fprintf('%-10s |', fading_cfgs{fi, 1});
        for si = 1:n_snr
            ber_mean = mean(ber_matrix(pi, fi, si, :), 'omitnan') * 100;
            fprintf(' %6.2f%%', ber_mean);
        end
        fprintf('\n');
    end
end

%% --- 5. pilot_per_blk vs BER 趋势 ---
fprintf('\n\n========================================\n');
fprintf('  pilot_per_blk vs BER 趋势（mean SNR={5,10,15,20} × 3 seed）\n');
fprintf('========================================\n');
fprintf('%-8s |', '');
for pi = 1:n_pilot, fprintf(' pilot=%-3d |', pilot_list(pi)); end
fprintf('\n');
for fi = 1:n_fad
    fprintf('%-8s |', fading_cfgs{fi, 1});
    for pi = 1:n_pilot
        ber_mean = mean(ber_matrix(pi, fi, :, :), 'all', 'omitnan') * 100;
        fprintf(' %8.2f%%  |', ber_mean);
    end
    fprintf('\n');
end

%% --- 6. 接受准则评估 ---
fprintf('\n\n========================================\n');
fprintf('  Phase 5 接受准则评估（spec L88）\n');
fprintf('========================================\n');

% V5a: static 任意 pilot 不退化
v5a_pass = true;
for pi = 1:n_pilot
    if mean(ber_matrix(pi, 1, 3:4, :), 'all', 'omitnan') > 0.05
        v5a_pass = false; break;
    end
end
fprintf('V5a static 任意 pilot 不退化（SNR={15,20} mean BER < 5%%）：%s\n', tern(v5a_pass));

% V5b: fd=1Hz pilot_per_blk={32,64,96,128} 至少一个 BER < 5%
v5b_best_pilot = -1;
v5b_best_ber = 100;
for pi = 1:n_pilot
    p = pilot_list(pi);
    if p == 0, continue; end  % skip baseline
    ber_mean = mean(ber_matrix(pi, 2, :, :), 'all', 'omitnan') * 100;
    if ber_mean < v5b_best_ber
        v5b_best_ber = ber_mean;
        v5b_best_pilot = p;
    end
end
v5b_pass = v5b_best_ber < 5;
fprintf('V5b fd=1Hz best pilot=%d, BER mean=%6.2f%%（接受准则 < 5%%）：%s\n', ...
        v5b_best_pilot, v5b_best_ber, tern(v5b_pass));

% V5c: fd=5Hz pilot_per_blk=64+ 至少一个 BER < 10%
v5c_best_pilot = -1;
v5c_best_ber = 100;
for pi = 1:n_pilot
    p = pilot_list(pi);
    if p < 64, continue; end
    ber_mean = mean(ber_matrix(pi, 3, :, :), 'all', 'omitnan') * 100;
    if ber_mean < v5c_best_ber
        v5c_best_ber = ber_mean;
        v5c_best_pilot = p;
    end
end
v5c_pass = v5c_best_ber < 10;
fprintf('V5c fd=5Hz best pilot=%d, BER mean=%6.2f%%（接受准则 < 10%%）：%s\n', ...
        v5c_best_pilot, v5c_best_ber, tern(v5c_pass));

fprintf('\n日志: %s\n', diary_file);
fprintf('========================================\n');

end


function s = tern(ok)
if ok, s = '✅ PASS'; else, s = '❌ FAIL'; end
end
