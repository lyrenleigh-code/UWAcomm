function diag_p4_bypass_body_compare()
% DIAG_P4_BYPASS_BODY_COMPARE  Phase 1: 数值对比 ON 与 OFF 路径的 body_bb_rx
%
% spec: 2026-05-01-p4-bypass-on-doppler-ber-rca.md (H2)
%
% 设计：固定 seed + 同 frame_ch（无噪声！）→ 两路独立处理 → 对比 body_bb_rx
%   ON: rx_seg = frame_ch；body_bb_rx_ON = rx_seg(body_offset+1:end) （α 反补偿后）
%   OFF: rx_seg = real(upconvert(frame_ch))；downconvert → body_bb_rx_OFF
%
% 度量：
%   - relative L2 error: ||ON - OFF|| / ||OFF||
%   - peak phase error: angle(ON ./ OFF) max
%   - 频谱对比（FFT）
%
% 期望（H2 验证）：
%   - 若两路 body_bb_rx 数值相近 (rel_err < 1%)：modem_decode 应该一致 BER
%   - 若两路差异大：定位 upconvert/downconvert 链路的非线性 / 相位偏移
%
% 用法：matlab -batch "diag_p4_bypass_body_compare"

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

sys = sys_params_default();
fs = sys.fs; fc = sys.fc;
sch = 'OFDM';   % OFDM 在 Phase 0 ON SNR=15 51% / OFF SNR=15 0.2%，差异最大
preset = '6径 标准水声';
text   = 'Hello UWAcomm bypass test';
dop_hz_list = [0, 10];

ui_vals = struct('blk_fft',128,'turbo_iter',2,'payload',2048, ...
    'fading_type','static (恒定)','fd_hz',0);
[N_info, sys_p] = p4_apply_scheme_params(sch, sys, ui_vals);

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
[h_tap, ~, ~] = p4_channel_tap(sch, sys_p, preset);
L_bb = length(frame_bb);
N_shaped = meta_tx.N_shaped;

fprintf('========== Phase 1: ON vs OFF body_bb_rx 数值对比 (无噪声) ==========\n');
fprintf('scheme=%s, preset=%s, body_offset=%d, N_shaped=%d\n\n', sch, preset, body_offset, N_shaped);

