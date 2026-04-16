function [bits, info] = modem_decode_scfde(body_bb, sys, meta)
% 功能：SC-FDE RX（RRC 匹配滤波 + 符号定时 + 信道估计 + Turbo LMMSE-IC/BCJR）
% 版本：V1.0.0（P3.1 从 13_SourceCode/tests/SC-FDE/test_scfde_timevarying.m 抽取）
% 输入：
%   body_bb - 基带 body（已由外层完成 LFM 对齐 + Doppler 补偿；长度 ≈ meta.N_shaped）
%   sys     - 系统参数（用 sys.codec, sys.scfde, sys.sps, sys.sym_rate）
%   meta    - TX 侧 modem_encode_scfde 产出（含 all_cp_data / perm_all / 块参数）
% 输出：
%   bits - 1×N_info 解码信息比特
%   info - struct（含统一 API 字段 + 诊断）
%
% 依赖：
%   09_Waveform/match_filter
%   07_ChannelEstEq/{ch_est_gamp, ch_est_bem, eq_mmse_ic_fde, soft_demapper, soft_mapper}
%   02_ChannelCoding/siso_decode_conv
%   03_Interleaving/random_deinterleave, random_interleave
%
% 噪声：若 meta.noise_var 存在则使用，否则用 RRC 后残差中位数估计

cfg   = sys.scfde;
codec = sys.codec;

%% ---- 1. 关键参数 ----
blk_fft       = meta.blk_fft;
blk_cp        = meta.blk_cp;
N_blocks      = meta.N_blocks;
sym_per_block = meta.sym_per_block;
M_per_blk     = meta.M_per_blk;
M_total       = meta.M_total;
N_total_sym   = meta.N_total_sym;
N_shaped      = meta.N_shaped;
sym_delays    = cfg.sym_delays;
L_h           = max(sym_delays) + 1;
K_sparse      = length(sym_delays);

%% ---- 2. body 长度对齐 ----
body_bb = body_bb(:).';
if length(body_bb) < N_shaped
    body_bb = [body_bb, zeros(1, N_shaped - length(body_bb))];
elseif length(body_bb) > N_shaped
    body_bb = body_bb(1:N_shaped);
end

%% ---- 3. RRC 匹配滤波 + 符号定时 ----
[rx_filt, ~] = match_filter(body_bb, sys.sps, 'rrc', cfg.rolloff, cfg.span);

% 用 pilot_sym（TX 首 10 符号）做最大相关符号定时
pilot = meta.pilot_sym;
N_pilot = length(pilot);
best_off = 0; best_corr = 0;
for off = 0 : sys.sps-1
    st = rx_filt(off+1 : sys.sps : end);
    if length(st) >= N_pilot
        c = abs(sum(st(1:N_pilot) .* conj(pilot)));
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

%% ---- 4. 噪声方差估计 ----
if isfield(meta, 'noise_var') && ~isempty(meta.noise_var)
    nv_eq = max(meta.noise_var, 1e-10);
else
    % 用末尾 CP 段（已含噪+衰落）的信号方差 × 0.1 作粗估（保守）
    tail = rx_sym_all(end-blk_cp+1:end);
    nv_eq = max(0.1 * var(tail), 1e-10);
end

%% ---- 5. 信道估计 ----
eff_delays = mod(sym_delays, blk_fft);   % 同步后 offset=0

if strcmpi(cfg.fading_type, 'static')
    % --- GAMP：用第 1 块 CP 段 ---
    usable = blk_cp;
    T_mat = zeros(usable, L_h);
    tx_blk1 = meta.all_cp_data(1:sym_per_block);
    for col = 1:L_h
        for row = col:usable
            T_mat(row, col) = tx_blk1(row - col + 1);
        end
    end
    y_train = rx_sym_all(1:usable).';
    [h_gamp_vec, ~] = ch_est_gamp(y_train, T_mat, L_h, 50, nv_eq);
    h_td_est = zeros(1, blk_fft);
    for p = 1:K_sparse
        if sym_delays(p) + 1 <= L_h
            h_td_est(eff_delays(p)+1) = h_gamp_vec(sym_delays(p)+1);
        end
    end
    H_est_blocks = cell(1, N_blocks);
    for bi = 1:N_blocks
        H_est_blocks{bi} = fft(h_td_est);
    end
else
    % --- BEM(DCT) 跨块 ---
    obs_y = []; obs_x = []; obs_n = [];
    for bi = 1:N_blocks
        blk_start = (bi-1)*sym_per_block;
        for kk = max(sym_delays)+1 : blk_cp
            n = blk_start + kk;
            x_vec = zeros(1, K_sparse);
            for pp = 1:K_sparse
                idx = n - sym_delays(pp);
                if idx >= 1 && idx <= N_total_sym
                    x_vec(pp) = meta.all_cp_data(idx);
                end
            end
            if any(x_vec ~= 0) && n <= length(rx_sym_all)
                obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
                obs_x = [obs_x; x_vec]; %#ok<AGROW>
                obs_n(end+1) = n; %#ok<AGROW>
            end
        end
    end
    bem_opts = struct('Q_mode', 'auto', 'lambda_scale', 1.0);
    [h_tv_bem, ~, ~] = ch_est_bem(obs_y(:), obs_x, obs_n(:), N_total_sym, ...
        sym_delays, cfg.fd_hz, sys.sym_rate, nv_eq, 'dct', bem_opts);
    H_est_blocks = cell(1, N_blocks);
    for bi = 1:N_blocks
        blk_mid = (bi-1)*sym_per_block + round(sym_per_block/2);
        blk_mid = max(1, min(blk_mid, N_total_sym));
        h_td_est = zeros(1, blk_fft);
        for p = 1:K_sparse
            h_td_est(eff_delays(p)+1) = h_tv_bem(p, blk_mid);
        end
        H_est_blocks{bi} = fft(h_td_est);
    end
