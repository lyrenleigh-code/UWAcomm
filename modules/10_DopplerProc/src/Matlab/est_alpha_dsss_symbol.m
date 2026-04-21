function [alpha_track, alpha_avg, diag] = est_alpha_dsss_symbol(bb_raw, gold_ref, sps, fs, fc, frame_cfg, track_cfg)
% 功能：DSSS 符号级 α 跟踪（Sun-2020 JCIN 2020）
% 版本：V1.0.0（2026-04-22）
% 对应 spec: 2026-04-22-dsss-symbol-doppler-tracking.md
%
% 原理：
%   相邻 Gold31 symbol 的匹配滤波 peak 时差 Δτ = τ_{k+1} - τ_k = T_sym·(1+α_k)
%   → α_k = (Δτ - T_sym) / T_sym
%   三点余弦内插给 sub-sample 精度
%   一阶 IIR 平滑（前 5 符号累加不滤波，第 6 起启用）
%
% 输入：
%   bb_raw   - 1×N complex 基带信号（downconvert 后、未 resample，或粗 resample 后残余小）
%   gold_ref - 1×L Gold 序列（chip 级，L=31）
%   sps      - samples per chip
%   fs, fc   - 采样率 / 载频
%   frame_cfg - struct:
%       .data_start_samples  data 段起始样本索引（含 training）
%       .n_symbols           总 symbol 数
%   track_cfg - struct:
%       .alpha_block        先验 α（块估计给出），作 IIR 初值 + 搜索中心
%       .alpha_max          搜索半径绝对值
%       .iir_beta           一阶 IIR 系数（0~1），默认 0.7
%       .iir_warmup         IIR 开启前的累加符号数，默认 5
%       .use_subsample      bool，默认 true
% 输出：
%   alpha_track - 1×n_symbols 瞬时 α（逐符号 IIR 平滑后）
%   alpha_avg   - scalar，alpha_track 平均（用于 uniform resample）
%   diag        - struct：tau_peaks / alpha_raw / peak_snr / etc.

%% 1. 入参默认
if ~isfield(track_cfg, 'iir_beta'),      track_cfg.iir_beta    = 0.7; end
if ~isfield(track_cfg, 'iir_warmup'),    track_cfg.iir_warmup  = 5; end
if ~isfield(track_cfg, 'use_subsample'), track_cfg.use_subsample = true; end
if ~isfield(track_cfg, 'alpha_max'),     track_cfg.alpha_max   = 3e-2; end

alpha_center = track_cfg.alpha_block;
n_sym        = frame_cfg.n_symbols;
bb           = bb_raw(:).';
N_bb         = length(bb);

%% 2. Upsample Gold31 chip 到 sample rate，做 matched filter 模板
L = length(gold_ref);
gold_up = zeros(1, L * sps);
for k = 1:L
    gold_up((k-1)*sps + 1 : k*sps) = gold_ref(k);
end
mf = conj(fliplr(gold_up));  % 匹配滤波 kernel

T_sym_samples = L * sps;  % 248 for L=31, sps=8

%% 3. 逐符号 peak 搜索（sequential tracking：tau_expected 动态更新）
%    filter peak 在信号结束位置（filter group delay = N_template - 1）
%    symbol k 的 peak ≈ data_start + k*T_sym + T_sym - 1 (at α=0)
%    对 α>0 压缩，peak 位置被 1/(1+α) 缩放

search_radius = max(ceil(track_cfg.alpha_max * T_sym_samples * 3), 20);
tau_peaks   = zeros(1, n_sym);
peak_mags   = zeros(1, n_sym);
peak_snrs   = zeros(1, n_sym);
valid_flags = true(1, n_sym);

% 初始 peak (symbol 0) 的预期位置，考虑 alpha_center
tau_nom_first = frame_cfg.data_start_samples + (T_sym_samples - 1);
tau_cen_first = tau_nom_first / (1 + alpha_center);  % α>0 压缩，peak 更早

