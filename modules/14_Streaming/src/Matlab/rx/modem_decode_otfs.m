function [bits, info] = modem_decode_otfs(body_bb, sys, meta)
% 功能：OTFS RX（OTFS 解调 + DD 域信道估计 + 导频去除 + Turbo 均衡 → 译码）
% 版本：V1.0.0（P3.3 从 13_SourceCode/tests/OTFS/test_otfs_timevarying.m 抽取）
% 输入：
%   body_bb - 基带 body（已由外层完成对齐 + Doppler 补偿；长度 ≈ meta.N_shaped）
%   sys     - 系统参数（用 sys.codec, sys.otfs）
%   meta    - TX 侧 modem_encode_otfs 产出
% 输出：
%   bits - 1×N_info 解码信息比特
%   info - struct（含统一 API 字段 + 诊断）
%
% 依赖：
%   06_MultiCarrier/otfs_demodulate
%   07_ChannelEstEq/{ch_est_otfs_dd, eq_otfs_lmmse, soft_mapper}
%   02_ChannelCoding/siso_decode_conv
%   03_Interleaving/{random_deinterleave, random_interleave}

cfg   = sys.otfs;
codec = sys.codec;

%% ---- 1. 关键参数 ----
N            = meta.N;
M            = meta.M;
cp_len       = meta.cp_len;
N_shaped     = meta.N_shaped;
data_indices = meta.data_indices;
pilot_info   = meta.pilot_info;
pilot_config = meta.pilot_config;
guard_mask   = meta.guard_mask;
N_data_slots = meta.N_data_slots;
M_coded      = meta.M_coded;
turbo_iter   = cfg.turbo_iter;

%% ---- 2. body 长度对齐 ----
body_bb = body_bb(:).';
if length(body_bb) < N_shaped
    body_bb = [body_bb, zeros(1, N_shaped - length(body_bb))];
elseif length(body_bb) > N_shaped
    body_bb = body_bb(1:N_shaped);
end

%% ---- 3. OTFS 解调 ----
[Y_dd, ~] = otfs_demodulate(body_bb, N, M, cp_len, 'dft');

%% ---- 4. 噪声方差盲估计（guard 区域）----
guard_indices = find(guard_mask);
if ~isempty(guard_indices)
    nv = max(mean(abs(Y_dd(guard_indices)).^2), 1e-8);
else
    nv = max(0.1 * var(Y_dd(:)), 1e-8);
end

%% ---- 5. DD 域信道估计 ----
[h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M);

%% ---- 6. 导频贡献去除 ----
Y_dd_eq = Y_dd;
if ~isempty(pilot_info.positions)
    pk_pos = pilot_info.positions(1,1);
    pl_pos = pilot_info.positions(1,2);
    pv_val = pilot_info.values(1);
else
    pk_pos = ceil(N/2);
    pl_pos = ceil(M/2);
    pv_val = 1;
end

switch cfg.pilot_mode
    case 'impulse'
        for pp = 1:path_info.num_paths
            kk = mod(pk_pos - 1 + path_info.doppler_idx(pp), N) + 1;
            ll = mod(pl_pos - 1 + path_info.delay_idx(pp), M) + 1;
            Y_dd_eq(kk, ll) = Y_dd_eq(kk, ll) - path_info.gain(pp) * pv_val;
        end
    case 'sequence'
        for pp = 1:path_info.num_paths
            dl_p = path_info.delay_idx(pp);
            dk_p = path_info.doppler_idx(pp);
            for pc_i = 1:size(pilot_info.positions, 1)
                pk_c = pilot_info.positions(pc_i, 1);
                pl_c = pilot_info.positions(pc_i, 2);
                pv_c = pilot_info.values(pc_i);
                kk = mod(pk_c - 1 + dk_p, N) + 1;
                ll = mod(pl_c - 1 + dl_p, M) + 1;
                Y_dd_eq(kk, ll) = Y_dd_eq(kk, ll) - path_info.gain(pp) * pv_c;
            end
        end
    case 'superimposed'
        if isfield(pilot_info, 'pilot_pattern')
            h_origin = zeros(N, M);
            for p_idx = 1:path_info.num_paths
                dk_p = path_info.doppler_idx(p_idx);
                dl_p = path_info.delay_idx(p_idx);
                kk_o = mod(dk_p, N) + 1;
                ll_o = mod(dl_p, M) + 1;
                h_origin(kk_o, ll_o) = path_info.gain(p_idx);
            end
            Y_pilot_contrib = ifft2(fft2(pilot_info.pilot_pattern) .* fft2(h_origin));
            Y_dd_eq = Y_dd - Y_pilot_contrib;
        end
