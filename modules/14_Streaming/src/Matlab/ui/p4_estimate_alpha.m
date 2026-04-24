function [alpha, diag] = p4_estimate_alpha(rx_bb_seg, sys)
% 功能：用 est_alpha_dual_hfm_vss（wei-2020 VSS）估 α，专供 P4 try_decode_frame RX 补偿
% 版本：V1.0.0 (2026-04-22)
% 用法：[alpha, diag] = p4_estimate_alpha(rx_bb_seg, sys)
% 输入：
%   rx_bb_seg  已下变频的基带信号段（必须含 HFM+ guard HFM- 区段 且起点 = HFM+ 头）
%   sys        系统参数
% 输出：
%   alpha      估计的 α（v/c，符号约定 = gen_uwa_channel，正=压缩）
%              → 可直接传 comp_resample_spline(rx, alpha, fs) 做反向补偿
%   diag       估计器诊断 struct（透传 est_alpha_dual_hfm_vss 返回）
%
% 备注：
%   1. 与 detect_frame_stream 自带 α 估计对比：
%      detect_frame_stream 用亚样本 peak 抛物线拟合，未校准 2.2× bias
%      est_alpha_dual_hfm_vss 用频域速度谱扫描，有标准测试保证
%   2. HFM 模板参数与 assemble_physical_frame.m 一致

    fs   = sys.fs;
    fc   = sys.fc;
    bw   = sys.preamble.bw_lfm;
    dur  = sys.preamble.dur;
    guard = sys.preamble.guard_samp;

    f_lo = fc - bw/2;
    f_hi = fc + bw/2;

    % 生成基带 HFM 模板（与 assemble_physical_frame.m L37-53 同公式）
    N_pre = round(dur * fs);
    t_pre = (0:N_pre-1) / fs;

    if abs(f_hi - f_lo) < 1e-6
        phase_hfm = 2*pi*f_lo*t_pre;
        phase_neg = 2*pi*f_hi*t_pre;
    else
        k_hfm = f_lo * f_hi * dur / (f_hi - f_lo);
        phase_hfm = -2*pi * k_hfm * log(1 - (f_hi - f_lo)/f_hi * t_pre / dur);
        k_neg = f_hi * f_lo * dur / (f_lo - f_hi);
        phase_neg = -2*pi * k_neg * log(1 - (f_lo - f_hi)/f_lo * t_pre / dur);
    end
    HFM_up = exp(1j * (phase_hfm - 2*pi*fc*t_pre));
    HFM_dn = exp(1j * (phase_neg - 2*pi*fc*t_pre));

    T   = dur;
    T_e = guard / fs;

    % 提取含双 HFM 的段（从 rx_bb_seg 起点，足够覆盖 |α|<0.1 下展开后的长度）
    seg_len = ceil((2*N_pre + guard) / (1 - 0.1)) + 500;
    if length(rx_bb_seg) < seg_len
        seg_len = length(rx_bb_seg);
    end
    bb_segment = rx_bb_seg(1:seg_len);

    search_cfg = struct( ...
        'v_range',   [-60, 60], ...   % ±60 m/s 足够，α_max≈±4e-2
        'dv_coarse', 0.5, ...
        'dv_fine',   0.02, ...
        'c_sound',   1500, ...
        'first_hfm', 'up' );          % 帧结构 HFM+ 在前

    [alpha, diag] = est_alpha_dual_hfm_vss(bb_segment, HFM_up, HFM_dn, ...
                                            f_lo, f_hi, T, T_e, fs, search_cfg);
end
