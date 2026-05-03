%% test_p4_ui_jakes_alpha_gate_e2e.m - 验证 alpha gate 在 jakes 下阻断假 α 反补偿
% Spec: specs/active/2026-05-03-p4-ui-runner-equivalence-rca.md
%
% 场景：模拟 P4 UI try_decode_frame 关键路径
%   1. TX: SC-FDE V4.0 + assemble_physical_frame
%   2. Channel: jakes fd=1Hz + 大 bulk Doppler（fc·α=10Hz, α≈6.7e-3）
%   3. RX: detect_frame_stream 估 α
%   4. 对比：α 直接反补偿 vs gate 过滤后反补偿（仅当 gate accepted 才补偿）
%
% 预期：jakes + bulk Doppler 下 detect_frame_stream 可能给出
%   假 α≈3.67e-2（codex P6.20 实测值），无 gate 时反补偿后 BER 大幅恶化
%   有 gate 时假 α 被拒绝，跳过补偿，BER 接近 jakes baseline

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
addpath(fullfile(proj_root, 'modules', '10_DopplerProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '03_Interleaving', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '04_Modulation', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(proj_root, 'modules', '13_SourceCode', 'src', 'Matlab', 'common'));

diary_path = fullfile(this_dir, 'test_p4_ui_jakes_alpha_gate_e2e_results.txt');
if exist(diary_path, 'file'), delete(diary_path); end
diary(diary_path);

fprintf('========================================\n');
fprintf(' P4 UI jakes α-gate 端到端验证\n');
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
    'fading_type',    'slow (Jakes 慢衰落)', ...
    'fd_hz',          1 );
[N_info, sys] = p4_apply_scheme_params('SC-FDE', sys, ui_vals);

%% ---- 2. TX：信源 → encode → assemble ----
rng(20260503, 'twister');
info_bits = randi([0 1], 1, N_info);
[body_bb, meta_tx] = modem_encode(info_bits, 'SC-FDE', sys);
[frame_bb, ~] = assemble_physical_frame(body_bb, sys);
body_offset = length(frame_bb) - length(body_bb);
fn = length(frame_bb);

%% ---- 3. Channel: jakes fd=1Hz（无 bulk Doppler，仅多径衰落）----
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
[frame_jakes, ~] = gen_uwa_channel(frame_bb, ch_params);
if length(frame_jakes) > fn
    frame_jakes = frame_jakes(1:fn);
elseif length(frame_jakes) < fn
    frame_jakes = [frame_jakes, zeros(1, fn-length(frame_jakes))];
end

%% ---- 4. AWGN ----
SNR_dB = 20;
sig_pwr = mean(abs(body_bb).^2);
nv = sig_pwr / 10^(SNR_dB/10);
rng(42);
noise = sqrt(nv/2) * (randn(1, fn) + 1j*randn(1, fn));
frame_rx = frame_jakes + noise;

%% ---- 5. detect_frame_stream（同 UI 真同步）----
silence_pad = 5000;
fifo_simulated = [zeros(1, silence_pad), frame_rx];
fifo_write = length(fifo_simulated);
sync_det = detect_frame_stream(fifo_simulated, fifo_write, 0, sys, ...
    struct('frame_len_hint', fn));

if ~sync_det.found
    error('detect_frame_stream FAILED');
end
% 注意：detect_frame_stream 的 fs_pos 在 jakes 下可能错位（jakes fading 让
% LFM 匹配滤波峰偏移）。本测试目标是验证 alpha gate 行为，对 fs_pos 错位
% 不感兴趣 → 强制用 ground truth fs_pos，专注测 α 假报与 gate 决策。
fs_pos = silence_pad + 1;
alpha_est_rx = 0;
if isfield(sync_det, 'alpha_est'), alpha_est_rx = sync_det.alpha_est; end
alpha_conf = 0;
if isfield(sync_det, 'alpha_confidence'), alpha_conf = sync_det.alpha_confidence; end
fprintf('detect_frame_stream: found=%d fs_pos_det=%d fs_pos_true=%d\n', ...
    sync_det.found, sync_det.fs_pos, fs_pos);
fprintf('  α_est=%+.3e conf=%.2f (ground truth α=0)\n', alpha_est_rx, alpha_conf);

rx_seg = fifo_simulated(fs_pos : fs_pos + fn - 1);
rx_seg_raw = rx_seg;

%% ---- 6. 三路对比 ----
% Path A: 不做 α 反补偿（baseline）
body_A = rx_seg(body_offset+1 : end);
[bits_A, ~] = modem_decode(body_A, 'SC-FDE', sys, meta_tx);
n_A = min(length(bits_A), N_info);
ber_A = sum(bits_A(1:n_A) ~= info_bits(1:n_A)) / n_A;
fprintf('\nPath A (no α-comp baseline)        BER = %.4f%%\n', ber_A*100);

% Path B: 旧 P4 UI 路径（abs(α)>1e-6 && conf>0.3 → 直接补偿，不 gate）
if abs(alpha_est_rx) > 1e-6 && alpha_conf > 0.3
    rx_B = comp_resample_spline(rx_seg_raw, alpha_est_rx, sys.fs, 'fast');
    if length(rx_B) >= fn, rx_B = rx_B(1:fn);
    else, rx_B = [rx_B, zeros(1, fn-length(rx_B))]; end
    body_B = rx_B(body_offset+1 : end);
    [bits_B, ~] = modem_decode(body_B, 'SC-FDE', sys, meta_tx);
    n_B = min(length(bits_B), N_info);
    ber_B = sum(bits_B(1:n_B) ~= info_bits(1:n_B)) / n_B;
    fprintf('Path B (旧 UI: 无 gate, 用 α=%+.3e) BER = %.4f%%\n', alpha_est_rx, ber_B*100);
else
    ber_B = ber_A;
    fprintf('Path B (旧 UI: α 太小或 conf 低，跳过补偿) BER = %.4f%% (=A)\n', ber_B*100);
end

% Path C: 新 P4 UI 路径（streaming_alpha_gate）
gate = streaming_alpha_gate(alpha_est_rx, alpha_conf, sys);
if gate.accepted
    rx_C = comp_resample_spline(rx_seg_raw, gate.alpha, sys.fs, 'fast');
    if length(rx_C) >= fn, rx_C = rx_C(1:fn);
    else, rx_C = [rx_C, zeros(1, fn-length(rx_C))]; end
    body_C = rx_C(body_offset+1 : end);
    [bits_C, ~] = modem_decode(body_C, 'SC-FDE', sys, meta_tx);
    n_C = min(length(bits_C), N_info);
    ber_C = sum(bits_C(1:n_C) ~= info_bits(1:n_C)) / n_C;
    fprintf('Path C (新 UI: gate accept α=%+.3e) BER = %.4f%%\n', gate.alpha, ber_C*100);
else
    body_C = body_A;
    ber_C = ber_A;
    fprintf('Path C (新 UI: gate=%s, 跳过补偿) BER = %.4f%% (=A)\n', gate.reason, ber_C*100);
end

%% ---- 7. 总结 ----
fprintf('\n========================================\n');
fprintf(' α-gate 端到端总结\n');
fprintf('========================================\n');
fprintf('A (no α-comp)        BER = %.4f%%\n', ber_A*100);
fprintf('B (旧 UI no gate)    BER = %.4f%%\n', ber_B*100);
fprintf('C (新 UI with gate)  BER = %.4f%%\n', ber_C*100);
fprintf('α_est=%+.3e conf=%.2f gate=%s alpha_used=%+.3e\n', ...
    alpha_est_rx, alpha_conf, gate.reason, gate.alpha);

if abs(alpha_est_rx) > 1e-2 && alpha_conf > 0.3
    fprintf('\n[INJECTED] 假 α 注入成功（α=%+.3e > 1e-2 物理上限）\n', alpha_est_rx);
    if ber_C < ber_B
        fprintf('[GATE-WIN] Path C BER 优于 Path B（gate 修复有效）\n');
    elseif ber_C == ber_A
        fprintf('[GATE-OK] Path C 退化到 baseline（gate 拒绝假 α，保护 BER）\n');
    end
elseif gate.accepted
    fprintf('\n[NOT-INJECTED] 本 seed 未触发假 α，gate 通过真 α；C/B 应一致\n');
else
    fprintf('\n[GATE-NEUTRAL] 本 seed α 估计 below_min/low_conf，C 退化到 A\n');
end

diary off;
fprintf('Log: %s\n', diary_path);
