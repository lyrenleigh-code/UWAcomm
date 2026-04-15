function [starts, peaks_info] = frame_detector(bb_raw, sys, opts)
% 功能：滑动 HFM+ 匹配滤波 + 双阈值 + debounce → 多帧起点检测
% 版本：V1.1.0（加 hybrid 预测模式提升 Jakes 鲁棒性）
% 输入：
%   bb_raw - 已下变频 + Doppler 补偿的基带复信号（1×N）
%   sys    - 系统参数
%   opts   - 可选 struct
%       .frame_len_samples  单帧标称样本数（必需）
%       .threshold_K        噪底倍数阈值（默认 4）
%       .threshold_ratio    全局峰比例阈值（默认 0.15）
%       .min_sep_factor     debounce 最小间隔系数（默认 0.9）
%       .use_predict        是否启用 hybrid 预测模式（默认 true）
%                           true: 找首帧后用 frame_len 预测后续帧位置 + ±tol 窗口取峰
%                           false: 全段滑动阈值（V1.0 行为）
%       .predict_tol_factor 预测窗口宽度系数（默认 0.05，即 ±5% × frame_len）
% 输出：
%   starts     - 1×N 检测到的帧起点（HFM+ 头位置，1-based）
%   peaks_info - struct: corr_mag, threshold, noise_floor, peak_max, raw_peaks,
%                       N_template, mode

if nargin < 3, opts = struct(); end
if ~isfield(opts, 'threshold_K'),       opts.threshold_K = 4; end
if ~isfield(opts, 'threshold_ratio'),   opts.threshold_ratio = 0.15; end
if ~isfield(opts, 'min_sep_factor'),    opts.min_sep_factor = 0.9; end
if ~isfield(opts, 'use_predict'),       opts.use_predict = true; end
if ~isfield(opts, 'predict_tol_factor'),opts.predict_tol_factor = 0.05; end
assert(isfield(opts, 'frame_len_samples'), 'frame_detector: 需要 opts.frame_len_samples');

bb_raw = bb_raw(:).';

%% ---- 1. HFM+ 模板 ----
fs = sys.fs; fc = sys.fc;
bw = sys.preamble.bw_lfm; dur = sys.preamble.dur;
f_lo = fc - bw/2; f_hi = fc + bw/2;
N_template = round(dur * fs);
t_pre = (0:N_template-1) / fs;
if abs(f_hi - f_lo) < 1e-6
    phase_hfm = 2*pi*f_lo*t_pre;
else
    k_hfm = f_lo * f_hi * dur / (f_hi - f_lo);
    phase_hfm = -2*pi * k_hfm * log(1 - (f_hi - f_lo)/f_hi * t_pre / dur);
end
HFM_bb = exp(1j * (phase_hfm - 2*pi * fc * t_pre));

%% ---- 2. 匹配滤波 ----
mf = conj(fliplr(HFM_bb));
corr = filter(mf, 1, bb_raw);
corr_mag = abs(corr);

%% ---- 3. 自适应阈值 ----
noise_floor = median(corr_mag);
peak_max = max(corr_mag);
threshold = max(opts.threshold_K * noise_floor, opts.threshold_ratio * peak_max);

%% ---- 4. 检测：hybrid 预测模式 vs 全段滑动 ----
min_sep = round(opts.min_sep_factor * opts.frame_len_samples);
predict_tol = max(round(opts.predict_tol_factor * opts.frame_len_samples), 50);

if opts.use_predict
    % --- Stage A: 直接在 frame 1 的预期位置窗口里取最大峰作为锚点 ---
    %   假设 TX 多帧 wav 必然从 frame 1 起，frame 1 的 HFM 在样本 [1, ~30% frame_len] 内
    %   不依赖全局阈值，保证 frame 1 一定会被尝试解码（即使 Jakes 深衰落让峰很弱）
    %   若解码 CRC 失败，由 text_assembler 诚实标 missing
    scan_hi = min(round(0.3 * opts.frame_len_samples) + N_template, length(corr_mag));
    if scan_hi <= N_template
        starts = [];
        mode_used = 'predict_no_first';
    else
        [f1_peak_val, rel] = max(corr_mag(N_template:scan_hi));
        f1_peak_pos = N_template + rel - 1;
        first_hfm_head = max(1, f1_peak_pos - N_template + 1);
        fprintf('[frame_detector] frame 1 anchor: k=%d, peak=%.1f (threshold=%.1f, noise=%.1f)\n', ...
            first_hfm_head, f1_peak_val, threshold, noise_floor);

        starts = first_hfm_head;
            % --- Stage B: 用首帧位置 + frame_len 预测后续帧 ---
            % 预测窗口阈值降一档（已知位置先验）
            predict_threshold = max(opts.threshold_K * 0.5 * noise_floor, ...
                                    opts.threshold_ratio * 0.3 * peak_max);
            next_hfm_head = first_hfm_head + opts.frame_len_samples;
            % 至少留 30% 帧 + 模板长度才认为可能有完整帧
            min_remaining = round(opts.frame_len_samples * 0.3) + N_template;
            while next_hfm_head + min_remaining <= length(bb_raw)
                target_peak = next_hfm_head + N_template - 1;  % 预测匹配滤波峰位
                win_lo = max(1, target_peak - predict_tol);
                win_hi = min(target_peak + predict_tol, length(corr_mag));
                if win_lo >= win_hi, break; end
                [val, rel] = max(corr_mag(win_lo:win_hi));
                if val > predict_threshold
                    actual_peak = win_lo + rel - 1;
                    actual_hfm_head = max(1, actual_peak - N_template + 1);
                    starts(end+1) = actual_hfm_head; %#ok<AGROW>
                    next_hfm_head = actual_hfm_head + opts.frame_len_samples;
                else
                    % 衰落让本帧丢失，仍按标称步进继续（不连锁失效）
                    next_hfm_head = next_hfm_head + opts.frame_len_samples;
                end
            end
            mode_used = 'predict';
    end
else
    % --- V1.0 全段滑动阈值（备用 / 真盲场景）---
    above = find(corr_mag > threshold);
    starts = [];
    i = 1;
    while i <= length(above)
        pos = above(i);
        win_end = pos + min_sep - 1;
        j = i; best = pos;
        while j <= length(above) && above(j) <= win_end
            if corr_mag(above(j)) > corr_mag(best), best = above(j); end
            j = j + 1;
        end
        hfm_head = best - N_template + 1;
        if hfm_head >= 1 - round(0.05 * N_template) && hfm_head < 1
            hfm_head = 1;
        end
        if hfm_head >= 1
            starts(end+1) = hfm_head; %#ok<AGROW>
        end
        i = j;
    end
    mode_used = 'sliding';
end

%% ---- 5. info ----
peaks_info = struct();
peaks_info.corr_mag    = corr_mag;
peaks_info.threshold   = threshold;
peaks_info.noise_floor = noise_floor;
peaks_info.peak_max    = peak_max;
peaks_info.raw_peaks   = find(corr_mag > threshold);
peaks_info.N_template  = N_template;
peaks_info.mode        = mode_used;

end
