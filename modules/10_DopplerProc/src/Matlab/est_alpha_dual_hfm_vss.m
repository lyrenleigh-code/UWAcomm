function [alpha, diag] = est_alpha_dual_hfm_vss(bb_segment, HFM_up, HFM_dn, ...
                                                 f_lo, f_hi, T, T_e, fs, search_cfg)
% 功能：基于 HFM 双信号速度谱扫描的高精度 α 估计（wei-2020 IEEE SPL）
% 版本：V1.0.0（2026-04-21）
% 对应 spec: specs/active/2026-04-21-hfm-velocity-spectrum-refinement.md
%
% 原理：
%   利用 HFM 的 Doppler 不变性 s(kt) ≈ s(t-ε(k))·exp(jϑ(k))，
%   在频域构造统计量 U(f) = f⁴·|X(f)|²/(S(f))²（Eq.14），
%   该 U(f) 含与 Δτ=τ_2-τ_1 相关的正弦分量。
%   通过 1D 速度扫描 Y(v) = ∫ U(f)·exp(j·2π·f·(c_1·v+c_2))·df（Eq.21）
%   的 argmax 得到速度估计，精度不受采样率限制（相比时延差法提升 ~10×）。
%
% 输入：
%   bb_segment - 1×N complex，含双 HFM 对的基带信号段
%                paper 的 "up+gap+down" 或 "down+gap+up" 均可（见 convention）
%   HFM_up     - 1×N_hfm complex，up-HFM 模板（f_lo → f_hi 基带相位）
%   HFM_dn     - 1×N_hfm complex，down-HFM 模板（f_hi → f_lo）
%   f_lo, f_hi - HFM 频率边界（Hz，通带绝对频率）
%   T          - HFM 持续时间（秒）
%   T_e        - 两 HFM 间隔（秒），对应 SC-FDE 帧中 guard_samp/fs
%   fs         - 采样率（Hz）
%   search_cfg - struct:
%       .v_range     [v_min, v_max] (m/s)，默认 ±112
%       .dv_coarse   粗扫步长 (m/s)，默认 0.5
%       .dv_fine     精扫步长 (m/s)，默认 0.02
%       .c_sound     声速，默认 1500 m/s
%       .first_hfm   'up' 或 'down'，bb_segment 中首个 HFM 类型（默认 'up'）
% 输出：
%   alpha - scalar double，v/c，符号约定与 gen_uwa_channel.doppler_rate 对齐
%   diag  - struct:
%       .v_est            估计速度 (m/s)
%       .alpha_est        估计 α
%       .v_coarse_grid    粗扫速度网格
%       .Y_coarse         粗扫 |Y(v)|
%       .v_fine_grid      精扫速度网格
%       .Y_fine           精扫 |Y(v)|
%       .peak_psr         peak-to-sidelobe ratio
%       .scan_time_s      扫描耗时

%% 1. 入参校验
if nargin < 9, search_cfg = struct(); end
defaults = struct('v_range', [-112, 112], 'dv_coarse', 0.5, 'dv_fine', 0.02, ...
                  'c_sound', 1500, 'first_hfm', 'up');
fns = fieldnames(defaults);
for k = 1:numel(fns)
    if ~isfield(search_cfg, fns{k}), search_cfg.(fns{k}) = defaults.(fns{k}); end
end
c = search_cfg.c_sound;

%% 2. HFM 物理参数
f_0 = 2 * f_lo * f_hi / (f_lo + f_hi);
M   = 4 * f_lo * f_hi * (f_hi - f_lo) / ((f_lo + f_hi)^2 * T);
% wei-2020 Eq.21 的物理常数：paper 帧顺序 down+up 用 +2f_0/M；up+down 用 -2f_0/M
% （Δτ = (T+Te)/k ± 2ε(k) 的符号由帧顺序决定）
sign_eps = 1;
if strcmpi(search_cfg.first_hfm, 'up')
    sign_eps = -1;   % up+down: Δτ = (T+Te)/k - 2ε(k)
end
c_1 = (T + T_e + sign_eps * 2*f_0/M) / c;
c_2 = T + T_e;

%% 3. 零填充 bb_segment 到 T_seg > 2·(2T+T_e)
N_seg = length(bb_segment);
N_min_seg = ceil(2.5 * (2*T + T_e) * fs);
N_fft = max(N_seg, N_min_seg);
N_fft = 2^nextpow2(N_fft);   % FFT 长度取 2 次幂加速

bb_padded = zeros(1, N_fft);
bb_padded(1:N_seg) = bb_segment(:).';

%% 4. 计算 X(f) = FFT(bb_padded) 和 S(f) = FFT(down-HFM zero-padded)
% paper §III 末尾: "the down-sweeping HFM signal should be extended to the same
%                   length as X(f) by padding zero"
% S(f) 是 down-HFM 模板 FFT，因为 paper Eq.12: S(f) = F[s^(d)(T,t)]
% （up-HFM 的 FFT 是 S*(f)，paper §III）
%
% 注意：基带 HFM_dn 已减去 fc 载波，frequency domain 在 (f_lo - fc, f_hi - fc)
% 论文里的 f 是通带，我们在基带里需要对应 baseband 的 (f_l_bb, f_h_bb)
% 简化：所有处理都在基带，f_lo_bb, f_hi_bb 对应 (f_lo-fc, f_hi-fc)
% 但 passband f_0, M 保持（物理 HFM 参数）。
hfm_dn_pad = zeros(1, N_fft);
hfm_dn_pad(1:length(HFM_dn)) = HFM_dn(:).';
S = fft(hfm_dn_pad);
X = fft(bb_padded);

