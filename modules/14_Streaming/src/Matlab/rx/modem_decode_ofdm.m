function [bits, info] = modem_decode_ofdm(body_bb, sys, meta)
% 功能：OFDM RX（RRC匹配滤波 + 导频块信道估计 + CFO + Turbo MMSE-IC/BCJR）
% 版本：V2.0.0（去oracle：导频块本地重生成，无 all_cp_data / noise_var 依赖）
% 输入：
%   body_bb - 基带 body（已由外层完成 LFM 对齐 + Doppler 补偿）
%   sys     - 系统参数
%   meta    - 帧结构参数（不含 TX 数据）
%
% 依赖：
%   09_Waveform/match_filter
%   07_ChannelEstEq/{ch_est_omp, ch_est_bem}
%   02_ChannelCoding/{conv_encode, siso_decode_conv}
%   03_Interleaving/{random_interleave, random_deinterleave}
%   12_IterativeProc/soft_mapper

cfg   = sys.ofdm;
codec = sys.codec;

%% ---- 1. 关键参数 ----
blk_fft       = meta.blk_fft;
blk_cp        = meta.blk_cp;
N_blocks      = meta.N_blocks;
N_data_blocks = meta.N_data_blocks;
sym_per_block = meta.sym_per_block;
M_per_blk     = meta.M_per_blk;
M_total       = meta.M_total;
N_total_sym   = meta.N_total_sym;
N_shaped      = meta.N_shaped;
null_idx      = meta.null_idx;
data_idx      = meta.data_idx;
% 去oracle：不用 cfg.sym_delays，由导频块 LS 自动发现时延位置
L_max         = blk_cp;            % 最大时延扩展 = CP 长度
K_sparse_max  = 10;
ofdm_norm     = sqrt(blk_fft);

%% ---- 1b. 本地重生成导频块（seed=78，与 TX 一致）----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
rng_st = rng;
rng(meta.pilot_seed);
pilot_freq = zeros(1, blk_fft);
N_data_sc  = length(data_idx);
pilot_freq(data_idx) = constellation(randi(4, 1, N_data_sc));
rng(rng_st);
% 导频块时域（用于时域操作）
pilot_td = ifft(pilot_freq) * ofdm_norm;
pilot_cp = [pilot_td(end-blk_cp+1:end), pilot_td];

%% ---- 2. body 长度对齐 ----
body_bb = body_bb(:).';
if length(body_bb) < N_shaped
    body_bb = [body_bb, zeros(1, N_shaped - length(body_bb))];
elseif length(body_bb) > N_shaped
    body_bb = body_bb(1:N_shaped);
end

%% ---- 3. RRC 匹配滤波 + 符号定时 ----
[rx_filt, ~] = match_filter(body_bb, sys.sps, 'rrc', cfg.rolloff, cfg.span);

% 用导频块 CP 首段做定时
pilot_timing = pilot_cp(1:min(10, sym_per_block));
N_pilot = length(pilot_timing);
best_off = 0; best_corr = 0;
sym_off_corr_curve = zeros(1, sys.sps);
for off = 0 : sys.sps-1
    st = rx_filt(off+1 : sys.sps : end);
    if length(st) >= N_pilot
        c = abs(sum(st(1:N_pilot) .* conj(pilot_timing)));
        sym_off_corr_curve(off+1) = c;
        if c > best_corr
            best_corr = c;
            best_off  = off;
        end
    end
end
rx_sym_all = rx_filt(best_off+1 : sys.sps : end);
if length(rx_sym_all) > N_total_sym
    rx_sym_all = rx_sym_all(1:N_total_sym);
elseif length(rx_sym_all) < N_total_sym
    rx_sym_all = [rx_sym_all, zeros(1, N_total_sym - length(rx_sym_all))];
end

