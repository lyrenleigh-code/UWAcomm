function det = detect_frame_stream(fifo, fifo_write, last_fs_decoded, sys, opts)
% DETECT_FRAME_STREAM  流式 HFM+ 匹配滤波帧检测（P3 demo 真同步核心）
%
% 功能：在 passband FIFO 尾部一个搜索窗口内做 downconvert + HFM+ 匹配滤波，
%       返回检测到的帧起点（绝对 FIFO 位置）+ 双 HFM corr 曲线（sync tab 可视化用）。
%       与 frame_detector.m (P2 多帧版) 的差异：
%         - 输入是 passband FIFO 而非完整基带段
%         - 只扫尾部窗口，维持实时性
%         - 返回 ground truth 对齐信息供 sync tab 显示偏差
% 版本：V1.0.0（2026-04-17 spec 2026-04-17-p3-demo-ui-sync-quality-viz Step 0）
%
% 输入：
%   fifo             — 1×N passband real 向量（环形缓冲，前 fifo_write 样本有效）
%   fifo_write       — 绝对写指针（1-based 绝对位置）
%   last_fs_decoded  — 上次已解码帧起点的绝对位置（0 = 从未解码）
%   sys              — 系统参数（含 fs/fc/preamble）
%   opts             — 可选 struct：
%       .frame_len_hint     — 预期帧长（样本，供计算搜索窗口；默认 44000 ≈ 0.9s@48k）
%       .search_window      — 搜索窗口（默认 2×frame_len_hint，覆盖整帧 + 旁侧）
%       .min_samples_ahead  — 峰值距 fifo_write 至少多少样本才确认（默认 preamble_len+200）
%       .threshold_K        — 噪底阈值倍数（默认 4）
%       .threshold_ratio    — 峰比阈值（默认 0.15）
%       .min_gap_samples    — 距上次检测最小间隔（默认 preamble_len，防重复）
%
% 输出：
%   det.found        — bool，是否检测到帧
%   det.fs_pos       — 绝对样本位置（HFM+ 头部，1-based）
%   det.peak_val     — 匹配滤波峰值
%   det.peak_ratio   — 峰值 / 旁瓣中位数
%   det.noise_floor  — corr 幅值中位数
%   det.threshold    — 使用的判决阈值
%   det.hfm_pos_corr — HFM+ 匹配滤波 corr 幅值（1×M，用于 sync tab）
%   det.hfm_neg_corr — HFM- 匹配滤波 corr 幅值（1×M）
%   det.search_abs_lo / det.search_abs_hi — 搜索窗口绝对位置边界
%   det.confidence   — 0-1 置信度（= min(peak_ratio/20, 1)）

%% 1. 默认参数
if nargin < 5, opts = struct(); end

fs = sys.fs;
fc = sys.fc;
bw = sys.preamble.bw_lfm;
dur = sys.preamble.dur;
guard = sys.preamble.guard_samp;
N_pre = round(dur * fs);                         % 单段 HFM/LFM 样本
preamble_total = 4*N_pre + 4*guard;              % 完整前导码 + body 前 guard

if ~isfield(opts, 'frame_len_hint'),    opts.frame_len_hint = 44000; end
if ~isfield(opts, 'search_window'),     opts.search_window = 2*opts.frame_len_hint + 2000; end
if ~isfield(opts, 'min_samples_ahead'), opts.min_samples_ahead = N_pre + 200; end
if ~isfield(opts, 'threshold_K'),       opts.threshold_K = 4; end
if ~isfield(opts, 'threshold_ratio'),   opts.threshold_ratio = 0.15; end
if ~isfield(opts, 'min_gap_samples'),   opts.min_gap_samples = preamble_total; end

%% 2. 初始化输出
det = struct('found', false, 'fs_pos', 0, 'peak_val', 0, ...
    'peak_ratio', 0, 'noise_floor', 0, 'threshold', 0, ...
    'hfm_pos_corr', [], 'hfm_neg_corr', [], ...
    'search_abs_lo', 0, 'search_abs_hi', 0, 'confidence', 0, ...
    'alpha_est', 0, 'alpha_confidence', 0);

%% 3. 前置检查
if fifo_write < N_pre + opts.min_samples_ahead
    return;  % FIFO 太短，无法检测
end

% 搜索窗口 = FIFO 最近的 search_window 段
search_abs_hi = fifo_write;
search_abs_lo = max(1, fifo_write - opts.search_window + 1);
% Debounce：仅当有过前次解码时才跳过已处理区间
if last_fs_decoded > 0
    search_abs_lo = max(search_abs_lo, last_fs_decoded + opts.min_gap_samples);
end
if search_abs_lo >= search_abs_hi - N_pre
    return;  % 搜索范围不足
end

det.search_abs_lo = search_abs_lo;
det.search_abs_hi = search_abs_hi;

%% 4. 提取 passband 段 → downconvert 到基带
rx_pb_seg = fifo(search_abs_lo : search_abs_hi);
bw_bb = max(bw * 1.2, 2000);  % 基带带宽足够包住前导码
[bb_raw, ~] = downconvert(rx_pb_seg, fs, fc, bw_bb);
bb_raw = bb_raw(:).';

%% 5. 生成 HFM+ / HFM- 基带模板
t_pre = (0:N_pre-1) / fs;
f_lo = fc - bw/2;
f_hi = fc + bw/2;

% HFM+ （正向双曲）
if abs(f_hi - f_lo) < 1e-6
    phase_pos = 2*pi*f_lo*t_pre;
else
    k_pos = f_lo * f_hi * dur / (f_hi - f_lo);
    phase_pos = -2*pi * k_pos * log(1 - (f_hi - f_lo)/f_hi * t_pre / dur);
