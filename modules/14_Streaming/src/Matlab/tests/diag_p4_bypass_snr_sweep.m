function diag_p4_bypass_snr_sweep()
% DIAG_P4_BYPASS_SNR_SWEEP  Phase 0: 扫 SNR 验 H1（bypass=ON Doppler BER 灾难是否 effective SNR 差异）
%
% spec: specs/active/2026-05-01-p4-bypass-on-doppler-ber-rca.md
%
% 设计：
%   bypass=ON dop=10Hz × SNR ∈ {15, 20, 25, 30, 35} × {SC-FDE, OFDM, SC-TDE}
%   bypass=OFF dop=10Hz × SNR ∈ {15}                  作 baseline
%
% 期望（H1 成立）：bypass=ON BER 单调下降，到某 SNR* 与 OFF SNR=15 等价
%   → 校准 fix 方向 = 提升 ON 路径 effective SNR（lpf 等效）或降 OFF 严格度
%
% 期望（H1 不成立 / 部分）：bypass=ON 在 SNR=35 仍高 BER → 转 Phase 1 验 H2 载波相位
%
% 用法：matlab -batch "diag_p4_bypass_snr_sweep"

%% 路径
this_dir       = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
mod14_root     = fileparts(fileparts(streaming_root));
modules_root   = fileparts(mod14_root);
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'tx'));
addpath(fullfile(streaming_root, 'rx'));
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(modules_root, '02_ChannelCoding', 'src', 'Matlab'));
addpath(fullfile(modules_root, '03_Interleaving',  'src', 'Matlab'));
addpath(fullfile(modules_root, '05_SpreadSpectrum','src', 'Matlab'));
addpath(fullfile(modules_root, '06_MultiCarrier',  'src', 'Matlab'));
addpath(fullfile(modules_root, '07_ChannelEstEq',  'src', 'Matlab'));
addpath(fullfile(modules_root, '08_Sync',          'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform',      'src', 'Matlab'));
addpath(fullfile(modules_root, '10_DopplerProc',   'src', 'Matlab'));
addpath(fullfile(modules_root, '12_IterativeProc', 'src', 'Matlab'));
addpath(fullfile(modules_root, '13_SourceCode',    'src', 'Matlab', 'common'));

schemes = {'SC-FDE','OFDM','SC-TDE'};
SNR_list_ON  = [15 20 25 30 35];
SNR_OFF      = 15;

cd_static_dop10 = struct('name','static dop=10','fading','static','dop_hz',10,'fd_jakes',0);
preset = '6径 标准水声';
text   = 'Hello UWAcomm bypass test';
sys0   = sys_params_default();
fs = sys0.fs;
fc = sys0.fc;

% 多 seed 平均（消除单 seed 抖动）
n_seed = 3;

fprintf('========== Phase 0: bypass=ON SNR sweep (dop=10Hz, %d seeds) ==========\n', n_seed);
fprintf('spec: 2026-05-01-p4-bypass-on-doppler-ber-rca.md (H1)\n\n');

%% bypass=OFF baseline
fprintf('--- bypass=OFF baseline (SNR=%d) ---\n', SNR_OFF);
BER_OFF = nan(length(schemes), 1);
for si = 1:length(schemes)
    sch = schemes{si};
    ui_vals = struct('blk_fft',128,'turbo_iter',2,'payload',2048, ...
        'fading_type','static (恒定)','fd_hz',0);
    [N_info, sys_p] = p4_apply_scheme_params(sch, sys0, ui_vals);
    bers = nan(1, n_seed);
    for ss = 1:n_seed
        try
            [bers(ss), ~, ~] = run_one(sch, sys_p, preset, cd_static_dop10, false, SNR_OFF, text, N_info, fs, fc, ss);
        catch
            bers(ss) = NaN;
        end
    end
    BER_OFF(si) = mean(bers, 'omitnan');
    fprintf('  %-8s : BER = %.3f%% (mean of %d seeds)\n', sch, BER_OFF(si)*100, n_seed);
end

%% bypass=ON SNR sweep
fprintf('\n--- bypass=ON SNR sweep ---\n');
BER_ON = nan(length(schemes), length(SNR_list_ON));
for si = 1:length(schemes)
    sch = schemes{si};
    ui_vals = struct('blk_fft',128,'turbo_iter',2,'payload',2048, ...
        'fading_type','static (恒定)','fd_hz',0);
    [N_info, sys_p] = p4_apply_scheme_params(sch, sys0, ui_vals);
    fprintf('  %-8s :', sch);
    for ki = 1:length(SNR_list_ON)
        snr = SNR_list_ON(ki);
        bers = nan(1, n_seed);
        for ss = 1:n_seed
            try
                [bers(ss), ~, ~] = run_one(sch, sys_p, preset, cd_static_dop10, true, snr, text, N_info, fs, fc, ss);
            catch
                bers(ss) = NaN;
            end
        end
        BER_ON(si, ki) = mean(bers, 'omitnan');
        fprintf(' SNR%2d=%6.3f%%', snr, BER_ON(si, ki)*100);
    end
    fprintf('\n');
end

%% 汇总 + 解读
fprintf('\n========== 汇总 ==========\n');
fprintf('  %-8s | OFF SNR=%d | %s\n', 'scheme', SNR_OFF, ...
    strjoin(arrayfun(@(s) sprintf('ON SNR=%d', s), SNR_list_ON, 'UniformOutput', false), ' | '));
for si = 1:length(schemes)
    fprintf('  %-8s | %8.3f%%  | ', schemes{si}, BER_OFF(si)*100);
    for ki = 1:length(SNR_list_ON)
        fprintf('%8.3f%% | ', BER_ON(si, ki)*100);
    end
    fprintf('\n');