end

%% ---- 7. 手写 Turbo（turbo_equalizer_otfs 不支持 pilot grid，需手动处理 data_indices）----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
perm_all = meta.perm_all;
prior_mean = [];
prior_var  = [];
bits_decoded = [];
Lpost_info = [];
post_eq_syms_dd = [];

for titer = 1:turbo_iter
    % 7a. LMMSE 均衡（全 NxM 格点）
    [~, ~, x_mean_dd, eq_info_t] = eq_otfs_lmmse(Y_dd_eq, h_dd, path_info, ...
        N, M, nv, 1, constellation, prior_mean, prior_var);
    nv_llr = max(eq_info_t.nv_post, 1e-8);

    % 7b. 仅从 data_indices 提取软符号 → LLR（列优先线性索引直接取）
    x_data_soft = x_mean_dd(data_indices);
    LLR_eq = zeros(1, M_coded);
    LLR_eq(1:2:end) = -2*sqrt(2) * real(x_data_soft(:).') / nv_llr;
    LLR_eq(2:2:end) = -2*sqrt(2) * imag(x_data_soft(:).') / nv_llr;
    LLR_eq = max(min(LLR_eq, 30), -30);

    % 7c. 解交织 + BCJR（用编码器的 perm_all，长度 = M_coded）
    Le_deint = random_deinterleave(LLR_eq, perm_all);
    [~, Lpost_info, Lpost_coded] = siso_decode_conv(Le_deint, [], ...
        codec.gen_polys, codec.constraint_len, codec.decode_mode);
    bits_decoded = double(Lpost_info > 0);

    % 7d. 反馈：soft_mapper → 填回 NxM DD 格点（列优先）
    if titer < turbo_iter
        Lp_inter = random_interleave(Lpost_coded, codec.interleave_seed);
        if length(Lp_inter) < M_coded
            Lp_inter = [Lp_inter, zeros(1, M_coded - length(Lp_inter))]; %#ok<AGROW>
        else
            Lp_inter = Lp_inter(1:M_coded);
        end
        [x_bar_data, var_x_raw] = soft_mapper(Lp_inter, 'qpsk');
        var_x = max(var_x_raw, nv);

        prior_mean = zeros(N, M);
        prior_mean(data_indices) = x_bar_data;
        prior_var = zeros(N, M);
        prior_var(data_indices) = var_x;
    end
end
post_eq_syms_dd = x_mean_dd(data_indices);

%% ---- 8. 截取信息比特 ----
N_info = meta.N_info;
if length(bits_decoded) >= N_info
    bits = bits_decoded(1:N_info);
else
    bits = [bits_decoded, zeros(1, N_info - length(bits_decoded))];
end

%% ---- 9. info ----
med_llr = median(abs(Lpost_info));
info = struct();
% 信道总功率 / guard 区噪声
P_ch_otfs = sum(abs(path_info.gain).^2);
info.estimated_snr    = 10*log10(max(P_ch_otfs / nv, 1e-6));
info.estimated_ber    = mean(0.5 * exp(-abs(Lpost_info)));
info.turbo_iter       = turbo_iter;
% 统一收敛判据（decode_convergence helper，三选一 — 2026-04-19 HIGH-1 修复）
[info.convergence_flag, conv_extra] = decode_convergence(Lpost_info, [], []);
info.frac_confident = conv_extra.frac_confident;
info.noise_var        = nv;
info.h_dd             = h_dd;
info.path_info        = path_info;
% 同步诊断（sync tab 用）：DD 域路径快照
info.dd_path_info = struct( ...
    'num_paths',   path_info.num_paths, ...
    'delay_idx',   path_info.delay_idx, ...
    'doppler_idx', path_info.doppler_idx, ...
    'gain',        path_info.gain);

info.pre_eq_syms  = Y_dd(data_indices).';
info.post_eq_syms = post_eq_syms_dd(:).';

end