%% 5. 构造频谱掩码（基带里 (f_lo - fc, f_hi - fc) 对应的频率 bin）
% 基带 HFM 模板是 exp(j·(phase_hfm - 2π·fc·t))，基带频率范围 (f_lo - fc, f_hi - fc)
% 但对于 |X(f)|² 和 S(f)，我们只关心其内含 HFM 信号的频段
% 基带 FFT 的正频率 bin 对应 0 → fs/2，需要 wrap 到 baseband HFM 频段
% 为通用，直接用 (f_lo, f_hi) 的 baseband 映射
fc_bb = (f_lo + f_hi) / 2;  % HFM 频段中心（用于基带推算）
f_lo_bb = f_lo - fc_bb;     % baseband freq for lowest HFM bin
f_hi_bb = f_hi - fc_bb;
% FFT bin 频率（考虑负频率）
if mod(N_fft, 2) == 0
    f_bins = [0:N_fft/2-1, -N_fft/2:-1] * fs / N_fft;
else
    f_bins = [0:(N_fft-1)/2, -(N_fft-1)/2:-1] * fs / N_fft;
end

% 基带 HFM 基带频段 (f_lo - fc, f_hi - fc)，对 fc=12kHz, bw=8kHz: (-4050, +4050)
% paper f_pb ∈ (f_lo, f_hi) 对应基带 f_bins ∈ (f_lo - fc, f_hi - fc)
f_mask = (f_bins >= f_lo_bb) & (f_bins <= f_hi_bb);

%% 6. 计算 U(f) = f_pb⁴·|X(f)|²/(S(f))²（Eq.14 通带版本）
% paper 在通带工作，f_pb = f_bb + fc（fc=HFM 频段中心近似）
% U 里 f⁴ 必须用通带 f_pb 才对应 paper 推导
fc_pb = fc_bb;   % 通带中心（= (f_lo+f_hi)/2）
f_pb  = f_bins + fc_pb;  % 基带 f_bb 映射到通带 f_pb
% (S(f))² 是复数平方（不是 |S|²），paper Eq.15 展开里含相位
S_sq = S.^2;
S_sq_safe = S_sq;
S_sq_safe(abs(S_sq_safe) < eps) = eps;  % 防除零
U = zeros(1, N_fft);
U(f_mask) = (f_pb(f_mask).^4) .* (abs(X(f_mask)).^2) ./ S_sq_safe(f_mask);

%% 7. 速度谱粗扫（paper Eq.14 + Eq.21 严格版）
t_scan = tic;
v_coarse = search_cfg.v_range(1) : search_cfg.dv_coarse : search_cfg.v_range(2);
Y_coarse = zeros(1, length(v_coarse));

% 预计算掩码下的 U 和 f_pb（用通带频率做 Y(v) 积分相位）
U_masked = U(f_mask);
f_pb_masked = f_pb(f_mask);

% paper Eq.21: Y(v) = Σ U(f) · exp(j·2π·f·(c_1·v + c_2))
for vi = 1:length(v_coarse)
    v = v_coarse(vi);
    phase = 2*pi * f_pb_masked * (c_1 * v + c_2);
    Y_coarse(vi) = sum(U_masked .* exp(1j * phase));
end

[~, i_peak] = max(abs(Y_coarse));
v_coarse_est = v_coarse(i_peak);

%% 8. 精扫（围绕 coarse peak ±3·dv_coarse）
v_fine = v_coarse_est + (-3*search_cfg.dv_coarse : search_cfg.dv_fine : 3*search_cfg.dv_coarse);
Y_fine = zeros(1, length(v_fine));
for vi = 1:length(v_fine)
    v = v_fine(vi);
    phase = 2*pi * f_pb_masked * (c_1 * v + c_2);
    Y_fine(vi) = sum(U_masked .* exp(1j * phase));
end

%% 9. 精扫取峰 + 抛物线插值
[~, i_fine] = max(abs(Y_fine));
Y_fine_abs = abs(Y_fine);
if i_fine > 1 && i_fine < length(Y_fine)
    y0 = Y_fine_abs(i_fine-1);
    y1 = Y_fine_abs(i_fine);
    y2 = Y_fine_abs(i_fine+1);
    denom = 2*(y0 - 2*y1 + y2);
    if abs(denom) > eps
        offset = (y0 - y2) / denom;
        offset = max(-0.5, min(0.5, offset));
    else
        offset = 0;
    end
    v_est = v_fine(i_fine) + offset * search_cfg.dv_fine;
else
    v_est = v_fine(i_fine);
end

%% 10. α 转换 + 符号对齐
%   gen_uwa_channel.doppler_rate: α>0 → 压缩（相向）
%   paper v: v>0 → 远离（k=c/(c+v)）
% 所以 α = -v/c
% c_1 公式已经对 up+down 帧做了符号修正（sign_eps=-1），所以 v 估计符号自洽
alpha = -v_est / c;

%% 11. 诊断
% PSR: peak / median sidelobe
peak_val = abs(Y_fine(i_fine));
median_sidelobe = median(abs(Y_fine));
psr = peak_val / max(median_sidelobe, eps);

diag = struct();
diag.v_est         = v_est;
diag.alpha_est     = alpha;
diag.v_coarse_grid = v_coarse;
diag.Y_coarse      = Y_coarse;
diag.v_fine_grid   = v_fine;
diag.Y_fine        = Y_fine;
diag.peak_psr      = psr;
diag.scan_time_s   = toc(t_scan);
diag.f_0           = f_0;
diag.M             = M;
diag.c_1           = c_1;
diag.c_2           = c_2;

end
