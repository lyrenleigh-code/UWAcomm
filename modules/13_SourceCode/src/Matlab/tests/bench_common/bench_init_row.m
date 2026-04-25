function row = bench_init_row(stage, scheme)
% 功能：初始化单点 benchmark row，固定字段顺序（CSV 列顺序）
% 版本：V1.0.0
% 输入：
%   stage  - 'A1'/'A2'/'A3'/'B'/'C'
%   scheme - 'SC-FDE'/'OFDM'/'SC-TDE'/'OTFS'/'DSSS'/'FH-MFSK'
% 输出：
%   row - struct，字段按 CSV schema 顺序预置 NaN/空字符串
%
% 备注：
%   字段顺序必须与 spec/plan 一致，保证各阶段 CSV header 对齐

row = struct();
row.timestamp        = datestr(now, 'yyyy-mm-ddTHH:MM:SS');  %#ok<*DATST>
row.matlab_ver       = get_matlab_ver_short();
row.stage            = stage;
row.scheme           = scheme;
row.profile          = '';
row.fd_hz            = NaN;
row.doppler_rate     = NaN;
row.snr_db           = NaN;
row.seed             = NaN;
row.ber_coded        = NaN;
row.ber_uncoded      = NaN;
row.nmse_db          = NaN;
row.sync_tau_err     = NaN;
row.frame_detected   = 0;
row.turbo_final_iter = NaN;
row.runtime_s        = NaN;
row.alpha_est        = NaN;  % 2026-04-19 D 阶段新增（constant-doppler-isolation）
row.alpha_lfm_raw    = NaN;  % 2026-04-25 SC-TDE fd=1Hz α fix Phase 1：est_alpha_dual_chirp 直出
row.alpha_lfm_iter   = NaN;  % bench_alpha_iter refinement 后
row.alpha_lfm_scan   = NaN;  % 大 α (>1.5e-2) 局部精扫后
row.diag_tau_up_int   = NaN; % 2026-04-25 Phase 2 C2：LFM up-chirp 整数样本峰位置
row.diag_tau_dn_int   = NaN; % LFM down-chirp 整数样本峰位置
row.diag_tau_up_frac  = NaN; % up-chirp 子样本偏移 [-0.5, 0.5]
row.diag_tau_dn_frac  = NaN; % down-chirp 子样本偏移
row.diag_snr_up       = NaN; % up-chirp peak/median 启发式 SNR
row.diag_snr_dn       = NaN; % down-chirp peak/median 启发式 SNR
row.diag_dtau_resid_s = NaN; % dual-chirp 残差时间差（秒）

end

function v = get_matlab_ver_short()
v_full = version();
% 取前 10 字符（如 "9.14.0.22" / "24.2.0.263"）
v = v_full(1:min(10, length(v_full)));
end
