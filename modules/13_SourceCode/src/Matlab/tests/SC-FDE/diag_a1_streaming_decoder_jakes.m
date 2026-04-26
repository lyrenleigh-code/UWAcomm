function diag_a1_streaming_decoder_jakes()
% DIAG_A1_STREAMING_DECODER_JAKES
%
% 路线 4 (A1) 验证：14_Streaming production decoder × jakes fd=1Hz
%
% 目的：判定 SC-FDE Phase 3b.2 fd=1Hz 50% 灾难是架构 trade-off 还是 13 移植 bug
%
%   A1 fd=1Hz BER ≈ 50% (与 13 Phase 3b.2 同水平) → 架构 trade-off → 走 spec 路线 1
%   A1 fd=1Hz BER  < 5%                          → 13 移植有 bug      → 写新 spec 修
%
% 设计：
%   - TX: 14_Streaming/tx/modem_encode_scfde（去 oracle protocol）
%   - Channel: gen_uwa_channel(jakes fd=1Hz) 与 13 test 同
%   - RX: 14_Streaming/rx/modem_decode_scfde（production，含 mean(var)<0.6 BEM 门控）
%   - 无 preamble（jakes α=0，无需 LFM 同步）
%   - 噪声加在通带（与 13 test 严格对齐）
%
% 用法：
%   cd('D:\Claude\TechReq\UWAcomm-claude\modules\13_SourceCode\src\Matlab\tests\SC-FDE');
%   clear functions; clear all;
%   diag_a1_streaming_decoder_jakes
%
% 输出：
%   diag_a1_streaming_decoder_jakes_results.txt（diary）
%   控制台 BER 表格 + 决策建议

clc; close all;
this_dir       = fileparts(mfilename('fullpath'));
sc_fde_dir     = this_dir;
tests_dir      = fileparts(sc_fde_dir);
sourcecode_dir = fileparts(tests_dir);
matlab_dir     = fileparts(sourcecode_dir);
mod13_root     = fileparts(matlab_dir);
modules_root   = fileparts(mod13_root);

% 加 14_Streaming + 依赖模块路径
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

diary_file = fullfile(this_dir, 'diag_a1_streaming_decoder_jakes_results.txt');
if exist(diary_file, 'file'), delete(diary_file); end
diary(diary_file);
cleanupObj = onCleanup(@() diary('off')); %#ok<NASGU>

