function [otfs_bb, sync_info] = frame_parse_otfs(rx_pb, info)
% 功能：OTFS通带帧解析——两级同步 + 多普勒补偿 + 数据提取
% 版本：V2.0.0 — 双HFM粗同步+LFM精定时+重采样补偿
% 输入：
%   rx_pb      - 接收通带信号 (1×L)
%   info       - 帧信息结构体（由 frame_assemble_otfs V2.0 生成）
% 输出：
%   otfs_bb    - 基带OTFS数据段 (1×L_otfs, 含per-sub-block CP)
%   sync_info  - 同步信息
%     .alpha_est    : 多普勒因子估计
%     .tau_coarse   : 双HFM粗定时（采样点）
%     .tau_fine     : LFM精确定时（采样点）
%     .sync_quality : 同步质量
%     .data_start   : 数据段起始位置
%
% 两级同步流程:
%   Level 1: downconvert → sync_dual_hfm(HFM+,HFM-) → α_est + τ_coarse
%   Level 2: comp_resample_spline(α_est) → sync_detect(LFM2) → τ_fine
%   提取: OTFS通带段 → downconvert+降采样 → 基带OTFS

%% ========== 1. 参数提取 ========== %%
p = info.params;
fs_pb = info.fs_pb;
fc = p.fc; bw = p.bw;
N = p.N; M = p.M; cp_len = p.cp_len; sps = p.sps;

%% ========== 2. 下变频到基带（宽LPF保留HFM完整带宽） ========== %%
% LPF截止 = bw (HFM带宽)，保证HFM能量完整通过
[bb_raw, ~] = downconvert(rx_pb, fs_pb, fc, bw);

%% ========== 3. Level 1: 迭代式双HFM粗同步 + 多普勒估计 ========== %%
% 鸡生蛋问题: 下变频后基带HFM有残余exp(j·2π·fc·α·t)相位, 估计α需已知α
% 解决: 迭代——α_0=0 → 补偿 → 重估Δα → 累加 → 收敛
sp_dual = struct('S_bias', info.S_bias, ...
                 'alpha_max', 0.02, ...
                 'search_win', length(bb_raw), ...
                 'sep_samples', info.L_hfm + info.N_guard, ...
                 'frame_gap', info.N_guard);

alpha_est = 0;
N_iter = 3;
t_bb = (0:length(bb_raw)-1) / fs_pb;
for iter = 1:N_iter
    if abs(alpha_est) > 1e-8
        bb_iter = comp_resample_spline(bb_raw, alpha_est);
        L_iter = min(length(bb_iter), length(t_bb));
        bb_iter = bb_iter(1:L_iter) .* exp(-1j * 2*pi * fc * alpha_est * t_bb(1:L_iter));
    else
        bb_iter = bb_raw;
    end
    [tau_coarse, alpha_delta, qual, dual_info] = sync_dual_hfm( ...
        bb_iter, info.hfm_bb_pos, info.hfm_bb_neg, fs_pb, sp_dual);
    alpha_est = alpha_est + alpha_delta;
    if abs(alpha_delta) < 1e-6, break; end
end

%% ========== 4. 最终补偿 ========== %%
if abs(alpha_est) > 1e-8
    bb_comp = comp_resample_spline(bb_raw, alpha_est);
    L_cmp = min(length(bb_comp), length(t_bb));
    bb_comp = bb_comp(1:L_cmp) .* exp(-1j * 2*pi * fc * alpha_est * t_bb(1:L_cmp));
else
    bb_comp = bb_raw;
end

%% ========== 5. Level 2: LFM精确定时（基带） ========== %%
expected_lfm2_offset = 2*info.L_hfm + 2*info.N_guard + info.L_lfm + info.N_guard;
search_start = max(1, tau_coarse + expected_lfm2_offset - info.L_lfm);
search_end = min(length(bb_comp), tau_coarse + expected_lfm2_offset + 2*info.L_lfm);

if search_start < search_end
    search_seg = bb_comp(search_start : search_end);
    [lfm_pos_rel, lfm_peak, ~] = sync_detect(search_seg, info.lfm_bb, 0.3);
    tau_fine = search_start + lfm_pos_rel - 1;
else
    [tau_fine, lfm_peak, ~] = sync_detect(bb_comp, info.lfm_bb, 0.3);
end

%% ========== 6. 提取OTFS基带段（多普勒+CFO补偿后）========== %%
otfs_pb_start = tau_fine + info.L_lfm + info.N_guard;
otfs_pb_end = otfs_pb_start + info.otfs_pb_len - 1;

if otfs_pb_end > length(bb_comp)
    bb_otfs_up = zeros(1, info.otfs_pb_len);
    available = length(bb_comp) - otfs_pb_start + 1;
    if available > 0
        bb_otfs_up(1:available) = bb_comp(otfs_pb_start : otfs_pb_start+available-1);
    end
else
    bb_otfs_up = bb_comp(otfs_pb_start : otfs_pb_end);
end

%% ========== 7. 逐子块FFT降采样到OTFS基带率 ========== %%
sub_size = M + cp_len;
sub_up = sub_size * sps;
N_sub = N;

otfs_bb = zeros(1, N_sub * sub_size);
for n = 1:N_sub
    offset_up = (n-1) * sub_up;
    if offset_up + sub_up <= length(bb_otfs_up)
        sub_raw = bb_otfs_up(offset_up+1 : offset_up+sub_up);
    else
        sub_raw = [bb_otfs_up(offset_up+1:end), zeros(1, sub_up-(length(bb_otfs_up)-offset_up))];
    end
    sub_down = interpft(sub_raw, sub_size);
    otfs_bb((n-1)*sub_size+1 : n*sub_size) = sub_down;
end

%% ========== 8. 同步信息输出 ========== %%
sync_info.alpha_est = alpha_est;
sync_info.tau_coarse = tau_coarse;
sync_info.tau_fine = tau_fine;
sync_info.sync_quality = qual;
sync_info.data_start = otfs_pb_start;
sync_info.lfm_peak = lfm_peak;

end
