function [bits, info] = modem_decode_otfs(body_bb, sys, meta)
% 功能：OTFS RX（RRC 匹配滤波 + 符号定时 + OTFS 解调 + DD 域信道估计 + Turbo）
% 版本：V2.0.0（2026-04-19 采样率桥接：body_bb @ fs 匹配滤波后下采样回 sym_rate）
% 输入：
%   body_bb - 基带 body **@ fs**（V1.0 假设 @ sym_rate，V2.0 与 modem_encode V2.0 对齐）
%   sys     - 系统参数（用 sys.codec, sys.otfs, sys.sps）
%   meta    - TX 侧 modem_encode_otfs V2.0 产出（含 .sps, .rolloff, .span, .N_otfs_sym）
% 输出：
%   bits - 1×N_info 解码信息比特
%   info - struct（含统一 API 字段 + 诊断）
%
% 依赖：
%   09_Waveform/match_filter (V2.0 新增)
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
N_otfs_sym   = meta.N_otfs_sym;
data_indices = meta.data_indices;
pilot_info   = meta.pilot_info;
pilot_config = meta.pilot_config;
guard_mask   = meta.guard_mask;
N_data_slots = meta.N_data_slots;
M_coded      = meta.M_coded;
turbo_iter   = cfg.turbo_iter;
sps          = meta.sps;
rolloff      = meta.rolloff;
span         = meta.span;

%% ---- 2. body 长度对齐（@ fs）----
body_bb = body_bb(:).';
if length(body_bb) < N_shaped
    body_bb = [body_bb, zeros(1, N_shaped - length(body_bb))];
elseif length(body_bb) > N_shaped
    body_bb = body_bb(1:N_shaped);
end

%% ---- 3. RRC 匹配滤波 + 符号定时（V2.0 下采样桥接）----
[rx_filt, ~] = match_filter(body_bb, sps, 'rrc', rolloff, span);

% 符号定时：用 pilot-only 帧的 OTFS 时域波形作本地参考
pilot_only_dd = zeros(N, M);
for k = 1:size(pilot_info.positions, 1)
    kk = pilot_info.positions(k, 1);
    ll = pilot_info.positions(k, 2);
    pilot_only_dd(kk, ll) = pilot_info.values(k);
end
[pilot_ref_sym, ~] = otfs_modulate(pilot_only_dd, N, M, cp_len, 'dft');
pilot_ref_sym = pilot_ref_sym(:).';
N_ref = min(64, length(pilot_ref_sym));   % 前 64 个参考符号

best_off = 0; best_corr = 0;
sym_off_corr = zeros(1, sps);
for off = 0:sps-1
    st = rx_filt(off+1 : sps : end);
    if length(st) >= N_ref
        c = abs(sum(st(1:N_ref) .* conj(pilot_ref_sym(1:N_ref))));
        sym_off_corr(off+1) = c;
        if c > best_corr
            best_corr = c;
            best_off = off;
        end
    end
end
rx_sym = rx_filt(best_off+1 : sps : end);
% 长度对齐到 N_otfs_sym（OTFS 符号域）
if length(rx_sym) < N_otfs_sym
    rx_sym = [rx_sym, zeros(1, N_otfs_sym - length(rx_sym))];
elseif length(rx_sym) > N_otfs_sym
    rx_sym = rx_sym(1:N_otfs_sym);
end

%% ---- 4. OTFS 解调（输入 rx_sym @ sym_rate）----
[Y_dd, ~] = otfs_demodulate(rx_sym, N, M, cp_len, 'dft');

%% ---- 5. 噪声方差盲估计（guard 区域）----
guard_indices = find(guard_mask);
if ~isempty(guard_indices)
    nv = max(mean(abs(Y_dd(guard_indices)).^2), 1e-8);
else
    nv = max(0.1 * var(Y_dd(:)), 1e-8);
end

%% ---- 6. DD 域信道估计（按 pilot_mode 分派）----
switch cfg.pilot_mode
    case 'impulse'
        [h_dd, path_info] = ch_est_otfs_dd(Y_dd, pilot_info, N, M);
    case 'sequence'
        [h_dd, path_info] = ch_est_otfs_zc(Y_dd, pilot_info, N, M);
    case 'superimposed'
        [h_dd, path_info] = ch_est_otfs_superimposed(Y_dd, pilot_info, N, M);
    otherwise
        error('modem_decode_otfs: 未知 pilot_mode %s', cfg.pilot_mode);
end

%% ---- 7. 导频贡献去除 ----
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

%% ---- 8. 手写 Turbo（turbo_equalizer_otfs 不支持 pilot grid，需手动处理 data_indices）----
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

%% ---- 9. 截取信息比特 ----
N_info = meta.N_info;
if length(bits_decoded) >= N_info
    bits = bits_decoded(1:N_info);
else
    bits = [bits_decoded, zeros(1, N_info - length(bits_decoded))];
end

%% ---- 10. info ----
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
% 同步诊断（sync tab 用）：DD 域路径快照 + 符号定时
info.dd_path_info = struct( ...
    'num_paths',   path_info.num_paths, ...
    'delay_idx',   path_info.delay_idx, ...
    'doppler_idx', path_info.doppler_idx, ...
    'gain',        path_info.gain);
info.sym_off_best     = best_off;
info.sym_off_corr     = sym_off_corr;
info.sym_off_best_val = best_corr;

info.pre_eq_syms  = Y_dd(data_indices).';
info.post_eq_syms = post_eq_syms_dd(:).';

end
