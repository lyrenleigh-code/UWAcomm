function [frame_bb, meta] = assemble_physical_frame(body_bb, sys)
% 功能：组装物理帧 [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|body]（基带）
% 版本：V1.0.0
% 输入：
%   body_bb - 基带数据段（复信号，例如 FH-MFSK 基带波形）
%   sys     - 系统参数
% 输出：
%   frame_bb - 完整基带帧（复信号，1×N）
%   meta     - 结构体
%       .N_pre                   HFM/LFM 单段样本数
%       .N_lfm                   LFM 样本数（= N_pre）
%       .guard_samp              guard 间隔样本数
%       .lfm2_peak_nom           LFM2 匹配滤波峰位（filter 滞后 N_lfm-1）
%       .data_offset_from_lfm_head  从 LFM2 头部到 data 起点的样本数
%       .body_samples            body 样本数
%
% 依赖：gen_hfm (08_Sync)
%
% 备注：
%   前导码在基带等价表示（乘 exp(-j 2π fc t) 从 passband 转为 bb complex）。
%   upconvert() 在 TX 最后一步把完整 frame_bb 上变频到 passband。

fs   = sys.fs;
fc   = sys.fc;
bw   = sys.preamble.bw_lfm;
dur  = sys.preamble.dur;
guard = sys.preamble.guard_samp;

f_lo = fc - bw/2;
f_hi = fc + bw/2;

% 复用 08_Sync 的 gen_hfm 生成 passband HFM（仅用于功率归一化基准）
[HFM_pb, ~] = gen_hfm(fs, dur, f_lo, f_hi);
N_pre = length(HFM_pb);
t_pre = (0:N_pre-1) / fs;

% --- HFM+ 基带 ---
if abs(f_hi - f_lo) < 1e-6
    phase_hfm = 2*pi*f_lo*t_pre;
else
    k_hfm = f_lo * f_hi * dur / (f_hi - f_lo);
    phase_hfm = -2*pi * k_hfm * log(1 - (f_hi - f_lo)/f_hi * t_pre / dur);
end
HFM_bb = exp(1j * (phase_hfm - 2*pi*fc*t_pre));

% --- HFM- 基带（负扫频）---
if abs(f_hi - f_lo) < 1e-6
    phase_neg = 2*pi*f_hi*t_pre;
else
    k_neg = f_hi * f_lo * dur / (f_lo - f_hi);
    phase_neg = -2*pi * k_neg * log(1 - (f_lo - f_hi)/f_lo * t_pre / dur);
end
HFM_bb_neg = exp(1j * (phase_neg - 2*pi*fc*t_pre));

% --- LFM 基带 ---
chirp_rate = (f_hi - f_lo) / dur;
phase_lfm = 2*pi * (f_lo * t_pre + 0.5 * chirp_rate * t_pre.^2);
LFM_bb = exp(1j * (phase_lfm - 2*pi*fc*t_pre));
N_lfm = length(LFM_bb);

% --- 功率归一化：以 body passband 功率为基准 ---
% body_bb 上变频后的 RMS 作参考
[body_pb_ref, ~] = upconvert(body_bb, fs, fc);
body_rms = sqrt(mean(body_pb_ref.^2));
hfm_rms  = sqrt(mean(HFM_pb.^2));
if hfm_rms > 1e-12
    scale = body_rms / hfm_rms;
else
    scale = 1;
end

HFM_bb_n     = HFM_bb     * scale;
HFM_bb_neg_n = HFM_bb_neg * scale;
LFM_bb_n     = LFM_bb     * scale;

% --- 帧组装 ---
frame_bb = [HFM_bb_n, zeros(1, guard), ...
            HFM_bb_neg_n, zeros(1, guard), ...
            LFM_bb_n, zeros(1, guard), ...
            LFM_bb_n, zeros(1, guard), ...
            body_bb(:).'];

% --- meta ---
meta = struct();
meta.N_pre       = N_pre;
meta.N_lfm       = N_lfm;
meta.guard_samp  = guard;
% LFM2 匹配滤波峰位（filter 滞后：LFM2 头部 + N_lfm - 1）
meta.lfm2_head   = 2*N_pre + 3*guard + N_lfm;                     % LFM2 头在 frame_bb 的 1-based 起点
meta.lfm2_peak_nom = meta.lfm2_head + N_lfm - 1;                   % 匹配滤波理论峰位
meta.data_offset_from_lfm_head = N_lfm + guard;                    % LFM2 头 → data 头
meta.data_start  = meta.lfm2_head + meta.data_offset_from_lfm_head; % data 在 frame_bb 的 1-based 起点
meta.body_samples= length(body_bb);
meta.frame_len   = length(frame_bb);

end