end

fprintf('\n[INTERPRETATION]\n');
fprintf('  - 若 BER_ON 随 SNR 单调下降，且某 SNR* 与 BER_OFF(SNR=%d) 等价：\n', SNR_OFF);
fprintf('    H1（effective SNR 差异）成立。SNR* - %d ≈ ON/OFF noise 路径增益差\n', SNR_OFF);
fprintf('  - 若 BER_ON 在 SNR=%d 仍 ≥ 10%%：H1 不足以解释，转 Phase 1 验 H2（载波相位）\n', SNR_list_ON(end));

end

%% =============================================================
function [ber, sync_diff, alpha_est] = run_one(sch, sys_p, preset, cd, is_bp, SNR_db, text, N_info, fs, fc, seed)
if nargin < 11, seed = 1; end
rng(seed);

bits_raw = text_to_bits(text);
if length(bits_raw) >= N_info
    info_bits = bits_raw(1:N_info);
else
    rng_st = rng; rng(42);
    pad = randi([0 1], 1, N_info - length(bits_raw));
    rng(rng_st);
    info_bits = [bits_raw, pad];
end
[body_bb, meta_tx] = modem_encode(info_bits, sch, sys_p);
[frame_bb, ~] = assemble_physical_frame(body_bb, sys_p);
body_offset = length(frame_bb) - length(body_bb);
[h_tap, paths, ~] = p4_channel_tap(sch, sys_p, preset);
alpha_b = cd.dop_hz / fc;
L_bb = length(frame_bb);
if strcmp(cd.fading,'static')
    tv = struct('enable',false,'model','constant','drift_rate',0,'jitter_std',0);
    paths_single = struct('delays',0,'gains',1);
    frame_mp = conv(frame_bb, h_tap);
    frame_mp = frame_mp(1:L_bb);
    [frame_ch_raw, ~] = gen_doppler_channel(frame_mp, fs, alpha_b, paths_single, Inf, tv, fc);
    if length(frame_ch_raw) < L_bb
        frame_ch = [frame_ch_raw, zeros(1, L_bb-length(frame_ch_raw))];
    elseif alpha_b < 0
        frame_ch = frame_ch_raw;
    else
        frame_ch = frame_ch_raw(1:L_bb);
    end
else
    ch_params = struct('fs',fs,'num_paths',length(paths.delays), ...
        'delay_profile','custom','delays_s',paths.delays,'gains',paths.gains, ...
        'doppler_rate',alpha_b,'fading_type','slow', ...
        'fading_fd_hz',cd.fd_jakes,'snr_db',Inf,'seed',seed);
    [frame_ch_raw, ~] = gen_uwa_channel(frame_bb, ch_params);
    if length(frame_ch_raw) >= L_bb
        frame_ch = frame_ch_raw(1:L_bb);
    else
        frame_ch = [frame_ch_raw, zeros(1, L_bb-length(frame_ch_raw))];
    end
end
fifo_capacity = round(16 * fs);
ofs = round(1 * fs);
if is_bp
    sig_pwr = mean(abs(frame_ch).^2);
    nv = sig_pwr * 10^(-SNR_db/10);
    fifo = sqrt(nv/2) * (randn(1,fifo_capacity) + 1j*randn(1,fifo_capacity));
    tx_signal = frame_ch;
else
    [tx_pb, ~] = upconvert(frame_ch, fs, fc);
    tx_pb = real(tx_pb);
    sig_pwr = mean(tx_pb.^2);
    nv = sig_pwr * 10^(-SNR_db/10);
    fifo = sqrt(nv) * randn(1,fifo_capacity);
    tx_signal = tx_pb;
end
fn = length(tx_signal);
fifo(ofs : ofs+fn-1) = fifo(ofs : ofs+fn-1) + tx_signal;
fifo_write = ofs + fn + round(0.5 * fs);
sync_det = detect_frame_stream(fifo, fifo_write, 0, sys_p, ...
    struct('frame_len_hint', fn));
if ~sync_det.found
    ber = NaN; sync_diff = NaN; alpha_est = NaN;
    return;
end
fs_pos = sync_det.fs_pos;
sync_diff = fs_pos - ofs;
alpha_est = sync_det.alpha_est;
if fifo_write < fs_pos + fn - 1
    fn_use = fifo_write - fs_pos + 1;
else
    fn_use = fn;
end
rx_seg = fifo(fs_pos : fs_pos + fn_use - 1);
if abs(alpha_est) > 1e-6 && sync_det.alpha_confidence > 0.3
    rx_seg_comp = comp_resample_spline(rx_seg, alpha_est, fs, 'fast');
    if length(rx_seg_comp) >= fn_use
        rx_seg = rx_seg_comp(1:fn_use);
    else
        rx_seg = [rx_seg_comp, zeros(1, fn_use-length(rx_seg_comp))];
    end
end
if is_bp
    body_bb_rx = rx_seg(body_offset+1 : end);
else
    bw_use = max(sys_p.preamble.bw_lfm * 2, 2000);
    [full_bb_rx, ~] = downconvert(rx_seg, fs, fc, bw_use);
    body_bb_rx = full_bb_rx(body_offset+1 : min(body_offset+meta_tx.N_shaped, length(full_bb_rx)));
end
[bits_out, ~] = modem_decode(body_bb_rx, sch, sys_p, meta_tx);
n = min(length(bits_out), length(info_bits));
ber = sum(bits_out(1:n) ~= info_bits(1:n)) / n;
end
