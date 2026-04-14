function [frame, info] = frame_assemble_otfs(otfs_bb, params)
% 功能：OTFS通带帧组装——双HFM+双LFM两级同步架构
% 版本：V2.0.0 — 对齐SC-FDE/OFDM帧结构 [HFM+|guard|HFM-|guard|LFM1|guard|LFM2|guard|OTFS_pb]
% 输入：
%   otfs_bb    - 基带OTFS信号 (1×L, otfs_modulate输出, 含per-sub-block CP)
%   params     - 帧参数结构体
%     .N, .M, .cp_len   : OTFS维度参数（per-sub-block上变频需要）
%     .sps               : 每符号采样数（通带上采样因子, 默认6）
%     .fs_bb             : 基带采样率 (Hz, 默认6000)
%     .fc                : 载频 (Hz, 默认12000)
%     .bw                : 同步信号带宽 (Hz, 默认8000)
%     .T_hfm             : HFM时长 (秒, 默认0.05)
%     .T_lfm             : LFM时长 (秒, 默认0.02)
%     .guard_ms          : 保护间隔 (毫秒, 默认5)
% 输出：
%   frame      - 通带实信号帧 (1×L_total)
%   info       - 帧信息结构体
%     .hfm_pos_bb, .hfm_neg_bb  : 基带HFM模板（供RX sync_dual_hfm用）
%     .lfm_bb                   : 基带LFM模板（供RX精确定时用）
%     .fs_pb                    : 通带采样率
%     .S_bias                   : HFM偏置灵敏度
%     .seg_pos                  : 各段起止位置 (struct)
%     .otfs_pb_len              : OTFS通带段长度
%     .params                   : 输入参数副本

%% ========== 1. 入参解析 ========== %%
if nargin < 2, params = struct(); end
if ~isfield(params, 'N'), params.N = 8; end
if ~isfield(params, 'M'), params.M = 32; end
if ~isfield(params, 'cp_len'), params.cp_len = 8; end
if ~isfield(params, 'sps'), params.sps = 6; end
if ~isfield(params, 'fs_bb'), params.fs_bb = 6000; end
if ~isfield(params, 'fc'), params.fc = 12000; end
if ~isfield(params, 'bw'), params.bw = 8000; end
if ~isfield(params, 'T_hfm'), params.T_hfm = 0.05; end   % 50ms
if ~isfield(params, 'T_lfm'), params.T_lfm = 0.02; end   % 20ms
if ~isfield(params, 'guard_ms'), params.guard_ms = 5; end
if ~isfield(params, 'sync_gain'), params.sync_gain = 0.7; end  % 同步幅度/数据峰值比（<1，同步更弱）

otfs_bb = otfs_bb(:).';
N = params.N; M = params.M; cp_len = params.cp_len;
sps = params.sps;
fs_pb = params.fs_bb * sps;
fc = params.fc; bw = params.bw;
f_lo = fc - bw/2; f_hi = fc + bw/2;

%% ========== 2. 生成同步序列（通带实信号） ========== %%
% HFM+（正扫频）和HFM-（负扫频）
[hfm_pb_pos, ~] = gen_hfm(fs_pb, params.T_hfm, f_lo, f_hi);
[hfm_pb_neg, ~] = gen_hfm(fs_pb, params.T_hfm, f_hi, f_lo);

% LFM1 和 LFM2（相同信号，双LFM用于精确定时）
[lfm_pb, ~] = gen_lfm(fs_pb, params.T_lfm, f_lo, f_hi);

% 功率归一化：同步序列RMS ≈ 数据RMS × sync_gain
% 使用RMS而非peak，避免OTFS高PAPR导致peak归一化不合理
% 预估OTFS通带RMS = BB_RMS / sqrt(2)
data_bb_rms = sqrt(mean(abs(otfs_bb).^2));
otfs_pb_rms_est = data_bb_rms / sqrt(2);  % 通带RMS理论估计
if otfs_pb_rms_est > 0
    target_rms = otfs_pb_rms_est * params.sync_gain;
    hfm_pb_pos = hfm_pb_pos / sqrt(mean(hfm_pb_pos.^2)) * target_rms;
    hfm_pb_neg = hfm_pb_neg / sqrt(mean(hfm_pb_neg.^2)) * target_rms;
    lfm_pb = lfm_pb / sqrt(mean(lfm_pb.^2)) * target_rms;
end

% 同步序列边界加窗（消除与guard的突变）
sync_taper_len = round(2e-3 * fs_pb);  % 2ms过渡区
sync_up = 0.5 * (1 - cos(pi * (0:sync_taper_len-1) / sync_taper_len));
sync_dn = 0.5 * (1 + cos(pi * (0:sync_taper_len-1) / sync_taper_len));
hfm_pb_pos(1:sync_taper_len) = hfm_pb_pos(1:sync_taper_len) .* sync_up;
hfm_pb_pos(end-sync_taper_len+1:end) = hfm_pb_pos(end-sync_taper_len+1:end) .* sync_dn;
hfm_pb_neg(1:sync_taper_len) = hfm_pb_neg(1:sync_taper_len) .* sync_up;
hfm_pb_neg(end-sync_taper_len+1:end) = hfm_pb_neg(end-sync_taper_len+1:end) .* sync_dn;
lfm_pb_windowed = lfm_pb;
lfm_pb_windowed(1:sync_taper_len) = lfm_pb_windowed(1:sync_taper_len) .* sync_up;
lfm_pb_windowed(end-sync_taper_len+1:end) = lfm_pb_windowed(end-sync_taper_len+1:end) .* sync_dn;
lfm_pb = lfm_pb_windowed;

