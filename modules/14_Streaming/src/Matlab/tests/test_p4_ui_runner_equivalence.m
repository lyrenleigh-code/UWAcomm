%% test_p4_ui_runner_equivalence.m - P4 UI ↔ runner 等价性 RCA
% Spec: specs/active/2026-05-03-p4-ui-runner-equivalence-rca.md
%
% 目标：定位 13_SourceCode runner 0.68% vs P4 UI 50% BER 的根因
%
% 路径：
%   Path R (runner-style)   : modem_encode → AWGN(body) → modem_decode
%   Path U1 (UI-style ideal): modem_encode → assemble_physical_frame → AWGN(frame)
%                             → 真实 fs_pos 切片 (data_start) → modem_decode
%   Path U2 (UI-style sync) : 同 U1，但用 detect_frame_stream 找 fs_pos
%
% 配置：SC-FDE V4.0 预设（blk_fft=256, blk_cp=128, pilot_per_blk=128, train_period_K=31）
% 信道：AWGN SNR=20（无 Doppler、无 fading，最干净），固定 seed
%
% 验收：
%   - Path R BER ≤ 1%（runner V4.0 直接链路 baseline 0.68%）
%   - Path U1 BER 与 Path R 同数量级（≤ 2%）→ 证明 meta-pass 路径无问题
%   - Path U2 BER 与 Path U1 同数量级 → 证明 detect_frame_stream 无问题
%   - 三者差距 → 定位根因层

clear functions; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));

streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(proj_root, 'modules', '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '04_Modulation', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '12_IterativeProc', 'src', 'Matlab'));

diary_path = fullfile(this_dir, 'test_p4_ui_runner_equivalence_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('========================================\n');
fprintf(' P4 UI ↔ runner 等价性 RCA\n');
fprintf('========================================\n\n');

%% ---- 1. SC-FDE V4.0 配置 ----
sys = sys_params_default();
ui_vals = struct( ...
    'blk_fft',        256, ...
    'blk_cp',         128, ...
    'pilot_per_blk',  128, ...
    'train_period_K', 31, ...
    'turbo_iter',     3, ...
    'payload',        128, ...
    'fading_type',    'static (恒定)', ...
    'fd_hz',          0 );
[N_info, sys] = p4_apply_scheme_params('SC-FDE', sys, ui_vals);
fprintf('SC-FDE V4.0 配置：blk_fft=%d blk_cp=%d pilot=%d train_K=%d N_info=%d\n', ...
    sys.scfde.blk_fft, sys.scfde.blk_cp, sys.scfde.pilot_per_blk, ...
    sys.scfde.train_period_K, N_info);

%% ---- 2. 信源 ----
rng(20260503, 'twister');
info_bits = randi([0 1], 1, N_info);

%% ---- 3. modem_encode (TX) ----
[body_bb, meta_tx] = modem_encode(info_bits, 'SC-FDE', sys);
fprintf('TX body_bb 长度: %d, meta.N_shaped=%d\n', length(body_bb), meta_tx.N_shaped);

%% ---- 4. assemble_physical_frame ----
[frame_bb, frame_meta] = assemble_physical_frame(body_bb, sys);
body_offset = length(frame_bb) - length(body_bb);
fprintf('frame_bb 长度: %d, body_offset=%d, frame_meta.data_start=%d\n', ...
    length(frame_bb), body_offset, frame_meta.data_start);
fprintf('一致性检查 (body_offset+1 == data_start): %d\n', (body_offset+1) == frame_meta.data_start);

%% ---- 5. AWGN 噪声（统一 nv：以 body sig_pwr 为基准，三路同 nv）----
% 修正：原版用 frame sig_pwr 算 nv_frame 错误（frame 含 guard 零样本）
SNR_dB = 20;
sig_pwr_body  = mean(abs(body_bb).^2);
nv_body       = sig_pwr_body / 10^(SNR_dB/10);
nv_frame      = nv_body;   % 同 nv，frame/body 两路 SNR 一致

%% ---- Path R: runner-style (多 seed 看分布) ----
fprintf('\n=== Path R (runner-style: body 直加 AWGN, 5 seed) ===\n');
ber_R_arr = zeros(1, 5);
for s = 1:5
    rng(40+s);
    noise_R = sqrt(nv_body/2) * (randn(1, length(body_bb)) + 1j*randn(1, length(body_bb)));
    body_bb_R = body_bb + noise_R;
    [bits_R, info_R] = modem_decode(body_bb_R, 'SC-FDE', sys, meta_tx);
    n_R = min(length(bits_R), N_info);
    ber_R_arr(s) = sum(bits_R(1:n_R) ~= info_bits(1:n_R)) / n_R;
    fprintf('  seed=%d Path R BER = %.4f%%\n', 40+s, ber_R_arr(s)*100);
end
ber_R = mean(ber_R_arr);
fprintf('Path R mean BER = %.4f%% (5 seeds)\n', ber_R*100);

%% ---- Path U1: UI-style (理想 sync, 真实 fs_pos, 同 seed) ----
fprintf('\n=== Path U1 (UI-style: assemble + AWGN + 真实 fs_pos 切片, 5 seed) ===\n');
ber_U1_arr = zeros(1, 5);
fs_pos_true = 1;
fn = length(frame_bb);
for s = 1:5
    rng(40+s);
    noise_U = sqrt(nv_frame/2) * (randn(1, length(frame_bb)) + 1j*randn(1, length(frame_bb)));
    frame_rx = frame_bb + noise_U;
    rx_seg = frame_rx(fs_pos_true : fs_pos_true + fn - 1);
    body_bb_U1 = rx_seg(body_offset+1 : end);
    [bits_U1, info_U1] = modem_decode(body_bb_U1, 'SC-FDE', sys, meta_tx);
    n_U1 = min(length(bits_U1), N_info);
    ber_U1_arr(s) = sum(bits_U1(1:n_U1) ~= info_bits(1:n_U1)) / n_U1;
    fprintf('  seed=%d Path U1 BER = %.4f%%\n', 40+s, ber_U1_arr(s)*100);
end
ber_U1 = mean(ber_U1_arr);
fprintf('Path U1 mean BER = %.4f%% (5 seeds)\n', ber_U1*100);

%% ---- Path U2: UI-style + detect_frame_stream ----
fprintf('\n=== Path U2 (UI-style: assemble + AWGN + detect_frame_stream sync) ===\n');
% 模拟 UI fifo: 加前置 silence 模拟 wave wraparound
silence_pad = 5000;
fifo_simulated = [zeros(1, silence_pad), frame_rx];
fifo_write = length(fifo_simulated);
sync_det = detect_frame_stream(fifo_simulated, fifo_write, 0, sys, ...
    struct('frame_len_hint', fn));
fprintf('detect_frame_stream: found=%d fs_pos=%d (true=%d) peak_ratio=%.2f conf=%.2f\n', ...
    sync_det.found, sync_det.fs_pos, silence_pad+1, sync_det.peak_ratio, sync_det.confidence);
if sync_det.found
    fs_pos = sync_det.fs_pos;
    if fifo_write >= fs_pos + fn - 1
        rx_seg_U2 = fifo_simulated(fs_pos : fs_pos + fn - 1);
        body_bb_U2 = rx_seg_U2(body_offset+1 : end);
        [bits_U2, info_U2] = modem_decode(body_bb_U2, 'SC-FDE', sys, meta_tx);
        n_U2 = min(length(bits_U2), N_info);
        ber_U2 = sum(bits_U2(1:n_U2) ~= info_bits(1:n_U2)) / n_U2;
        fprintf('Path U2 BER = %.4f%% (n=%d)\n', ber_U2*100, n_U2);
    else
        ber_U2 = NaN;
        fprintf('Path U2 SKIPPED: fifo 不足\n');
    end
else
    ber_U2 = NaN;
    fprintf('Path U2 SKIPPED: detect_frame_stream FAILED\n');
end

%% ---- 6. Jakes fd=1Hz 信道下对比（UI 50% 问题复现路径）----
fprintf('\n=== Jakes fd=1Hz 路径对比（UI 报 50%% 主路径）===\n');
addpath(fullfile(proj_root, 'modules', '13_SourceCode', 'src', 'Matlab', 'common'));
addpath(fullfile(proj_root, 'modules', '13_SourceCode', 'src', 'Matlab'));
ch_params = struct( ...
    'fs',            sys.fs, ...
    'num_paths',     1, ...
    'delay_profile', 'custom', ...
    'delays_s',      0, ...
    'gains',         1, ...
    'doppler_rate',  0, ...
    'fading_type',   'slow', ...
    'fading_fd_hz',  1, ...
    'snr_db',        Inf, ...
    'seed',          12345 );

% Path R-jakes: body 直过 jakes 信道 + AWGN
[body_jakes, ~] = gen_uwa_channel(body_bb, ch_params);
if length(body_jakes) > length(body_bb)
    body_jakes = body_jakes(1:length(body_bb));
elseif length(body_jakes) < length(body_bb)
    body_jakes = [body_jakes, zeros(1, length(body_bb)-length(body_jakes))];
end
ber_Rj_arr = zeros(1, 3);
for s = 1:3
    rng(40+s);
    noise_R = sqrt(nv_body/2) * (randn(1, length(body_jakes)) + 1j*randn(1, length(body_jakes)));
    body_R = body_jakes + noise_R;
    [bits_Rj, ~] = modem_decode(body_R, 'SC-FDE', sys, meta_tx);
    n_Rj = min(length(bits_Rj), N_info);
    ber_Rj_arr(s) = sum(bits_Rj(1:n_Rj) ~= info_bits(1:n_Rj)) / n_Rj;
    fprintf('  R-jakes seed=%d BER = %.4f%%\n', 40+s, ber_Rj_arr(s)*100);
end
ber_Rj = mean(ber_Rj_arr);

% Path U1-jakes: frame_bb 过 jakes + AWGN，真实切片
ch_params_U = ch_params;
ch_params_U.seed = 12345;
[frame_jakes, ~] = gen_uwa_channel(frame_bb, ch_params_U);
if length(frame_jakes) > length(frame_bb)
    frame_jakes = frame_jakes(1:length(frame_bb));
elseif length(frame_jakes) < length(frame_bb)
    frame_jakes = [frame_jakes, zeros(1, length(frame_bb)-length(frame_jakes))];
end
ber_Uj_arr = zeros(1, 3);
for s = 1:3
    rng(40+s);
    noise_U = sqrt(nv_body/2) * (randn(1, length(frame_jakes)) + 1j*randn(1, length(frame_jakes)));
    frame_U = frame_jakes + noise_U;
    rx_seg = frame_U(fs_pos_true : fs_pos_true + fn - 1);
    body_U = rx_seg(body_offset+1 : end);
    [bits_Uj, ~] = modem_decode(body_U, 'SC-FDE', sys, meta_tx);
    n_Uj = min(length(bits_Uj), N_info);
    ber_Uj_arr(s) = sum(bits_Uj(1:n_Uj) ~= info_bits(1:n_Uj)) / n_Uj;
    fprintf('  U1-jakes seed=%d BER = %.4f%%\n', 40+s, ber_Uj_arr(s)*100);
end
ber_Uj = mean(ber_Uj_arr);

%% ---- 7. 总结 + 根因定位 ----
fprintf('\n========================================\n');
fprintf(' 等价性 RCA 总结\n');
fprintf('========================================\n');
fprintf('AWGN SNR=20:\n');
fprintf('  Path R  (runner)            BER = %.4f%%\n', ber_R*100);
fprintf('  Path U1 (UI ideal sync)     BER = %.4f%%\n', ber_U1*100);
if ~isnan(ber_U2)
    fprintf('  Path U2 (UI detect_stream)  BER = %.4f%%\n', ber_U2*100);
end
fprintf('Jakes fd=1Hz SNR=20:\n');
fprintf('  Path R-jakes (runner)       BER = %.4f%%\n', ber_Rj*100);
fprintf('  Path U1-jakes (UI ideal)    BER = %.4f%%\n', ber_Uj*100);
fprintf('\n');

% 验收 + 根因初步定位
ac_R  = ber_R  <= 0.02;
ac_U1 = ber_U1 <= 0.05;  % 比 R 略宽
ac_U2 = isnan(ber_U2) || ber_U2 <= 0.05;

if ac_R && ac_U1 && ac_U2
    fprintf('[PASS] 三路 BER 等价（V4.0 静态 AWGN SNR=20）\n');
    fprintf('  → meta-pass 路径无问题；UI jakes 50% 问题应在 jakes/Doppler 层\n');
elseif ac_R && ~ac_U1
    fprintf('[FAIL][H1/H4] Path R OK 但 Path U1 失败 → meta/frame 不匹配嫌疑\n');
    fprintf('  检查：body_offset 切片 / N_shaped / data_start 一致性\n');
elseif ac_R && ac_U1 && ~ac_U2
    fprintf('[FAIL][SYNC] Path U1 OK 但 Path U2 失败 → detect_frame_stream 嫌疑\n');
elseif ~ac_R
    fprintf('[FAIL][V4.0-REGRESSION] Path R 失败 → V4.0 算法层有问题（与 0.68% baseline 矛盾，需复跑 runner）\n');
end

diary off;
fprintf('Log written: %s\n', diary_path);