for k = 1:n_sym
    if k == 1
        tau_cen = tau_cen_first;
    else
        % sequential tracking：上一 peak + T_sym/(1+α_raw)
        % 若上一有效，用 tau_peaks(k-1) 预测 peak(k)
        if valid_flags(k-1)
            if k >= 2 && valid_flags(k-1) && k-2 >= 0 && valid_flags(max(1,k-1))
                alpha_hint = alpha_center;
                % 第 k>=3 可用 previous alpha_raw 预测
                if k >= 3 && valid_flags(k-2)
                    alpha_hint = (tau_peaks(k-1) - tau_peaks(k-2)) / T_sym_samples - 1;
                    alpha_hint = T_sym_samples / (tau_peaks(k-1) - tau_peaks(k-2)) - 1;
                end
            end
            tau_cen = tau_peaks(k-1) + T_sym_samples / (1 + alpha_center);
        else
            tau_cen = tau_cen_first + (k-1) * T_sym_samples / (1 + alpha_center);
        end
    end
    win_lo = max(1, round(tau_cen - search_radius));
    win_hi = min(N_bb, round(tau_cen + search_radius));
    if win_hi <= win_lo + 2
        valid_flags(k) = false;
        tau_peaks(k) = tau_cen;
        continue;
    end
    % 局部 matched filter
    % 注意：filter 从 win_lo 开始的信号片段，peak 相对位置在 segment 里
    seg = bb(max(1, win_lo - T_sym_samples + 1) : win_hi);   % 扩展前端让 filter 完整覆盖
    corr = filter(mf, 1, seg);
    corr_mag = abs(corr);

    % 只在实际 search window 内找 peak
    seg_offset = max(1, win_lo - T_sym_samples + 1) - 1;  % seg 中第 1 样本的绝对索引 - 1
    search_in_seg_lo = win_lo - seg_offset;
    search_in_seg_hi = win_hi - seg_offset;
    if search_in_seg_hi > length(corr_mag)
        search_in_seg_hi = length(corr_mag);
    end
    if search_in_seg_hi <= search_in_seg_lo
        valid_flags(k) = false;
        tau_peaks(k) = tau_cen;
        continue;
    end

    [peak_val, peak_rel] = max(corr_mag(search_in_seg_lo:search_in_seg_hi));
    peak_idx_in_seg = search_in_seg_lo + peak_rel - 1;
    peak_idx = seg_offset + peak_idx_in_seg;

    % 三点余弦内插（Sun-2020 Eq.21）
    delta = 0;
    if track_cfg.use_subsample && peak_idx_in_seg > 1 && peak_idx_in_seg < length(corr_mag)
        y_m1 = corr_mag(peak_idx_in_seg - 1);
        y_0  = corr_mag(peak_idx_in_seg);
        y_p1 = corr_mag(peak_idx_in_seg + 1);
        delta = cosine_subsample(y_m1, y_0, y_p1);
    end
    tau_peaks(k) = peak_idx + delta;
    peak_mags(k) = peak_val;

    % SNR 指标（peak / median）
    median_mag = median(corr_mag(search_in_seg_lo:search_in_seg_hi));
    peak_snrs(k) = peak_val / max(median_mag, eps);
end

%% 4. 相邻 peak 时差 → α_raw
% 物理模型：rx[n] = frame[(1+α)n]·exp(j2π·fc·α·n/fs)
%   α>0 压缩，相邻 peak 时差 Δτ = T_sym/(1+α) < T_sym
%   α = T_sym/Δτ - 1 ≈ (T_sym - Δτ)/T_sym
alpha_raw = zeros(1, n_sym);
for k = 1:n_sym-1
    if valid_flags(k) && valid_flags(k+1)
        dtau = tau_peaks(k+1) - tau_peaks(k);
        if abs(dtau) > eps
            alpha_raw(k) = T_sym_samples / dtau - 1;
        else
            alpha_raw(k) = alpha_center;
        end
    else
        alpha_raw(k) = alpha_center;  % 无效 symbol 回退先验
    end
end
alpha_raw(end) = alpha_raw(end-1);   % 最后一个延续倒数第二

%% 5. 一阶 IIR 平滑（前 iir_warmup 符号不滤波，累加；之后启用）
alpha_track = zeros(1, n_sym);
warmup = min(track_cfg.iir_warmup, n_sym);
if warmup > 1
    % 前 warmup 符号直接累加平均（等效 FIR）
    sum_raw = 0; count = 0;
    for k = 1:warmup
        if valid_flags(k)
            sum_raw = sum_raw + alpha_raw(k);
            count = count + 1;
        end
    end
    if count > 0
        init_val = sum_raw / count;
    else
        init_val = alpha_center;
    end
    for k = 1:warmup
        alpha_track(k) = init_val;   % 前 warmup 全部用累加平均
    end
else
    init_val = alpha_center;
    alpha_track(1:warmup) = init_val;
end

beta = track_cfg.iir_beta;
for k = warmup+1:n_sym
    alpha_track(k) = beta * alpha_track(k-1) + (1-beta) * alpha_raw(k-1);
end

%% 6. 平均 α（用于 uniform resample 分支）
alpha_avg = mean(alpha_track);

%% 7. 诊断
diag.tau_peaks  = tau_peaks;
diag.alpha_raw  = alpha_raw;
diag.peak_mags  = peak_mags;
diag.peak_snrs  = peak_snrs;
diag.valid_flags = valid_flags;
diag.T_sym_samples = T_sym_samples;
diag.alpha_init = init_val;

end

%% ========== 子函数：三点余弦内插 ==========
function delta = cosine_subsample(y_m1, y_0, y_p1)
% Sun-2020 Eq.21 余弦模型三点内插
%   y_k = A·cos(ω·(k·Δ - τ_0)) for k = -1, 0, 1
%   解得：cos(a) = (y_{-1}+y_{+1})/(2·y_0)，其中 a = ω·Δ
%         tan(θ) = (y_{+1}-y_{-1})/(2·y_0·sin(a))
%         fractional delay = θ/a ∈ (-0.5, 0.5)
%
% 保护：y_0 接近 0 / cos(a) 越界 / sin(a) 过小 → delta=0
delta = 0;
if abs(y_0) < eps, return; end
cos_a = (y_m1 + y_p1) / (2 * y_0);
if abs(cos_a) >= 1.0 - 1e-9
    % 退化为抛物线（cos(a) 越界 → 峰值点是采样点，或超窄峰）
    denom = 2*(2*y_0 - y_m1 - y_p1);
    if abs(denom) > eps
        delta = (y_m1 - y_p1) / denom;
    end
else
    a = acos(cos_a);
    sin_a = sin(a);
    if abs(sin_a) < eps, return; end
    tan_theta = (y_p1 - y_m1) / (2 * y_0 * sin_a);
    theta = atan(tan_theta);
    delta = theta / a;
end
delta = max(-0.5, min(0.5, delta));
end