end

%% ---- 6. 分块去 CP + FFT ----
Y_freq_blocks = cell(1, N_blocks);
for bi = 1:N_blocks
    blk_sym = rx_sym_all((bi-1)*sym_per_block+1 : bi*sym_per_block);
    rx_nocp = blk_sym(blk_cp+1:end);
    Y_freq_blocks{bi} = fft(rx_nocp);
end

%% ---- 7. 跨块 Turbo：LMMSE-IC ⇌ BCJR ----
turbo_iter = cfg.turbo_iter;
x_bar_blks = cell(1, N_blocks);
var_x_blks = ones(1, N_blocks);
H_cur_blocks = H_est_blocks;
for bi = 1:N_blocks, x_bar_blks{bi} = zeros(1, blk_fft); end
La_dec_info   = [];
bits_decoded  = [];
iter_done     = 0;
last_abs_llr  = 0;
converged     = 0;

x_tilde_blks = cell(1, N_blocks);   % 保留每块均衡后符号（用于星座图）

for titer = 1:turbo_iter
    % Step 1: per-block LMMSE-IC → soft symbols → LLR
    LLR_all = zeros(1, M_total);
    for bi = 1:N_blocks
        [x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq_blocks{bi}, ...
            H_cur_blocks{bi}, x_bar_blks{bi}, var_x_blks(bi), nv_eq);
        Le_eq_blk = soft_demapper(x_tilde, mu, nv_tilde, zeros(1, M_per_blk), 'qpsk');
        LLR_all((bi-1)*M_per_blk+1 : bi*M_per_blk) = Le_eq_blk;
        x_tilde_blks{bi} = x_tilde;
    end

    % Step 2: 跨块解交织 + BCJR
    Le_eq_deint = random_deinterleave(LLR_all, meta.perm_all);
    Le_eq_deint = max(min(Le_eq_deint, 30), -30);
    [~, Lpost_info, Lpost_coded] = siso_decode_conv( ...
        Le_eq_deint, La_dec_info, codec.gen_polys, codec.constraint_len);
    bits_decoded = double(Lpost_info > 0);
    iter_done = titer;

    % 收敛判据：|LLR| 中位数 稳定且 > 5
    cur_abs = median(abs(Lpost_info));
    if titer > 1 && cur_abs > 5 && abs(cur_abs - last_abs_llr) < 0.1
        converged = 1;
        break;
    end
    last_abs_llr = cur_abs;

    % Step 3: 反馈 + DD 信道重估（titer >= 2 且置信足够）
    if titer < turbo_iter
        Lpost_inter = random_interleave(Lpost_coded, codec.interleave_seed);
        if length(Lpost_inter) < M_total
            Lpost_inter = [Lpost_inter, zeros(1, M_total - length(Lpost_inter))];
        else
            Lpost_inter = Lpost_inter(1:M_total);
        end
        for bi = 1:N_blocks
            coded_blk = Lpost_inter((bi-1)*M_per_blk+1 : bi*M_per_blk);
            [x_bar_blks{bi}, var_x_raw] = soft_mapper(coded_blk, 'qpsk');
            var_x_blks(bi) = max(var_x_raw, nv_eq);

            if titer >= 2 && var_x_blks(bi) < 0.5
                X_bar = fft(x_bar_blks{bi});
                H_dd_raw = Y_freq_blocks{bi} .* conj(X_bar) ./ (abs(X_bar).^2 + nv_eq);
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

%% ---- 8. 截取信息比特 ----
N_info = meta.N_info;
if length(bits_decoded) >= N_info
    bits = bits_decoded(1:N_info);
else
    bits = [bits_decoded, zeros(1, N_info - length(bits_decoded))];
end

%% ---- 9. info ----
info = struct();
info.estimated_snr    = 10*log10(max(mean(abs(rx_sym_all).^2) / nv_eq, 1e-6));
% 用 |LLR| 做 BER 估计
abs_llr = abs(Lpost_info);
info.estimated_ber    = mean(0.5 * exp(-abs_llr));
info.turbo_iter       = iter_done;
info.convergence_flag = converged;
info.H_est_block1     = H_est_blocks{1};
info.noise_var        = nv_eq;
info.sym_offset       = best_off;

% --- 星座图数据（UI 用）---
% 均衡前：rx_sym_all 中各块去 CP 后的数据段
pre_eq_syms = [];
for bi = 1:N_blocks
    blk = rx_sym_all((bi-1)*sym_per_block + blk_cp + 1 : bi*sym_per_block);
    pre_eq_syms = [pre_eq_syms, blk]; %#ok<AGROW>
end
info.pre_eq_syms = pre_eq_syms;
% 均衡后：x_tilde 拼接（最后一轮 Turbo 输出）
post_eq_syms = [];
for bi = 1:N_blocks
    if ~isempty(x_tilde_blks{bi})
        post_eq_syms = [post_eq_syms, x_tilde_blks{bi}(:).']; %#ok<AGROW>
    end
end
info.post_eq_syms = post_eq_syms;
% TX 参考符号（去 CP）
tx_ref = [];
for bi = 1:N_blocks
    blk = meta.all_cp_data((bi-1)*sym_per_block + blk_cp + 1 : bi*sym_per_block);
    tx_ref = [tx_ref, blk]; %#ok<AGROW>
end
info.tx_ref_syms = tx_ref;

end
