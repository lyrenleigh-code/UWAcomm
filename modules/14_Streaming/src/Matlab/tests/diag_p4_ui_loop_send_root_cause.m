function diag_p4_ui_loop_send_root_cause()
% DIAG_P4_UI_LOOP_SEND_ROOT_CAUSE  P4 UI "未点 Transmit 自动循环发" 根因诊断
%
% 验证两个 hypothesis（H1+H2 共同成立 → 循环发现象成立）：
%   H1: detect_frame_stream 在 fifo 残段（信号已解码完、仅噪声）会 false-positive
%       找到 peak 并返回 found=true
%   H2: 一旦 tx_pending=true 状态在 try_decode_frame 异常路径 leak，每个 100ms tick
%       都会调 detect → 反复触发解码 → 反复加 history → 表象 = "循环发"
%
% 本脚本只测 callee detect_frame_stream（不依赖 UI），给出量化指标。
% UI 真实修复效果须在 UI 中实测（按一次 Transmit 观察 history 是否多次增长）。
%
% 用法：
%   cd D:\Claude\TechReq\UWAcomm-claude\modules\14_Streaming\src\Matlab\tests
%   clear functions; clear all;
%   diary diag_p4_ui_loop_send_results.txt
%   diag_p4_ui_loop_send_root_cause()
%   diary off

%% 0. 路径
this_dir       = fileparts(mfilename('fullpath'));
streaming_root = fileparts(this_dir);
mod14_root     = fileparts(fileparts(streaming_root));
modules_root   = fileparts(mod14_root);
addpath(fullfile(streaming_root, 'common'));
addpath(fullfile(streaming_root, 'ui'));
addpath(fullfile(modules_root, '08_Sync',          'src', 'Matlab'));
addpath(fullfile(modules_root, '09_Waveform',      'src', 'Matlab'));
addpath(fullfile(modules_root, '13_SourceCode',    'src', 'Matlab', 'common'));

%% 1. 默认 sys + 前导参数
sys   = sys_params_default();
fs    = sys.fs;
fc    = sys.fc;
N_pre = round(sys.preamble.dur * fs);
guard = sys.preamble.guard_samp;
preamble_len = 4*N_pre + 4*guard;

fprintf('========== P4 UI 循环发送根因诊断 ==========\n');
fprintf('[CFG] fs=%dHz fc=%dHz N_pre=%d preamble_len=%d (%.3fs)\n', ...
    fs, fc, N_pre, preamble_len, preamble_len/fs);

%% 2. 构造 fifo: [噪声 | 完整前导 | 数据噪声 | 噪声尾]
fifo_capacity = round(8 * fs);
ofs           = round(2 * fs);                  % 信号起点（fifo 绝对索引）
frame_data_n  = round(0.5 * fs);                % 数据段 0.5s
frame_total   = preamble_len + frame_data_n;
fifo_write    = round(5 * fs);                  % 模拟已写 5s

rng(42);
fifo = 0.05 * randn(1, fifo_capacity);          % 噪声底
preamble_pb = build_preamble_passband(sys);
fifo(ofs : ofs + length(preamble_pb) - 1) = preamble_pb;
data_seg = 0.3 * randn(1, frame_data_n);
fifo(ofs + length(preamble_pb) : ofs + length(preamble_pb) + frame_data_n - 1) = data_seg;

fprintf('[FIFO] capacity=%d 信号起点=%d 帧总长=%d fifo_write=%d\n', ...
    fifo_capacity, ofs, frame_total, fifo_write);

%% 3. 基线: 第一次 detect（last_decode_at=0 → 应找到真信号 fs_pos≈ofs）
sync0 = detect_frame_stream(fifo, fifo_write, 0, sys, ...
    struct('frame_len_hint', frame_total));
fprintf('\n[BASELINE] 首次 detect (last_decode_at=0):\n');
fprintf('  found=%d fs_pos=%d (期望 ≈%d, 偏差=%+d)\n', ...
    sync0.found, sync0.fs_pos, ofs, sync0.fs_pos - ofs);
