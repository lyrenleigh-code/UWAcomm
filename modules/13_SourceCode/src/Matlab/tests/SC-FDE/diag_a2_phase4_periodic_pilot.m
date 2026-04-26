function diag_a2_phase4_periodic_pilot()
% DIAG_A2_PHASE4_PERIODIC_PILOT
%
% Phase 4 V4b/V4c/V4d 验证：14_Streaming production decoder × jakes × 多训练块 K
%
% 路线 1 后续协议层方向落地（spec specs/active/2026-04-26-scfde-time-varying-pilot-arch.md）。
% 在 A1 脚本基础上加 K 参数循环：
%   K=N_blocks-1 → 单训练块（与 A1 一致，对照 baseline）
%   K=4/8/16    → 多训练块插入（覆盖 Jakes 周期）
%
% 期望（spec L88 接受准则）：
%   V4b fd=1Hz K=4 BER < 5% 恢复 Phase 1 水平
%   V4c fd=5Hz K=4 BER < 10%
%   V4d K vs BER 曲线显示 trade-off（K↑ → 性能↓ + 吞吐↑）
%
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm-claude\modules\13_SourceCode\src\Matlab\tests\SC-FDE');
%   clear functions; clear all;
%   diag_a2_phase4_periodic_pilot

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

diary_file = fullfile(this_dir, 'diag_a2_phase4_periodic_pilot_results.txt');
if exist(diary_file, 'file'), delete(diary_file); end
diary(diary_file);
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('========================================\n');
fprintf('  A2 Phase 4 验证：多训练块协议 K vs BER\n');
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
fprintf('SC-FDE: blk_fft=%d blk_cp=%d N_blocks=%d turbo_iter=%d\n', ...
        sys.scfde.blk_fft, sys.scfde.blk_cp, sys.scfde.N_blocks, sys.scfde.turbo_iter);
fprintf('多径: sym_delays=[%s]\n', strjoin(arrayfun(@(x)sprintf('%d',x),sym_delays,'UniformOutput',false), ' '));

%% --- 2. 测试矩阵 ---
% K 候选：15(N-1 baseline) / 8 / 4 / 2
K_list = [sys.scfde.N_blocks - 1, 8, 4, 2];

fading_cfgs = {
    'static', 'static', 0, 0;
    'fd=1Hz', 'slow',   1, 0;
    'fd=5Hz', 'slow',   5, 0;
};
snr_list = [5, 10, 15, 20];
seed_list = [1, 2, 3];

n_K     = length(K_list);
n_fad   = size(fading_cfgs, 1);
n_snr   = length(snr_list);
n_seed  = length(seed_list);

ber_matrix = zeros(n_K, n_fad, n_snr, n_seed);
n_train_record = zeros(n_K, 1);

%% --- 3. 主循环 ---
for ki = 1:n_K
    K = K_list(ki);
    sys.scfde.train_period_K = K;

    % 计算实际 N_train（与 modem_encode_scfde V3.0 一致）
    if K >= sys.scfde.N_blocks - 1
        N_train = 1;
    else
        N_train = floor(sys.scfde.N_blocks / (K + 1)) + 1;
    end
    n_train_record(ki) = N_train;

    fprintf('\n========================================\n');
    fprintf('  K=%d (N_train=%d, 吞吐 %.1f%%)\n', K, N_train, ...
            100 * (sys.scfde.N_blocks - N_train) / sys.scfde.N_blocks);
    fprintf('========================================\n');

    for fi = 1:n_fad
        fname = fading_cfgs{fi, 1};
        ftype = fading_cfgs{fi, 2};
        fd_hz = fading_cfgs{fi, 3};
        dop_rate = fading_cfgs{fi, 4};

        fprintf('\n--- fading=%s (fd=%g Hz) ---\n', fname, fd_hz);

        for seed = 1:n_seed
            s = seed_list(seed);
            rng(uint32(100 + ki*10000 + fi*1000 + s*10), 'twister');

            % bits 长度从 modem_encode_scfde 派生（依赖 K）
            % 重新计算 N_data_blocks/N_info（与 modem_encode_scfde V3.0 一致）
            if K >= sys.scfde.N_blocks - 1
                N_train_actual = 1;
            else
                N_train_actual = floor(sys.scfde.N_blocks/(K+1)) + 1;
            end
            train_indices_tmp = round(linspace(1, sys.scfde.N_blocks, N_train_actual));
            train_indices_tmp = unique(train_indices_tmp);
            N_train_actual = length(train_indices_tmp);
            N_data_actual = sys.scfde.N_blocks - N_train_actual;
            M_total_actual = 2 * sys.scfde.blk_fft * N_data_actual;
            N_info_actual = M_total_actual / n_code - mem;

            info_bits = randi([0 1], 1, N_info_actual);

            [body_bb, meta] = modem_encode_scfde(info_bits, sys);

            ch_params = struct('fs', fs, 'delay_profile', 'custom', ...
                'delays_s', sym_delays / sym_rate, 'gains', gains_raw, ...
                'num_paths', length(sym_delays), 'doppler_rate', dop_rate, ...
                'fading_type', ftype, 'fading_fd_hz', fd_hz, ...
                'snr_db', Inf, 'seed', 200 + ki*1000 + fi*100 + s);
            [rx_bb_clean, ~] = gen_uwa_channel(body_bb, ch_params);

            [rx_pb_clean, ~] = upconvert(rx_bb_clean, fs, fc);
            sig_pwr = mean(rx_pb_clean.^2);

            for si = 1:n_snr
                snr_db = snr_list(si);
                noise_var = sig_pwr * 10^(-snr_db/10);
                rng(uint32(300 + ki*10000 + fi*1000 + si*100 + s), 'twister');
                rx_pb = rx_pb_clean + sqrt(noise_var) * randn(size(rx_pb_clean));

                lpf_bw = sym_rate * (1 + sys.scfde.rolloff) / 2;
                [bb_rx, ~] = downconvert(rx_pb, fs, fc, lpf_bw);

                try
                    [bits_decoded, ~] = modem_decode_scfde(bb_rx, sys, meta);
                    ber = mean(bits_decoded(1:N_info_actual) ~= info_bits);
                    ber_matrix(ki, fi, si, seed) = ber;
                catch ME
                    fprintf('  [ERR] K=%d fi=%d si=%d seed=%d: %s\n', K, fi, si, seed, ME.message);
                    ber_matrix(ki, fi, si, seed) = NaN;
                end

                fprintf('  K=%-2d seed=%d SNR=%2ddB  BER=%6.2f%%\n', ...
                        K, s, snr_db, ber_matrix(ki,fi,si,seed)*100);
            end
        end
    end
