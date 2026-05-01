function test_p4_bypass_matrix()
% TEST_P4_BYPASS_MATRIX  P4 UI bypass=ON detect_frame_stream fix 回归矩阵
%
% 等价模拟 P4 UI on_transmit + try_decode_frame 的核心数据流（脚本化，无 UI）：
%   modem_encode → assemble_physical_frame → channel(static/jakes) → fifo+noise
%   → detect_frame_stream → α 反补偿 → body 切片 → modem_decode
%
% 测试矩阵：5 scheme（OTFS 跳过，路径复杂）× 2 bypass × 3 condition
% 评估：sync_diff（应 |≤ ~10|）+ BER + α_est_rx
%
% 用法（CI / batch）：matlab -batch "test_p4_bypass_matrix"

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

schemes    = {'FH-MFSK','DSSS','SC-FDE','OFDM','SC-TDE'};
conditions = {
    struct('name','static dop=0',   'fading','static','dop_hz', 0, 'fd_jakes',0)
    struct('name','static dop=10',  'fading','static','dop_hz',10, 'fd_jakes',0)
    struct('name','slow Jakes fd=2','fading','jakes', 'dop_hz', 0, 'fd_jakes',2)
};

SNR_db = 15;
text   = 'Hello UWAcomm bypass test';
sys0   = sys_params_default();
fs = sys0.fs;
fc = sys0.fc;

% 信道用 p4_channel_tap '6径 标准水声'（与 P4 UI default preset 一致）
preset = '6径 标准水声';

bypass_modes = [true false];
fprintf('========== P4 bypass=ON detect fix 回归矩阵 ==========\n');
fprintf('SNR=%ddB, %d scheme × %d bypass × %d cond\n', SNR_db, length(schemes), 2, length(conditions));

n_scheme = length(schemes);
n_cond   = length(conditions);
BER  = nan(n_scheme, n_cond, 2);   % [scheme, cond, bypass]
SYNC = nan(n_scheme, n_cond, 2);
ALPHA = nan(n_scheme, n_cond, 2);
ERRMSG = cell(n_scheme, n_cond, 2);

for bi = 1:2
    is_bp = bypass_modes(bi);
    fprintf('\n---- bypass_rf = %s ----\n', tern(is_bp, 'ON  (complex baseband)', 'OFF (passband real)'));
    for si = 1:n_scheme
        sch = schemes{si};
        ui_vals = struct('blk_fft',128,'turbo_iter',2,'payload',2048, ...
            'fading_type','static (恒定)','fd_hz',0);
        [N_info, sys_p] = p4_apply_scheme_params(sch, sys0, ui_vals);
        for ci = 1:n_cond
            cd = conditions{ci};
            try
                [ber, sync_diff, alpha_est] = run_one(sch, sys_p, preset, cd, is_bp, SNR_db, text, N_info, fs, fc);
                BER(si,ci,bi) = ber;
                SYNC(si,ci,bi) = sync_diff;
                ALPHA(si,ci,bi) = alpha_est;
                mark = tern(isnan(ber), '✗SYNC', tern(ber<0.01,'✓',tern(ber<0.1,'⚠','✗')));
                fprintf('  %-8s %-18s : BER=%6.3f%% %s sync_diff=%+5d  α=%+.2e\n', ...
                    sch, cd.name, ber*100, mark, sync_diff, alpha_est);
            catch ME
                ERRMSG{si,ci,bi} = ME.message;
                fprintf('  %-8s %-18s : ERR %s\n', sch, cd.name, ME.message);
            end
        end
    end
end

%% 汇总表
fprintf('\n========== 汇总 BER (%%) ==========\n');
for bi = 1:2
    fprintf('\nbypass_rf = %s:\n', tern(bypass_modes(bi),'ON','OFF'));
    fprintf('  %-10s', 'scheme');
    for ci = 1:n_cond, fprintf(' %-18s', conditions{ci}.name); end
    fprintf('\n');
    for si = 1:n_scheme
        fprintf('  %-10s', schemes{si});
        for ci = 1:n_cond
            if isnan(BER(si,ci,bi))
                fprintf(' %-18s', 'NaN');
            else
                fprintf(' %-18s', sprintf('%.3f%% (sync%+d)', BER(si,ci,bi)*100, SYNC(si,ci,bi)));
            end
        end
        fprintf('\n');
    end
end
fprintf('\n[KEY 观察]\n');
fprintf('  · bypass=ON 各 cell sync_diff 应 |≤ ~10|（fix 后）；fix 前 bypass=ON sync_diff 大或 NaN\n');
fprintf('  · BER=NaN 表示 sync 失败或 decode 异常；详 ERRMSG\n');
fprintf('  · DSSS 在 dop_hz 下若 BER 仍高，说明 detect fix 之外另有问题（α 精度等）\n');

end

%% =============================================================
function [ber, sync_diff, alpha_est] = run_one(sch, sys_p, preset, cd, is_bp, SNR_db, text, N_info, fs, fc)
% 1. info bits
bits_raw = text_to_bits(text);
if length(bits_raw) >= N_info
    info_bits = bits_raw(1:N_info);
else
    rng_st = rng; rng(42);
    pad = randi([0 1], 1, N_info - length(bits_raw));
    rng(rng_st);
    info_bits = [bits_raw, pad];
end
% 2. encode
[body_bb, meta_tx] = modem_encode(info_bits, sch, sys_p);
[frame_bb, ~] = assemble_physical_frame(body_bb, sys_p);
body_offset = length(frame_bb) - length(body_bb);
% 3. channel — 与 P4 UI on_transmit 等价（p4_channel_tap + 双路 static/jakes）
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
else  % jakes
    ch_params = struct('fs',fs,'num_paths',length(paths.delays), ...
        'delay_profile','custom','delays_s',paths.delays,'gains',paths.gains, ...
        'doppler_rate',alpha_b,'fading_type','slow', ...
        'fading_fd_hz',cd.fd_jakes,'snr_db',Inf,'seed',1);
    [frame_ch_raw, ~] = gen_uwa_channel(frame_bb, ch_params);
    if length(frame_ch_raw) >= L_bb
        frame_ch = frame_ch_raw(1:L_bb);
    else
        frame_ch = [frame_ch_raw, zeros(1, L_bb-length(frame_ch_raw))];
    end
end
% 4. fifo + noise（capacity 与 P4 UI 一致：16s）
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
% 5. detect
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
% α 补偿
if abs(alpha_est) > 1e-6 && sync_det.alpha_confidence > 0.3
    rx_seg_comp = comp_resample_spline(rx_seg, alpha_est, fs, 'fast');
    if length(rx_seg_comp) >= fn_use
        rx_seg = rx_seg_comp(1:fn_use);
    else
        rx_seg = [rx_seg_comp, zeros(1, fn_use-length(rx_seg_comp))];
    end
end
% 6. body 切 + decode
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

function s = tern(c, a, b)
if c, s = a; else, s = b; end
end