for di = 1:length(dop_hz_list)
    dop_hz = dop_hz_list(di);
    alpha_b = dop_hz / fc;
    fprintf('--- dop_hz = %d (α=%.3e) ---\n', dop_hz, alpha_b);

    % channel
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

    % --- ON 路径 (无噪声) ---
    rx_seg_on = frame_ch;
    sync_det_on = detect_frame_stream(...
        [zeros(1, round(0.5*fs)), rx_seg_on, zeros(1, round(0.5*fs))], ...
        round(0.5*fs)+L_bb, 0, sys_p, struct('frame_len_hint', L_bb));
    fprintf('  ON  detect: found=%d fs_pos_diff=%+d α_est=%+.3e\n', ...
        sync_det_on.found, sync_det_on.fs_pos - round(0.5*fs) - 1, sync_det_on.alpha_est);

    alpha_est = sync_det_on.alpha_est;
    if abs(alpha_est) > 1e-6 && sync_det_on.alpha_confidence > 0.3
        rx_on_comp = comp_resample_spline(rx_seg_on, alpha_est, fs, 'fast');
        if length(rx_on_comp) >= L_bb
            rx_on_comp = rx_on_comp(1:L_bb);
        else
            rx_on_comp = [rx_on_comp, zeros(1, L_bb-length(rx_on_comp))];
        end
    else
        rx_on_comp = rx_seg_on;
    end
    body_on_raw = rx_on_comp(body_offset+1 : end);
    body_on_raw = body_on_raw(1:N_shaped);

    % H2 fix 候选：ON 路径载波相位反补偿 exp(-j·2π·fc·α·t)
    t_body = (0:N_shaped-1) / fs;
    body_on_fixed = body_on_raw .* exp(-1j * 2*pi * fc * alpha_est * t_body);

    body_on = body_on_raw;   % 用 raw 做主对比

    % --- OFF 路径 (无噪声) ---
    [tx_pb, ~] = upconvert(frame_ch, fs, fc);
    tx_pb = real(tx_pb);
    rx_seg_off = tx_pb;

    if abs(alpha_est) > 1e-6 && sync_det_on.alpha_confidence > 0.3
        rx_off_comp = comp_resample_spline(rx_seg_off, alpha_est, fs, 'fast');
        if length(rx_off_comp) >= L_bb
            rx_off_comp = rx_off_comp(1:L_bb);
        else
            rx_off_comp = [rx_off_comp, zeros(1, L_bb-length(rx_off_comp))];
        end
    else
        rx_off_comp = rx_seg_off;
    end
    bw_use = max(sys_p.preamble.bw_lfm * 2, 2000);
    [full_bb_off, ~] = downconvert(rx_off_comp, fs, fc, bw_use);
    body_off = full_bb_off(body_offset+1 : body_offset+N_shaped);

    % --- 对比 ---
    norm_off = norm(body_off);
    rel_err = norm(body_on - body_off) / max(norm_off, 1e-12);
    corr_iq = abs(sum(body_on .* conj(body_off))) / (norm(body_on) * norm_off + 1e-12);
    amp_ratio = norm(body_on) / max(norm_off, 1e-12);

    % phase 偏移（中位数 angle(on/off)）
    nz = abs(body_off) > 0.01 * max(abs(body_off));
    if any(nz)
        ratios = body_on(nz) ./ body_off(nz);
        med_phase = angle(median(ratios));
        med_amp = abs(median(ratios));
    else
        med_phase = NaN; med_amp = NaN;
    end

    fprintf('  rel_L2_err = %.4f  (||on-off|| / ||off||)\n', rel_err);
    fprintf('  corr_iq    = %.6f  (norm corr)\n', corr_iq);
    fprintf('  amp_ratio  = %.4f  (||on|| / ||off||)\n', amp_ratio);
    fprintf('  median(on./off): amp=%.4f phase=%+.4f rad (%.2f°)\n', med_amp, med_phase, med_phase*180/pi);

    % H2 fix 验证：ON+载波相位反补偿 vs OFF
    rel_err_fix = norm(body_on_fixed - body_off) / max(norm_off, 1e-12);
    corr_fix = abs(sum(body_on_fixed .* conj(body_off))) / (norm(body_on_fixed) * norm_off + 1e-12);
    fprintf('  [H2 fix] body_on_fixed = body_on .* exp(-j·2π·fc·α·t):\n');
    fprintf('           rel_L2_err = %.4f  corr = %.6f\n', rel_err_fix, corr_fix);

    % decode 三路对比
    [bits_on, ~] = modem_decode(body_on, sch, sys_p, meta_tx);
    [bits_on_fix, ~] = modem_decode(body_on_fixed, sch, sys_p, meta_tx);
    [bits_off, ~] = modem_decode(body_off, sch, sys_p, meta_tx);
    n_on = min(length(bits_on), length(info_bits));
    n_off = min(length(bits_off), length(info_bits));
    n_fix = min(length(bits_on_fix), length(info_bits));
    ber_on = sum(bits_on(1:n_on) ~= info_bits(1:n_on)) / n_on;
    ber_on_fix = sum(bits_on_fix(1:n_fix) ~= info_bits(1:n_fix)) / n_fix;
    ber_off = sum(bits_off(1:n_off) ~= info_bits(1:n_off)) / n_off;
    fprintf('  BER ON_raw=%.3f%%  ON_fix=%.3f%%  OFF=%.3f%%  (无噪声 baseline)\n\n', ...
        ber_on*100, ber_on_fix*100, ber_off*100);
end

fprintf('[INTERPRETATION]\n');
fprintf('  - dop=0 应两路 rel_err 极小（< 1%%），BER 都 0%%\n');
fprintf('  - dop=10 若 rel_err 仍极小但 BER 大差异 → modem_decode 内部对 ON 不友好\n');
fprintf('  - dop=10 若 rel_err 大 → upconvert/downconvert 链路在 Doppler 下引入了变换\n');
fprintf('    （重点看 amp_ratio + median phase shift；相位偏移可能就是隐式补偿）\n');

end