end
HFM_pos_bb = exp(1j * (phase_pos - 2*pi * fc * t_pre));

% HFM- （反向双曲）
if abs(f_hi - f_lo) < 1e-6
    phase_neg = 2*pi*f_hi*t_pre;
else
    k_neg = f_hi * f_lo * dur / (f_lo - f_hi);
    phase_neg = -2*pi * k_neg * log(1 - (f_lo - f_hi)/f_lo * t_pre / dur);
end
HFM_neg_bb = exp(1j * (phase_neg - 2*pi * fc * t_pre));

%% 6. 匹配滤波（时间反共轭）
mf_pos = conj(fliplr(HFM_pos_bb));
mf_neg = conj(fliplr(HFM_neg_bb));
corr_pos = filter(mf_pos, 1, bb_raw);
corr_neg = filter(mf_neg, 1, bb_raw);
corr_pos_mag = abs(corr_pos);
corr_neg_mag = abs(corr_neg);

det.hfm_pos_corr = corr_pos_mag;
det.hfm_neg_corr = corr_neg_mag;

%% 7. 阈值 + 检测（仅用 HFM+ 做判决）
noise_floor = median(corr_pos_mag);
peak_max = max(corr_pos_mag);
threshold = max(opts.threshold_K * noise_floor, opts.threshold_ratio * peak_max);

det.noise_floor = noise_floor;
det.threshold = threshold;

% 过滤 filter 延迟启动段
valid_start = N_pre;
if valid_start > length(corr_pos_mag), return; end

[peak_val, rel_peak] = max(corr_pos_mag(valid_start:end));
abs_rel_peak = valid_start + rel_peak - 1;

if peak_val < threshold, return; end

% 峰值位置（绝对 FIFO 索引）
% filter 输出 k 位置对应输入 [k-N_pre+1 : k] 的相关，因此 HFM+ 头部 = k - N_pre + 1
hfm_head_local = abs_rel_peak - N_pre + 1;
if hfm_head_local < 1, return; end

fs_pos_abs = search_abs_lo + hfm_head_local - 1;

% 峰值足够远离 fifo_write（确保整帧已入 FIFO 前导区）
if fifo_write - fs_pos_abs < opts.min_samples_ahead, return; end

%% 8. 峰值质量量化
% 去峰后的中位数 = 旁瓣水平
mask = true(1, length(corr_pos_mag));
lo_ex = max(1, abs_rel_peak - N_pre);
hi_ex = min(length(corr_pos_mag), abs_rel_peak + N_pre);
mask(lo_ex:hi_ex) = false;
sidelobe = median(corr_pos_mag(mask));
if sidelobe < 1e-9, sidelobe = 1e-9; end
peak_ratio = peak_val / sidelobe;

%% 8b. 多普勒 α 估计（双 HFM 偏置对消，sync_dual_hfm V1.1 精确公式）
% 公式: α ≈ (τ_neg - τ_pos - G) / (2·S_bias·fs - G)
%   G = nominal_gap (采样点，HFM+ peak 到 HFM- peak 理论间距)
%   S_bias = T_hfm × f_bar / bw (秒)，f_bar = fc（HFM 平均频率）
% 亚样本精度: 对 peak 左右 1 样本做抛物线插值
alpha_est = 0;
alpha_confidence = 0;
S_bias = dur * fc / bw;
nominal_sep = N_pre + guard;  % 采样点

% 在 HFM- corr 中搜索 peak（窗口: 距 HFM+ peak 约 nominal_sep 样本）
hfm_neg_expected = abs_rel_peak + nominal_sep;
half_win = round(N_pre * 0.2);   % 搜索窗 ±0.2×N_pre
win_lo = max(valid_start, hfm_neg_expected - half_win);
win_hi = min(length(corr_neg_mag), hfm_neg_expected + half_win);
if win_hi > win_lo + 2
    [neg_peak_val, rel_neg] = max(corr_neg_mag(win_lo:win_hi));
    abs_neg_peak = win_lo + rel_neg - 1;

    % 亚样本 peak 精化（抛物线拟合）
    [tau_pos_sub] = parabolic_subsample_peak(corr_pos_mag, abs_rel_peak);
    [tau_neg_sub] = parabolic_subsample_peak(corr_neg_mag, abs_neg_peak);

    actual_sep = tau_neg_sub - tau_pos_sub;   % 亚样本精度
    denom = 2 * S_bias * fs - nominal_sep;
    if abs(denom) > 1
        alpha_est = (actual_sep - nominal_sep) / denom;
    end
    alpha_confidence = min(neg_peak_val / max(peak_val, eps), 1);
end

%% 9. 输出
det.found = true;
det.fs_pos = fs_pos_abs;
det.peak_val = peak_val;
det.peak_ratio = peak_ratio;
det.confidence = min(peak_ratio / 20, 1);
det.alpha_est = alpha_est;
det.alpha_confidence = alpha_confidence;

end


%% ============================================================
%% 辅助函数：抛物线插值亚样本 peak 位置
%% ============================================================
function idx_sub = parabolic_subsample_peak(mag, idx_int)
% 输入：幅度序列 mag，整数 peak 位置 idx_int
% 输出：亚样本精度 peak 位置（1-based）
    N = length(mag);
    if idx_int <= 1 || idx_int >= N
        idx_sub = idx_int;
        return;
    end
    y_m = mag(idx_int - 1);
    y_0 = mag(idx_int);
    y_p = mag(idx_int + 1);
    denom = y_m - 2*y_0 + y_p;
    if abs(denom) < 1e-12
        idx_sub = idx_int;
    else
        delta = 0.5 * (y_m - y_p) / denom;
        delta = max(min(delta, 0.5), -0.5);   % clamp ±0.5
        idx_sub = idx_int + delta;
    end
end