end

%% --- 4. 汇总（K × fading × SNR） ---
fprintf('\n\n========================================\n');
fprintf('  汇总：BER mean across %d seeds\n', n_seed);
fprintf('========================================\n');

for ki = 1:n_K
    K = K_list(ki);
    N_train = n_train_record(ki);
    fprintf('\n--- K=%d (N_train=%d, 吞吐 %.1f%%) ---\n', K, N_train, ...
            100 * (sys.scfde.N_blocks - N_train) / sys.scfde.N_blocks);
    fprintf('%-10s |', '');
    for si = 1:n_snr, fprintf(' %6ddB', snr_list(si)); end
    fprintf('\n%s\n', repmat('-', 1, 10 + 8*n_snr));
    for fi = 1:n_fad
        fprintf('%-10s |', fading_cfgs{fi, 1});
        for si = 1:n_snr
            ber_mean = mean(ber_matrix(ki, fi, si, :), 'omitnan') * 100;
            fprintf(' %6.2f%%', ber_mean);
        end
        fprintf('\n');
    end
end

%% --- 5. K vs BER 趋势（fd=1Hz/fd=5Hz）---
fprintf('\n\n========================================\n');
fprintf('  K vs BER 趋势（mean SNR={5,10,15,20} × 3 seed）\n');
fprintf('========================================\n');
fprintf('%-8s | %-10s | %-10s | %-10s | %-10s\n', '', 'K=15(单)', 'K=8', 'K=4', 'K=2');
for fi = 1:n_fad
    fprintf('%-8s |', fading_cfgs{fi, 1});
    for ki = 1:n_K
        ber_mean = mean(ber_matrix(ki, fi, :, :), 'all', 'omitnan') * 100;
        fprintf(' %8.2f%%  |', ber_mean);
    end
    fprintf('\n');
end

%% --- 6. 接受准则评估 ---
fprintf('\n\n========================================\n');
fprintf('  Phase 4 接受准则评估（spec L88）\n');
fprintf('========================================\n');

% V4a static 不退化（任意 K）
v4a_pass = true;
for ki = 1:n_K
    if mean(ber_matrix(ki, 1, 3:4, :), 'all', 'omitnan') > 0.05  % SNR=15/20 BER < 5%
        v4a_pass = false; break;
    end
end
fprintf('V4a static 不退化（SNR={15,20} mean BER < 5%%）：%s\n', tern(v4a_pass));

% V4b fd=1Hz K=4 BER < 5%
ki_K4 = find(K_list == 4, 1);
if ~isempty(ki_K4)
    v4b_K4_mean = mean(ber_matrix(ki_K4, 2, :, :), 'all', 'omitnan') * 100;
    v4b_pass = v4b_K4_mean < 5;
    fprintf('V4b fd=1Hz K=4 BER mean=%6.2f%%（接受准则 < 5%%）：%s\n', v4b_K4_mean, tern(v4b_pass));
end

% V4c fd=5Hz K=4 BER < 10%
if ~isempty(ki_K4)
    v4c_K4_mean = mean(ber_matrix(ki_K4, 3, :, :), 'all', 'omitnan') * 100;
    v4c_pass = v4c_K4_mean < 10;
    fprintf('V4c fd=5Hz K=4 BER mean=%6.2f%%（接受准则 < 10%%）：%s\n', v4c_K4_mean, tern(v4c_pass));
end

fprintf('\n日志: %s\n', diary_file);
fprintf('========================================\n');

end


function s = tern(ok)
if ok, s = '✅ PASS'; else, s = '❌ FAIL'; end
end
