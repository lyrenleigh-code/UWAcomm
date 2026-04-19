function [alpha_est, confidence] = estimate_alpha_dual_hfm(bb_rx, sys)
% ESTIMATE_ALPHA_DUAL_HFM  调用 08_Sync/sync_dual_hfm 估计多普勒 α
%
% 功能：包装 sync_dual_hfm 的调用，生成 HFM+/HFM- 基带模板 + S_bias 参数
% 版本：V1.0.0（2026-04-19 P3 UI Level 1 Doppler 补偿用）
% 输入：
%   bb_rx - 基带接收信号（下变频后，含完整帧，不剥前导）
%   sys   - 系统参数
% 输出：
%   alpha_est  - 多普勒因子估计
%   confidence - 置信度（0-1）

fs = sys.fs;
fc = sys.fc;
bw = sys.preamble.bw_lfm;
dur = sys.preamble.dur;
guard = sys.preamble.guard_samp;
N_pre = round(dur * fs);

%% 生成基带 HFM+ / HFM- 模板（同 assemble_physical_frame）
t = (0:N_pre-1) / fs;
f_lo = fc - bw/2;
f_hi = fc + bw/2;

% HFM+（正扫频）
if abs(f_hi - f_lo) < 1e-6
    phase_pos = 2*pi*f_lo*t;
else
    k_pos = f_lo * f_hi * dur / (f_hi - f_lo);
    phase_pos = -2*pi * k_pos * log(1 - (f_hi - f_lo)/f_hi * t / dur);
end
hfm_pos = exp(1j * (phase_pos - 2*pi * fc * t));

% HFM-（负扫频）
if abs(f_hi - f_lo) < 1e-6
    phase_neg = 2*pi*f_hi*t;
else
    k_neg = f_hi * f_lo * dur / (f_lo - f_hi);
    phase_neg = -2*pi * k_neg * log(1 - (f_lo - f_hi)/f_lo * t / dur);
end
hfm_neg = exp(1j * (phase_neg - 2*pi * fc * t));

%% 调 sync_dual_hfm
S_bias = dur * fc / bw;   % 偏置灵敏度 (s)
params = struct( ...
    'S_bias',      S_bias, ...
    'alpha_max',   0.01, ...
    'search_win',  length(bb_rx), ...
    'threshold',   0.3, ...
    'sep_samples', N_pre + guard);

try
    [~, alpha_est, qual, ~] = sync_dual_hfm(bb_rx, hfm_pos, hfm_neg, fs, params);
    if isempty(qual) || ~isfield(qual, 'peak_ratio')
        confidence = 0.5;
    else
        confidence = min(qual.peak_ratio / 10, 1);
    end
catch
    alpha_est = 0;
    confidence = 0;
end

end