fprintf('  peak_val=%.2f peak_ratio=%.2f noise_floor=%.2e threshold=%.2f\n', ...
    sync0.peak_val, sync0.peak_ratio, sync0.noise_floor, sync0.threshold);

%% 4. 模拟 try_decode_frame leak 后的反复 detect
% 假设：path D leak 后 last_decode_at = fs_pos0，tx_pending 仍 true
% 每 tick fifo_write 增长 100ms 噪声，detect 在 [last_decode_at + min_gap, fifo_write] 找
n_iter = 30;
last_decode_at = sync0.fs_pos;
log = zeros(n_iter, 4);   % [iter, found, fs_pos, peak_ratio]

fprintf('\n--- 模拟 %d 次 leak 后 detect (last_decode_at 推进 + fifo 持续生长 100ms 噪声/tick) ---\n', n_iter);
for k = 1:n_iter
    sync_det = detect_frame_stream(fifo, fifo_write, last_decode_at, sys, ...
        struct('frame_len_hint', frame_total));
    log(k, :) = [k, sync_det.found, sync_det.fs_pos, sync_det.peak_ratio];

    if sync_det.found
        % 模拟 path D：异常后 last_decode_at = fs_pos
        last_decode_at = sync_det.fs_pos;
    end

    add_n = round(0.1 * fs);
    if fifo_write + add_n <= fifo_capacity
        fifo(fifo_write+1 : fifo_write+add_n) = 0.05 * randn(1, add_n);
        fifo_write = fifo_write + add_n;
    end
end

%% 5. 报告
n_found = sum(log(:, 2));
fprintf('\n[RESULT]\n');
fprintf('  iter 总数  = %d\n', n_iter);
fprintf('  found=true = %d (%.1f%%)\n', n_found, 100*n_found/n_iter);

fprintf('\n  逐次 fs_pos 推进：\n');
for k = 1:n_iter
    if log(k, 2)
        fprintf('    iter %2d: found=YES fs_pos=%-8d peak_ratio=%.2f\n', ...
            log(k,1), log(k,3), log(k,4));
    else
        fprintf('    iter %2d: found=NO\n', log(k,1));
    end
end

fprintf('\n[OBSERVATIONS]\n');
fprintf('  · 若 found 比例 > 0：detect 在 fifo 残段会 false-positive 找峰\n');
fprintf('    → 只要 tx_pending leak（异常路径未清），就会按 100ms 节奏循环触发解码\n');
fprintf('    → 与"未点 Transmit 自动循环发"现象一致；fix（清 tx_pending）必要\n');
fprintf('  · 若 found 比例 = 0：detect debounce 自洽，循环原因需另寻\n');
fprintf('\n[NOTE] 本脚本只测 detect callee；UI 真实 fix 验证需在 UI 实测：\n');
fprintf('       按 Transmit 一次 + 故意触发解码异常（如 SNR 极低 / 信道极差），\n');
fprintf('       看 history 是否仍多次增长 / 仅记录 1 次失败后停。\n');

end

%% ============================================================
%% 辅助：生成 passband 完整前导（HFM+ guard HFM- guard HFM+ guard HFM- guard）
%% ============================================================
function preamble_pb = build_preamble_passband(sys)
    fs   = sys.fs;
    fc   = sys.fc;
    bw   = sys.preamble.bw_lfm;
    dur  = sys.preamble.dur;
    gs   = sys.preamble.guard_samp;
    N_pre = round(dur * fs);
    t = (0:N_pre-1) / fs;
    f_lo = fc - bw/2;
    f_hi = fc + bw/2;

    k_pos = f_lo * f_hi * dur / (f_hi - f_lo);
    phase_pos = -2*pi * k_pos * log(1 - (f_hi - f_lo)/f_hi * t / dur);
    hfm_pos = real(exp(1j * phase_pos));

    k_neg = f_hi * f_lo * dur / (f_lo - f_hi);
    phase_neg = -2*pi * k_neg * log(1 - (f_lo - f_hi)/f_lo * t / dur);
    hfm_neg = real(exp(1j * phase_neg));

    g = zeros(1, gs);
    preamble_pb = [hfm_pos, g, hfm_neg, g, hfm_pos, g, hfm_neg, g];
end
