%% diag_p4_ui_jakes_passband_mimic.m
% 用途：在 headless 下复刻 P4 UI 完整 passband + jakes 路径，验证 alpha gate fix
%       是否在 UI 真实链路下生效。绕开 GUI/timer/FIFO ring，直跑 try_decode_frame 主链。
%
% 与 test_p4_ui_jakes_alpha_gate_e2e.m 区别：
%   - e2e 在基带做 jakes + AWGN，强制用 ground truth fs_pos，覆盖率有限
%   - 本 diag 走 UI 默认路径：bypass_rf=false，passband 上行 + 真 detect_frame_stream + 真 downconvert
%   - 输出每一步与 UI append_log 完全一致的 [TAG] 行，供 UI 实测 log 直接对照
%
% Spec: specs/active/2026-05-03-p4-ui-runner-equivalence-rca.md（衍生发现）

clear functions; clear all; clc;

this_dir = fileparts(mfilename('fullpath'));
proj_root = fileparts(fileparts(fileparts(fileparts(fileparts(this_dir)))));

streaming_root = fullfile(proj_root, 'modules', '14_Streaming', 'src', 'Matlab');
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '04_Modulation', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '05_SpreadSpectrum', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '06_MultiCarrier', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '07_ChannelEstEq', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '08_Sync', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '09_Waveform', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '13_SourceCode', 'src', 'Matlab', 'common'));

