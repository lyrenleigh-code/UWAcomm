function [lfm_pos, sync_peak, corr_mag] = detect_lfm_start(bb_raw, sys, frame_meta)
% 功能：在基带接收信号中用 LFM 匹配滤波定位 LFM2 头部（数据段起点锚）
% 版本：V1.0.0（P1：已知标称峰位附近窗口搜索）
% 输入：
%   bb_raw     - 接收基带复信号（已下变频）
%   sys        - 系统参数
%   frame_meta - assemble_physical_frame 产出的 meta（含 lfm2_peak_nom, guard_samp）
% 输出：
%   lfm_pos    - LFM2 头部在 bb_raw 中的 1-based 样本索引
%   sync_peak  - 归一化峰值（≤1 为理想，反映同步质量）
%   corr_mag   - 匹配滤波幅度序列（debug 用）
%
% 备注：
%   - P1 使用窗口搜索（已知 lfm2_peak_nom）；P2 扩展为全局滑动检测
%   - LFM 基带模板由 sys 参数生成

fs   = sys.fs;
fc   = sys.fc;
bw   = sys.preamble.bw_lfm;
dur  = sys.preamble.dur;

f_lo = fc - bw/2;
f_hi = fc + bw/2;

% 生成 LFM 基带模板
t_pre = (0:round(dur*fs)-1) / fs;
chirp_rate = (f_hi - f_lo) / dur;
phase_lfm = 2*pi * (f_lo * t_pre + 0.5 * chirp_rate * t_pre.^2);
LFM_bb = exp(1j * (phase_lfm - 2*pi * fc * t_pre));
N_lfm = length(LFM_bb);

% 匹配滤波（时间反共轭）
mf = conj(fliplr(LFM_bb));
corr = filter(mf, 1, bb_raw(:).');
corr_mag = abs(corr);

% 搜索窗口（围绕 lfm2_peak_nom）
lfm2_peak_nom = frame_meta.lfm2_peak_nom;
margin = frame_meta.guard_samp + 200;
lo = max(1, lfm2_peak_nom - margin);
hi = min(lfm2_peak_nom + margin, length(corr_mag));

if lo > hi
    error('detect_lfm_start: 搜索窗口无效 lo=%d hi=%d len=%d', lo, hi, length(corr_mag));
end

[peak_val, rel] = max(corr_mag(lo:hi));
lfm2_peak_idx = lo + rel - 1;
lfm_pos = lfm2_peak_idx - N_lfm + 1;   % LFM2 头部 = 峰位 - (N_lfm-1)

% 归一化峰值（能量归一）
sync_peak = peak_val / sum(abs(LFM_bb).^2);

end