%% ---- 4. 空子载波 CFO 估计（对所有块执行，含导频块）----
N_null = length(null_idx);
cfo_est_hz = 0;
if N_null >= 2
    sc_spacing = sys.sym_rate / blk_fft;
    cfo_range = 3;
    cfo_grid = -cfo_range : 0.1 : cfo_range;
    E_null_grid = zeros(size(cfo_grid));
    for ci = 1:length(cfo_grid)
        cfo_hz = cfo_grid(ci);
        phase_corr = exp(-1j*2*pi*cfo_hz/sys.sym_rate*(0:blk_fft-1));
        for bk = 1:N_blocks
            blk_sym = rx_sym_all((bk-1)*sym_per_block+1:bk*sym_per_block);
            rx_nocp = blk_sym(blk_cp+1:end);
            Y_corr = fft(rx_nocp .* phase_corr);
            E_null_grid(ci) = E_null_grid(ci) + sum(abs(Y_corr(null_idx)).^2);
        end
    end
    [~, ci_best] = min(E_null_grid);
    cfo_coarse = cfo_grid(ci_best);
    cfo_fine = (cfo_coarse-0.15) : 0.01 : (cfo_coarse+0.15);
    E_null_fine = zeros(size(cfo_fine));
    for ci = 1:length(cfo_fine)
        cfo_hz = cfo_fine(ci);
        phase_corr = exp(-1j*2*pi*cfo_hz/sys.sym_rate*(0:blk_fft-1));
        for bk = 1:N_blocks
            blk_sym = rx_sym_all((bk-1)*sym_per_block+1:bk*sym_per_block);
            rx_nocp = blk_sym(blk_cp+1:end);
            Y_corr = fft(rx_nocp .* phase_corr);
            E_null_fine(ci) = E_null_fine(ci) + sum(abs(Y_corr(null_idx)).^2);
        end
    end
    [~, ci_best2] = min(E_null_fine);
    cfo_est_hz = cfo_fine(ci_best2);
    for bk = 1:N_blocks
        blk_start = (bk-1)*sym_per_block;
        n_vec = blk_start + (0:sym_per_block-1);
        rx_sym_all(blk_start+1:bk*sym_per_block) = ...
            rx_sym_all(blk_start+1:bk*sym_per_block) .* ...
            exp(-1j*2*pi*cfo_est_hz/sys.sym_rate*n_vec);
    end
end

%% ---- 5. 导频块信道估计 + 噪声估计 ----
% 导频块 = block 1：去 CP → FFT → 频域 LS
rx_pilot_blk = rx_sym_all(1:sym_per_block);
rx_pilot_nocp = rx_pilot_blk(blk_cp+1:end);
Y_pilot = fft(rx_pilot_nocp);

% 频域 LS 估计（仅 data_idx，null_idx 无信号）
H_ls = zeros(1, blk_fft);
H_ls(data_idx) = Y_pilot(data_idx) ./ (pilot_freq(data_idx) * ofdm_norm);

% 自动发现时延位置：IFFT → 峰值搜索（仅前 L_max 个抽头）
h_td_ls = ifft(H_ls);
h_cir = abs(h_td_ls(1:L_max));
thresh = 0.05 * max(h_cir);
detected = find(h_cir > thresh);
if length(detected) > K_sparse_max
    [~, si] = sort(h_cir(detected), 'descend');
    detected = sort(detected(si(1:K_sparse_max)));
end
if isempty(detected), detected = 1; end
sym_delays_est = detected - 1;  % 0-based
K_sparse = length(sym_delays_est);
eff_delays = mod(sym_delays_est, blk_fft);

h_td_sparse = zeros(1, blk_fft);
for p = 1:K_sparse
    h_td_sparse(eff_delays(p)+1) = h_td_ls(eff_delays(p)+1);
end
H_est_init = fft(h_td_sparse);

% 噪声估计：导频块频域残差（H 和 P 都已知）
Y_pred = H_est_init .* pilot_freq * ofdm_norm;
nv_eq = max(mean(abs(Y_pilot(data_idx) - Y_pred(data_idx)).^2), 1e-10);
P_sig_pilot = mean(abs(Y_pred(data_idx)).^2);  % 信号功率（供 SNR 估计）

% 初始化所有数据块的频域估计
H_est_blocks = cell(1, N_data_blocks);
for bi = 1:N_data_blocks
    H_est_blocks{bi} = H_est_init;
end

%% ---- 6. 数据块：去 CP + FFT ----
Y_freq_blocks = cell(1, N_data_blocks);
for bi = 1:N_data_blocks
    blk_idx = bi + 1;
    blk_sym = rx_sym_all((blk_idx-1)*sym_per_block+1 : blk_idx*sym_per_block);
    rx_nocp = blk_sym(blk_cp+1:end);
    Y_freq_blocks{bi} = fft(rx_nocp);
end

%% ---- 7. Turbo 均衡（逐子载波 MMSE-IC + BCJR，仅数据块）----
turbo_iter    = cfg.turbo_iter;
H_cur_blocks  = H_est_blocks;
x_bar_freq_blks = cell(1, N_data_blocks);
var_x_blks    = ones(1, N_data_blocks);
for bi = 1:N_data_blocks
    x_bar_freq_blks{bi} = zeros(1, blk_fft);
end
La_dec_info   = [];
bits_decoded  = [];
eq_syms_iters = cell(1, turbo_iter);