% 保护间隔
N_guard = round(params.guard_ms * 1e-3 * fs_pb);
guard = zeros(1, N_guard);

% 长度约束检查: 数据长度 >= 2 × 同步头总长
L_sync_total = 2*length(hfm_pb_pos) + 2*length(lfm_pb) + 4*N_guard;
L_otfs_expected = N * (M + cp_len) * sps;
if L_otfs_expected < 2 * L_sync_total
    warning('frame_assemble_otfs: 数据长度(%d)小于2×sync长度(%d)，建议增大N', ...
            L_otfs_expected, 2*L_sync_total);
end

%% ========== 3. OTFS基带→通带（逐子块interpft + 过渡窗）========== %%
% 4*sps样本过渡窗（与V4.0 otfs_to_passband一致），消除子块间Gibbs振铃
sub_size = M + cp_len;
sub_up = sub_size * sps;
win_taper = 4 * sps;
taper_up = 0.5 * (1 - cos(pi * (0:win_taper-1) / win_taper));
taper_dn = 0.5 * (1 + cos(pi * (0:win_taper-1) / win_taper));

bb_up = zeros(1, N * sub_up);
for n = 1:N
    offset_bb = (n-1) * sub_size;
    sub = otfs_bb(offset_bb+1 : offset_bb+sub_size);
    sub_interp = interpft(sub, sub_up);
    if n > 1
        sub_interp(1:win_taper) = sub_interp(1:win_taper) .* taper_up;
    end
    if n < N
        sub_interp(end-win_taper+1:end) = sub_interp(end-win_taper+1:end) .* taper_dn;
    end
    bb_up((n-1)*sub_up+1 : n*sub_up) = sub_interp;
end

% 上变频到通带
[otfs_pb, ~] = upconvert(bb_up, fs_pb, fc);

%% ========== 4. 拼装通带帧 ========== %%
frame = [hfm_pb_pos, guard, hfm_pb_neg, guard, ...
         lfm_pb, guard, lfm_pb, guard, otfs_pb];

%% ========== 5. 生成基带HFM/LFM模板（供RX用）========== %%
t_hfm = (0:length(hfm_pb_pos)-1) / fs_pb;
if abs(f_hi - f_lo) < 1e-6
    phase_pos = 2*pi*f_lo*t_hfm;
    phase_neg = phase_pos;
else
    k_pos = f_lo*f_hi*params.T_hfm / (f_hi-f_lo);
    phase_pos = -2*pi*k_pos*log(1 - (f_hi-f_lo)/f_hi*t_hfm/params.T_hfm);
    k_neg = f_hi*f_lo*params.T_hfm / (f_lo-f_hi);
    phase_neg = -2*pi*k_neg*log(1 - (f_lo-f_hi)/f_lo*t_hfm/params.T_hfm);
end
hfm_bb_pos = exp(1j*(phase_pos - 2*pi*fc*t_hfm));
hfm_bb_neg = exp(1j*(phase_neg - 2*pi*fc*t_hfm));

t_lfm = (0:length(lfm_pb)-1) / fs_pb;
lfm_bb = exp(1j*2*pi*(-bw/2*t_lfm + 0.5*bw/params.T_lfm*t_lfm.^2));

%% ========== 6. 输出帧信息 ========== %%
L_hfm = length(hfm_pb_pos);
L_lfm = length(lfm_pb);
L_otfs_pb = length(otfs_pb);

% 各段起始位置（1-based）
pos = 1;
seg.hfm_pos_start = pos;       pos = pos + L_hfm;
seg.guard1_start = pos;         pos = pos + N_guard;
seg.hfm_neg_start = pos;       pos = pos + L_hfm;
seg.guard2_start = pos;         pos = pos + N_guard;
seg.lfm1_start = pos;          pos = pos + L_lfm;
seg.guard3_start = pos;         pos = pos + N_guard;
seg.lfm2_start = pos;          pos = pos + L_lfm;
seg.guard4_start = pos;         pos = pos + N_guard;
seg.otfs_start = pos;

info.hfm_pb_pos = hfm_pb_pos;
info.hfm_pb_neg = hfm_pb_neg;
info.lfm_pb = lfm_pb;
info.hfm_bb_pos = hfm_bb_pos;
info.hfm_bb_neg = hfm_bb_neg;
info.lfm_bb = lfm_bb;
info.fs_pb = fs_pb;
info.S_bias = params.T_hfm * fc / bw;
info.L_hfm = L_hfm;
info.L_lfm = L_lfm;
info.otfs_pb_len = L_otfs_pb;
info.N_guard = N_guard;
info.seg = seg;
info.params = params;

end