diary_path = fullfile(this_dir, 'diag_p4_ui_jakes_passband_mimic_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('============================================================\n');
fprintf(' P4 UI jakes+passband headless mimic\n');
fprintf(' (用 UI 同口径 [TAG] 行输出，供 UI 实测 log 对照)\n');
fprintf('============================================================\n\n');

%% ---- 1. V4.0 预设（同 UI on_v40_preset）----
sys = sys_params_default();
ui_vals = struct( ...
    'blk_fft',        256, ...
    'blk_cp',         128, ...
    'pilot_per_blk',  128, ...
    'train_period_K', 31, ...
    'turbo_iter',     3, ...
    'payload',        128, ...
    'fading_type',    'slow (Jakes 慢衰落)', ...
    'fd_hz',          1 );
[N_info, sys] = p4_apply_scheme_params('SC-FDE', sys, ui_vals);
fprintf('[预设] V4.0 Jakes：blk_fft=256, blk_cp=128, pilot_per_blk=128, train_period_K=31\n');
fprintf('[UI] scheme -> SC-FDE (max %d bytes)\n', floor(N_info/8));

%% ---- 2. TX：modem_encode + assemble ----
rng(20260504, 'twister');
info_bits = randi([0 1], 1, N_info);
[body_bb, meta_tx] = modem_encode(info_bits, 'SC-FDE', sys);
[frame_bb, ~] = assemble_physical_frame(body_bb, sys);
body_offset = length(frame_bb) - length(body_bb);
L_bb = length(frame_bb);
fprintf('[TX-INFO] body_bb=%d, frame_bb=%d, body_offset=%d, N_info=%d\n', ...
    length(body_bb), L_bb, body_offset, N_info);

%% ---- 3. Channel：jakes fd=1Hz（同 UI on_transmit jakes 分支）----
% 模拟 UI 的 [TX] log：channel_label = 'custom6 | Jakes slow fd=1Hz | α=0.00e+00'
sch = 'SC-FDE';
[h_tap, paths, ch_label] = p4_channel_tap(sch, sys, 'V40 (Jakes 协议层)');
dop_hz  = 0;                  % UI doppler_edit 默认 0（无 bulk Doppler，仅 jakes 衰落）
alpha_b = dop_hz / sys.fc;
fading_type_ch = 'slow';
fd_jakes = 1;
ch_params = struct( ...
    'fs',            sys.fs, ...
    'num_paths',     length(paths.delays), ...
    'delay_profile', 'custom', ...
    'delays_s',      paths.delays, ...
    'gains',         paths.gains, ...
    'doppler_rate',  alpha_b, ...
    'fading_type',   fading_type_ch, ...
    'fading_fd_hz',  fd_jakes, ...
    'snr_db',        Inf, ...
    'seed',          12345 );
[frame_ch_raw, ~] = gen_uwa_channel(frame_bb, ch_params);
if length(frame_ch_raw) >= L_bb
    frame_ch = frame_ch_raw(1:L_bb);
else
    frame_ch = [frame_ch_raw, zeros(1, L_bb - length(frame_ch_raw))];
end
ch_label_full = sprintf('%s | Jakes %s fd=%.1fHz | α=%.2e', ch_label, fading_type_ch, fd_jakes, alpha_b);

%% ---- 4. Upconvert + AWGN（同 UI bypass_rf=false 路径）----
[tx_pb, ~] = upconvert(frame_ch, sys.fs, sys.fc);
tx_pb = real(tx_pb);
sig_pwr_pb = mean(tx_pb.^2);

snr_db = 20;
nv_pb = sig_pwr_pb * 10^(-snr_db/10);
bw_tx = p4_downconv_bw(sch, sys);
nv_meta = 8 * nv_pb * bw_tx / sys.fs;     % 同 UI L1102

% 模拟 FIFO：[silence_noise, tx_pb+noise_overlay, silence_noise]
% UI on_tick 在 chunk 上叠加 tx_signal；这里直接构造完整帧+前后噪声底
silence_pad = round(0.5 * sys.fs);
fn = length(tx_pb);
fifo = [sqrt(nv_pb)*randn(1, silence_pad), ...
        tx_pb + sqrt(nv_pb)*randn(1, fn), ...
        sqrt(nv_pb)*randn(1, silence_pad)];
fifo_write = length(fifo);
frame_start_write = silence_pad + 1;     % UI tx_meta_pending.frame_start_write

fprintf('[TX] %s %s frame=%d(pre=%d+body=%d) pb=%d, nv=%.3e (SNR=%gdB)\n', ...
    sch, ch_label_full, length(frame_ch), body_offset, length(body_bb), fn, nv_pb, snr_db);

%% ---- 5. RX：detect_frame_stream（同 UI try_decode_frame L1320）----
% 用 UI tx_meta_pending.frame_pb_samples 作 hint
sync_det = detect_frame_stream(fifo, fifo_write, 0, sys, ...
    struct('frame_len_hint', fn));

if ~sync_det.found
    fprintf('[DETECT-FAIL] detect_frame_stream returned found=0\n');
    fprintf('  → UI try_decode_frame L1323 提前 return → 无 [SYNC]/[α-GATE] 任何 log\n');
    fprintf('  → BER 显示残留上次值\n');
    diary off;
    return;
end

fs_pos    = sync_det.fs_pos;
sync_diff = fs_pos - frame_start_write;
alpha_est_rx = 0;
if isfield(sync_det, 'alpha_est'), alpha_est_rx = sync_det.alpha_est; end
alpha_conf = 0;
if isfield(sync_det, 'alpha_confidence'), alpha_conf = sync_det.alpha_confidence; end

fprintf('[SYNC] fs=%d gt=%d diff=%+d peak=%.1f ratio=%.1f conf=%.2f α=%+.3e conf_α=%.2f\n', ...
    fs_pos, frame_start_write, sync_diff, sync_det.peak_val, ...
    sync_det.peak_ratio, sync_det.confidence, alpha_est_rx, alpha_conf);

%% ---- 6. α gate（同 UI try_decode_frame L1363）----
rx_seg = fifo(fs_pos : fs_pos + fn - 1);
rx_seg_raw = rx_seg;
alpha_gate = streaming_alpha_gate(alpha_est_rx, alpha_conf, sys);

if alpha_gate.accepted
    alpha_use = alpha_gate.alpha;
    rx_seg_comp = comp_resample_spline(rx_seg, alpha_use, sys.fs, 'fast');
    if length(rx_seg_comp) >= fn
        rx_seg = rx_seg_comp(1:fn);
    else
        rx_seg = [rx_seg_comp, zeros(1, fn-length(rx_seg_comp))];
    end
    fprintf('[α-COMP] α=%+.3e (gate=%s) → 反补偿\n', alpha_use, alpha_gate.reason);
else
    fprintf('[α-GATE] α=%+.3e conf=%.2f 拒绝（%s），跳过反补偿\n', ...
        alpha_est_rx, alpha_conf, alpha_gate.reason);
end

%% ---- 7. Downconvert + body 切片（同 UI L1388）----
bw_use = p4_downconv_bw(sch, sys);
[full_bb_rx, ~] = downconvert(rx_seg, sys.fs, sys.fc, bw_use);
body_bb_rx = full_bb_rx(body_offset+1 : min(body_offset+meta_tx.N_shaped, length(full_bb_rx)));

%% ---- 8. modem_decode ----
meta = meta_tx;
meta.scheme = sch;
meta.body_offset = body_offset;
meta.frame_pb_samples = fn;
meta.frame_start_write = frame_start_write;
meta.noise_var = nv_meta;
try
    [bits_out, info] = modem_decode(body_bb_rx, sch, sys, meta);
catch ME
    fprintf('[DEC-ERR] %s\n', ME.message);
    if ~isempty(ME.stack)
        for si = 1:min(3, length(ME.stack))
            fprintf('  @ %s L%d\n', ME.stack(si).name, ME.stack(si).line);
        end
    end
    diary off;
    return;
end

n = min(length(bits_out), length(info_bits));
n_err = sum(bits_out(1:n) ~= info_bits(1:n));
ber = n_err / n;

fprintf('[DEC #1] %s BER=%.3f%% (%d/%d) iter=%d\n', sch, ber*100, n_err, n, info.turbo_iter);

%% ---- 9. 关键诊断信息（供与 UI 实测对照）----
fprintf('\n============================================================\n');
fprintf(' 关键 log 期望值（UI 实测应有这些 [TAG] 行）\n');
fprintf('============================================================\n');
fprintf('  [预设] V4.0 Jakes...                    ← 用户点 V4.0 按钮\n');
fprintf('  [TX] SC-FDE ... | Jakes slow fd=1Hz | α=0.00e+00 frame=%d ...\n', length(frame_ch));
fprintf('  [SYNC] fs=... gt=... diff=...           ← detect 通过\n');
if alpha_gate.accepted
    fprintf('  [α-COMP] α=%+.3e (gate=accepted) ...    ← gate 通过（jakes 下不应该走这条）\n', alpha_gate.alpha);
else
    fprintf('  [α-GATE] α=%+.3e conf=%.2f 拒绝（%s）   ← gate 拒绝假 α\n', alpha_est_rx, alpha_conf, alpha_gate.reason);
end
fprintf('  [DEC #N] SC-FDE BER=%.3f%% iter=%d\n', ber*100, info.turbo_iter);

fprintf('\n如果 UI Log tab 中找不到 [SYNC] 行 → detect 没通过（fifo 还没集齐 / silence pad 不够 / chunk 切到帧中间）\n');
fprintf('如果有 [SYNC] 但无 [α-GATE]/[α-COMP] → UI 跑的是缓存版（nested function closure 没重载）\n');
fprintf('如果有 [α-GATE] 拒绝 + BER 仍 50%% → detect fs_pos 错位（spec 衍生发现 7327 sample 偏移）\n');

fprintf('\n本 diag BER = %.3f%%\n', ber*100);

diary off;
fprintf('Log: %s\n', diary_path);