for titer = 1:turbo_iter
    LLR_all = zeros(1, M_total);
    eq_syms_t = [];
    for bi = 1:N_data_blocks
        H_eff    = H_cur_blocks{bi} * ofdm_norm;
        var_x_bi = var_x_blks(bi);

        G_k = var_x_bi * conj(H_eff) ./ (var_x_bi * abs(H_eff).^2 + nv_eq);
        Residual = Y_freq_blocks{bi} - H_eff .* x_bar_freq_blks{bi};
        X_hat_freq = x_bar_freq_blks{bi} + G_k .* Residual;

        mu_k = real(G_k .* H_eff);
        mu_k = max(mu_k, 1e-8);
        nv_k = mu_k .* (1 - mu_k) * var_x_bi + abs(G_k).^2 * nv_eq;
        nv_k = max(nv_k, 1e-10);

        scale_k = 2 * mu_k ./ nv_k;
        Lp_I = -scale_k .* sqrt(2) .* real(X_hat_freq);
        Lp_Q = -scale_k .* sqrt(2) .* imag(X_hat_freq);
        Lp_I_data = Lp_I(data_idx);
        Lp_Q_data = Lp_Q(data_idx);
        Le_eq_blk = zeros(1, M_per_blk);
        Le_eq_blk(1:2:end) = Lp_I_data;
        Le_eq_blk(2:2:end) = Lp_Q_data;
        LLR_all((bi-1)*M_per_blk+1 : bi*M_per_blk) = Le_eq_blk;
        eq_syms_t = [eq_syms_t, X_hat_freq(data_idx)]; %#ok<AGROW>
    end
    eq_syms_iters{titer} = eq_syms_t;

    Le_eq_deint = random_deinterleave(LLR_all, meta.perm_all);
    Le_eq_deint = max(min(Le_eq_deint, 30), -30);
    [~, Lpost_info, Lpost_coded] = siso_decode_conv( ...
        Le_eq_deint, La_dec_info, codec.gen_polys, codec.constraint_len);
    bits_decoded = double(Lpost_info > 0);

    if titer < turbo_iter
        Lpost_inter = random_interleave(Lpost_coded, codec.interleave_seed);
        if length(Lpost_inter) < M_total
            Lpost_inter = [Lpost_inter, zeros(1, M_total - length(Lpost_inter))]; %#ok<AGROW>
        else
            Lpost_inter = Lpost_inter(1:M_total);
        end

        for bi = 1:N_data_blocks
            coded_blk = Lpost_inter((bi-1)*M_per_blk+1 : bi*M_per_blk);
            [x_bar_data, var_x_raw] = soft_mapper(coded_blk, 'qpsk');
            var_x_blks(bi) = max(var_x_raw, nv_eq);
            x_bar_freq_full = zeros(1, blk_fft);
            x_bar_freq_full(data_idx) = x_bar_data;
            x_bar_freq_blks{bi} = x_bar_freq_full;
        end

        % DD 信道重估计（iter >= 2，软符号置信度足够时）
        if titer >= 2
            for bi = 1:N_data_blocks
                if var_x_blks(bi) < 0.5
                    X_bar_eff = x_bar_freq_blks{bi} * ofdm_norm;
                    H_dd_raw = Y_freq_blocks{bi} .* conj(X_bar_eff) ./ (abs(X_bar_eff).^2 + nv_eq);
                    h_dd = ifft(H_dd_raw);
                    h_dd_sparse = zeros(1, blk_fft);
                    for p = 1:K_sparse
                        h_dd_sparse(eff_delays(p)+1) = h_dd(eff_delays(p)+1);
                    end
                    H_cur_blocks{bi} = fft(h_dd_sparse);
                end
            end
        end
    end
end

%% ---- 8. 截取信息比特 ----
N_info = meta.N_info;
if length(bits_decoded) >= N_info
    bits = bits_decoded(1:N_info);
else
    bits = [bits_decoded, zeros(1, N_info - length(bits_decoded))];
end

%% ---- 9. info ----
info = struct();
% 频域 SNR → 信道 SNR：减去 RRC 匹配滤波处理增益
% 符号域 SNR（P_sig_pilot/nv_eq 已是符号域比值；同 SC-FDE V2.1.0 修复）
info.estimated_snr    = 10*log10(max(P_sig_pilot / nv_eq, 1e-6));
abs_llr = abs(Lpost_info);
info.estimated_ber    = mean(0.5 * exp(-abs_llr));
info.turbo_iter       = turbo_iter;
% 统一收敛判据（decode_convergence helper，三选一 — 2026-04-19 HIGH-1 修复）
[info.convergence_flag, conv_extra] = decode_convergence(Lpost_info, [], []);
info.frac_confident = conv_extra.frac_confident;
info.H_est_block1     = H_est_init;
info.noise_var        = nv_eq;
info.sym_offset       = best_off;
info.sym_off_best     = best_off;
info.sym_off_corr     = sym_off_corr_curve;
info.sym_off_best_val = best_corr;

pre_eq_syms = [];
for bi = 1:N_data_blocks
    blk_idx = bi + 1;
    blk = rx_sym_all((blk_idx-1)*sym_per_block + blk_cp + 1 : blk_idx*sym_per_block);
    pre_eq_syms = [pre_eq_syms, blk]; %#ok<AGROW>
end
info.pre_eq_syms = pre_eq_syms;
info.post_eq_syms = eq_syms_iters{end};
info.eq_syms_iters = eq_syms_iters;

end