fprintf('========================================\n');
fprintf('  A1 验证：14_Streaming production decoder × jakes fd=1Hz\n');
fprintf('  时间: %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf('========================================\n\n');

%% --- 1. 系统参数 (与 13 test_scfde_timevarying.m fd=1Hz 行对齐) ---
sys = sys_params_default();
sys.scfde.blk_fft   = 256;         % 13 test fd=1Hz: 256
sys.scfde.blk_cp    = 128;         % 13 test fd=1Hz: 128
sys.scfde.N_blocks  = 16;          % 13 test fd=1Hz: 16
sys.scfde.turbo_iter = 6;          % 与 13 test 一致

% 多径配置（与 13 test L44-46 一致）
sym_delays = sys.scfde.sym_delays;             % [0, 5, 15, 40, 60, 90]
gains_raw  = sys.scfde.gains_raw;              % 6 径
gains      = gains_raw / sqrt(sum(abs(gains_raw).^2));

fs       = sys.fs;
fc       = sys.fc;
sps      = sys.sps;
sym_rate = sys.sym_rate;
codec    = sys.codec;

n_code = 2;
mem    = codec.constraint_len - 1;
N_data_blocks = sys.scfde.N_blocks - 1;
M_per_blk     = 2 * sys.scfde.blk_fft;
M_total       = M_per_blk * N_data_blocks;
N_info        = M_total / n_code - mem;

fprintf('系统: fs=%dHz fc=%dHz sps=%d sym_rate=%d\n', fs, fc, sps, sym_rate);
fprintf('SC-FDE: blk_fft=%d blk_cp=%d N_blocks=%d turbo_iter=%d\n', ...
        sys.scfde.blk_fft, sys.scfde.blk_cp, sys.scfde.N_blocks, sys.scfde.turbo_iter);
fprintf('多径: sym_delays=[%s] (6 径)\n', strjoin(arrayfun(@(x)sprintf('%d',x),sym_delays,'UniformOutput',false), ' '));
fprintf('N_info=%d, M_total=%d (data blocks only)\n\n', N_info, M_total);

%% --- 2. 测试矩阵 ---
% fading_cfgs 列：{name, fading_type, fd_hz, dop_rate}
fading_cfgs = {
    'static', 'static', 0, 0;
    'fd=1Hz', 'slow',   1, 0;
    'fd=5Hz', 'slow',   5, 0;
};
snr_list = [5, 10, 15, 20];
seed_list = [1, 2, 3];

n_fad = size(fading_cfgs, 1);
n_snr = length(snr_list);
n_seed = length(seed_list);

ber_matrix = zeros(n_fad, n_snr, n_seed);
conv_matrix = zeros(n_fad, n_snr, n_seed);    % convergence_flag
turbo_matrix = zeros(n_fad, n_snr, n_seed);   % turbo_iter run

%% --- 3. 主循环 ---
for fi = 1:n_fad
    fname = fading_cfgs{fi, 1};
    ftype = fading_cfgs{fi, 2};
    fd_hz = fading_cfgs{fi, 3};
    dop_rate = fading_cfgs{fi, 4};

    fprintf('--- fading=%s (type=%s, fd=%g Hz) ---\n', fname, ftype, fd_hz);

    for seed = 1:n_seed
        s = seed_list(seed);
        rng(uint32(100 + fi*1000 + s*10), 'twister');
        info_bits = randi([0 1], 1, N_info);

        % TX：14_Streaming production encoder
        [body_bb, meta] = modem_encode_scfde(info_bits, sys);
        meta.train_seed = 77;   % 显式确保（modem_decode_scfde 重生成训练块）

        % Channel：与 13 test 一致（基带 jakes 多径）
        ch_params = struct('fs', fs, 'delay_profile', 'custom', ...
            'delays_s', sym_delays / sym_rate, 'gains', gains_raw, ...
            'num_paths', length(sym_delays), 'doppler_rate', dop_rate, ...
            'fading_type', ftype, 'fading_fd_hz', fd_hz, ...
            'snr_db', Inf, 'seed', 200 + fi*100 + s);
        [rx_bb_clean, ch_info] = gen_uwa_channel(body_bb, ch_params);

        % 上变频 → +噪声 → 下变频（与 13 test 严格对齐通带噪声口径）
        [rx_pb_clean, ~] = upconvert(rx_bb_clean, fs, fc);
        sig_pwr = mean(rx_pb_clean.^2);

        for si = 1:n_snr
            snr_db = snr_list(si);
            noise_var = sig_pwr * 10^(-snr_db/10);
            rng(uint32(300 + fi*1000 + si*100 + s), 'twister');
            rx_pb = rx_pb_clean + sqrt(noise_var) * randn(size(rx_pb_clean));

            % 下变频 → 基带 body
            lpf_bw = sym_rate * (1 + sys.scfde.rolloff) / 2;
            [bb_rx, ~] = downconvert(rx_pb, fs, fc, lpf_bw);

            % RX：14_Streaming production decoder
            try
                [bits_decoded, info_rx] = modem_decode_scfde(bb_rx, sys, meta);
                ber = mean(bits_decoded(1:N_info) ~= info_bits);
                ber_matrix(fi, si, seed) = ber;
                conv_matrix(fi, si, seed) = info_rx.convergence_flag;
                turbo_matrix(fi, si, seed) = info_rx.turbo_iter;
            catch ME
                fprintf('  [ERR] fi=%d si=%d seed=%d: %s\n', fi, si, seed, ME.message);
                ber_matrix(fi, si, seed) = NaN;
            end

            fprintf('  seed=%d SNR=%2ddB  BER=%6.2f%%  conv=%d  iter=%d\n', ...
                    s, snr_db, ber*100, ...
                    conv_matrix(fi, si, seed), turbo_matrix(fi, si, seed));
        end
    end
    fprintf('\n');
end

%% --- 4. 汇总表格 ---
fprintf('\n========================================\n');
fprintf('  汇总：BER (mean across %d seeds)\n', n_seed);
fprintf('========================================\n');
fprintf('%-10s |', '');
for si = 1:n_snr, fprintf(' %6ddB', snr_list(si)); end
fprintf('\n%s\n', repmat('-', 1, 10 + 8*n_snr));
for fi = 1:n_fad
    fprintf('%-10s |', fading_cfgs{fi, 1});
    for si = 1:n_snr
        ber_mean = mean(ber_matrix(fi, si, :), 'omitnan') * 100;
        fprintf(' %6.2f%%', ber_mean);
    end
    fprintf('\n');
end

fprintf('\n--- 13 Phase 3b.2 对照（spec L173-178，单 seed） ---\n');
fprintf('%-10s |   5dB   10dB   15dB   20dB\n', '');
fprintf('static     |  0.00%%  0.00%%  0.00%%  0.00%%   (V3a PASS)\n');
fprintf('fd=1Hz     | 50.23%% 50.13%% 50.03%% 50.31%%   (V3b 灾难)\n');
fprintf('fd=5Hz     | 50.73%% 49.90%% 49.22%% 51.31%%   (V3c ~50%% 物理极限)\n');

%% --- 5. 决策 ---
fprintf('\n========================================\n');
fprintf('  路线 4 (A1) 决策建议\n');
fprintf('========================================\n');
ber_fd1_mean = mean(ber_matrix(2, :, :), 'all', 'omitnan') * 100;
ber_static_mean = mean(ber_matrix(1, :, :), 'all', 'omitnan') * 100;

if ber_static_mean > 5
    fprintf('⚠ static 健全性 FAIL (mean=%5.2f%%)，A1 脚本本身有 bug，结论不可信\n', ber_static_mean);
elseif ber_fd1_mean >= 40
    fprintf('✓ A1 fd=1Hz mean=%5.2f%% ≈ 50%% (与 13 Phase 3b.2 同级)\n', ber_fd1_mean);
    fprintf('  → 架构 trade-off 确认：14_Streaming production decoder 在 jakes fd=1Hz 也无法工作\n');
    fprintf('  → 决策：走 spec 路线 1 (commit Phase 3b.2 + 重写 V3b 准则为 limitation + 推广 3b.4 + 归档)\n');
elseif ber_fd1_mean < 5
    fprintf('✗ A1 fd=1Hz mean=%5.2f%% < 5%%，14_Streaming production 工作正常\n', ber_fd1_mean);
    fprintf('  → 13 移植版本有 bug！需对比 13 Phase 3b.2 与 14 production 实现差异\n');
    fprintf('  → 决策：写新 spec，定位 13 移植 bug（重点对比 BEM 触发门控 + fallback 逻辑）\n');
else
    fprintf('? A1 fd=1Hz mean=%5.2f%% 介于 5%%~40%%，部分有效\n', ber_fd1_mean);
    fprintf('  → 部分 bug + 部分架构问题，需深入分析（提取 var_x_blks 时间序列）\n');
end

fprintf('\n日志: %s\n', diary_file);
fprintf('========================================\n');

end
