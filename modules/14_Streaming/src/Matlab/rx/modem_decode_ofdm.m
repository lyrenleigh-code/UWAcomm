function [bits, info] = modem_decode_ofdm(body_bb, sys, meta)
% 功能：OFDM RX（RRC 匹配滤波 + 符号定时 + [CFO] + 信道估计 + Turbo MMSE-IC/BCJR）
% 版本：V1.0.0（P3.2 从 13_SourceCode/tests/OFDM/test_ofdm_timevarying.m 抽取）
% 输入：
%   body_bb - 基带 body（已由外层完成 LFM 对齐 + Doppler 补偿；长度 ≈ meta.N_shaped）
%   sys     - 系统参数（用 sys.codec, sys.ofdm, sys.sps, sys.sym_rate）
%   meta    - TX 侧 modem_encode_ofdm 产出（含 all_cp_data / perm_all / 块参数）
% 输出：
%   bits - 1×N_info 解码信息比特
%   info - struct（含统一 API 字段 + 诊断）
%
% 依赖：
%   09_Waveform/match_filter
%   07_ChannelEstEq/{ch_est_omp, ch_est_bem}
%   02_ChannelCoding/{conv_encode, siso_decode_conv}
%   03_Interleaving/{random_interleave, random_deinterleave}
%   12_IterativeProc/soft_mapper
%
% 备注：
%   OFDM Turbo 均衡采用手写逐子载波 MMSE-IC + BCJR 循环（非 crossblock 函数），
%   因为 null 子载波需要特殊处理（null 位置不承载数据，LLR 仅取 data_idx）。
%   抽取自 test_ofdm_timevarying L472-632。

cfg   = sys.ofdm;
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
null_idx      = meta.null_idx;
data_idx      = meta.data_idx;
sym_delays    = cfg.sym_delays;
L_h           = max(sym_delays) + 1;
K_sparse      = length(sym_delays);
ofdm_norm     = sqrt(blk_fft);

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

%% ---- 4. 空子载波 CFO 估计（仅时变信道）----
is_timevarying = ~strcmpi(cfg.fading_type, 'static');
N_null = length(null_idx);
if is_timevarying && N_null >= 2
    sc_spacing = sys.sym_rate / blk_fft;
    cfo_range = 3;
    % 粗搜
    cfo_grid = -cfo_range : 0.1 : cfo_range;
    E_null_grid = zeros(size(cfo_grid));
    for ci = 1:length(cfo_grid)
        cfo_hz = cfo_grid(ci);
        phase_corr = exp(-1j*2*pi*cfo_hz/sys.sym_rate*(0:blk_fft-1));
        for bi = 1:N_blocks
            blk_sym = rx_sym_all((bi-1)*sym_per_block+1:bi*sym_per_block);
            rx_nocp = blk_sym(blk_cp+1:end);
            Y_corr = fft(rx_nocp .* phase_corr);
            E_null_grid(ci) = E_null_grid(ci) + sum(abs(Y_corr(null_idx)).^2);
        end
    end
    [~, ci_best] = min(E_null_grid);
    cfo_coarse = cfo_grid(ci_best);
    % 细搜
    cfo_fine = (cfo_coarse-0.15) : 0.01 : (cfo_coarse+0.15);
    E_null_fine = zeros(size(cfo_fine));
    for ci = 1:length(cfo_fine)
        cfo_hz = cfo_fine(ci);
        phase_corr = exp(-1j*2*pi*cfo_hz/sys.sym_rate*(0:blk_fft-1));
        for bi = 1:N_blocks
            blk_sym = rx_sym_all((bi-1)*sym_per_block+1:bi*sym_per_block);
            rx_nocp = blk_sym(blk_cp+1:end);
            Y_corr = fft(rx_nocp .* phase_corr);
            E_null_fine(ci) = E_null_fine(ci) + sum(abs(Y_corr(null_idx)).^2);
        end
    end
    [~, ci_best2] = min(E_null_fine);
    cfo_est_hz = cfo_fine(ci_best2);
    % 应用 CFO 校正
    for bi = 1:N_blocks
        blk_start = (bi-1)*sym_per_block;
        n_vec = blk_start + (0:sym_per_block-1);
        rx_sym_all(blk_start+1:bi*sym_per_block) = ...
            rx_sym_all(blk_start+1:bi*sym_per_block) .* ...
            exp(-1j*2*pi*cfo_est_hz/sys.sym_rate*n_vec);
    end
end

%% ---- 5. 噪声方差估计 ----
if isfield(meta, 'noise_var') && ~isempty(meta.noise_var)
    nv_eq = max(meta.noise_var, 1e-10);
else
    tail = rx_sym_all(end-blk_cp+1:end);
    nv_eq = max(0.1 * var(tail), 1e-10);
end

%% ---- 6. 信道估计 ----
eff_delays = mod(sym_delays, blk_fft);

if strcmpi(cfg.fading_type, 'static')
    % --- OMP：用第 1 块 CP 段 ---
    usable = blk_cp;
    T_mat = zeros(usable, L_h);
    tx_blk1 = meta.all_cp_data(1:sym_per_block);
    for col = 1:L_h
        for row = col:usable
            T_mat(row, col) = tx_blk1(row - col + 1);
        end
    end
    y_train = rx_sym_all(1:usable).';
    [h_omp_vec, ~, ~] = ch_est_omp(y_train, T_mat, L_h, K_sparse, nv_eq);
    h_td_est = zeros(1, blk_fft);
    for p = 1:K_sparse
        if sym_delays(p) + 1 <= L_h
            h_td_est(eff_delays(p)+1) = h_omp_vec(sym_delays(p)+1);
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

%% ---- 6b. nv_post 实测噪声兜底 ----
nv_post_sum = 0; nv_post_cnt = 0;
for bi = 1:N_blocks
    blk_start = (bi-1)*sym_per_block;
    h_td_blk = ifft(H_est_blocks{bi});
    for kk = max(sym_delays)+1 : blk_cp
        n = blk_start + kk;
        if n > length(rx_sym_all), break; end
        y_pred = 0;
        for pp = 1:K_sparse
            d_p = eff_delays(pp) + 1;
            idx = n - sym_delays(pp);
            if idx >= 1 && idx <= N_total_sym
                y_pred = y_pred + h_td_blk(d_p) * meta.all_cp_data(idx);
            end
        end
        nv_post_sum = nv_post_sum + abs(rx_sym_all(n) - y_pred)^2;
        nv_post_cnt = nv_post_cnt + 1;
    end
end
nv_post = nv_post_sum / max(nv_post_cnt, 1);
if is_timevarying
    nv_eq = max(nv_eq, nv_post);
end

%% ---- 7. 分块去 CP + FFT ----
Y_freq_blocks = cell(1, N_blocks);
for bi = 1:N_blocks
    blk_sym = rx_sym_all((bi-1)*sym_per_block+1 : bi*sym_per_block);
    rx_nocp = blk_sym(blk_cp+1:end);
    Y_freq_blocks{bi} = fft(rx_nocp);
end

%% ---- 8. 手写 Turbo 均衡（逐子载波 MMSE-IC + BCJR）----
% 不调用 crossblock，因为 null 子载波需要特殊处理
turbo_iter    = cfg.turbo_iter;
H_cur_blocks  = H_est_blocks;
x_bar_freq_blks = cell(1, N_blocks);
var_x_blks    = ones(1, N_blocks);
for bi = 1:N_blocks
    x_bar_freq_blks{bi} = zeros(1, blk_fft);
end
La_dec_info   = [];
bits_decoded  = [];

for titer = 1:turbo_iter
    % 1. 逐子载波 MMSE-IC → LLR
    LLR_all = zeros(1, M_total);
    for bi = 1:N_blocks
        H_eff    = H_cur_blocks{bi} * ofdm_norm;
        var_x_bi = var_x_blks(bi);

        G_k = var_x_bi * conj(H_eff) ./ (var_x_bi * abs(H_eff).^2 + nv_eq);
        Residual = Y_freq_blocks{bi} - H_eff .* x_bar_freq_blks{bi};
        X_hat_freq = x_bar_freq_blks{bi} + G_k .* Residual;

        mu_k = real(G_k .* H_eff);
        mu_k = max(mu_k, 1e-8);
        nv_k = mu_k .* (1 - mu_k) * var_x_bi + abs(G_k).^2 * nv_eq;
        if is_timevarying
            nv_k = max(nv_k, nv_post);
        else
            nv_k = max(nv_k, 1e-10);
        end

        % 仅 data_idx 子载波的 QPSK LLR
        scale_k = 2 * mu_k ./ nv_k;
        Lp_I = -scale_k .* sqrt(2) .* real(X_hat_freq);
        Lp_Q = -scale_k .* sqrt(2) .* imag(X_hat_freq);
        Lp_I_data = Lp_I(data_idx);
        Lp_Q_data = Lp_Q(data_idx);
        Le_eq_blk = zeros(1, M_per_blk);
        Le_eq_blk(1:2:end) = Lp_I_data;
        Le_eq_blk(2:2:end) = Lp_Q_data;
        LLR_all((bi-1)*M_per_blk+1 : bi*M_per_blk) = Le_eq_blk;
    end

    % 2. 解交织 + BCJR
    Le_eq_deint = random_deinterleave(LLR_all, meta.perm_all);
    Le_eq_deint = max(min(Le_eq_deint, 30), -30);
    [~, Lpost_info, Lpost_coded] = siso_decode_conv( ...
        Le_eq_deint, La_dec_info, codec.gen_polys, codec.constraint_len);
    bits_decoded = double(Lpost_info > 0);

    % 3. 反馈 + DD 信道重估计
    if titer < turbo_iter
        Lpost_inter = random_interleave(Lpost_coded, codec.interleave_seed);
        if length(Lpost_inter) < M_total
            Lpost_inter = [Lpost_inter, zeros(1, M_total - length(Lpost_inter))]; %#ok<AGROW>
        else
            Lpost_inter = Lpost_inter(1:M_total);
        end

        % 构建频域软符号
        x_bar_td_all = zeros(1, N_total_sym);
        var_x_avg = 0;
        for bi = 1:N_blocks
            coded_blk = Lpost_inter((bi-1)*M_per_blk+1 : bi*M_per_blk);
            [x_bar_data, var_x_raw] = soft_mapper(coded_blk, 'qpsk');
            var_x_blks(bi) = max(var_x_raw, nv_eq);
            var_x_avg = var_x_avg + var_x_blks(bi);
            x_bar_freq_full = zeros(1, blk_fft);
            x_bar_freq_full(data_idx) = x_bar_data;
            x_bar_freq_blks{bi} = x_bar_freq_full;
            % 时域：IFFT + CP
            x_bar_td_blk = ifft(x_bar_freq_full) * ofdm_norm;
            blk_start = (bi-1)*sym_per_block;
            x_bar_td_all(blk_start+blk_cp+1 : bi*sym_per_block) = x_bar_td_blk;
            x_bar_td_all(blk_start+1 : blk_start+blk_cp) = x_bar_td_blk(end-blk_cp+1:end);
        end
        var_x_avg = var_x_avg / N_blocks;

        % DD 信道重估计（iter >= 2）
        if titer >= 2
            if is_timevarying && var_x_avg < 0.5
                % DD-BEM
                dd_obs_y = []; dd_obs_x = []; dd_obs_n = [];
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
                            dd_obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
                            dd_obs_x = [dd_obs_x; x_vec]; %#ok<AGROW>
                            dd_obs_n(end+1) = n; %#ok<AGROW>
                        end
                    end
                    for kk = blk_cp+max(sym_delays)+1 : sym_per_block
                        n = blk_start + kk;
                        if n > length(rx_sym_all), break; end
                        x_vec = zeros(1, K_sparse);
                        all_known = true;
                        for pp = 1:K_sparse
                            idx = n - sym_delays(pp);
                            if idx >= 1 && idx <= N_total_sym
                                x_vec(pp) = x_bar_td_all(idx);
                            else
                                all_known = false;
                            end
                        end
                        if all_known && any(x_vec ~= 0)
                            dd_obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
                            dd_obs_x = [dd_obs_x; x_vec]; %#ok<AGROW>
                            dd_obs_n(end+1) = n; %#ok<AGROW>
                        end
                    end
                end
                bem_opts_dd = struct('Q_mode', 'auto', 'lambda_scale', 1.0);
                [h_tv_dd, ~, ~] = ch_est_bem(dd_obs_y(:), dd_obs_x, dd_obs_n(:), ...
                    N_total_sym, sym_delays, cfg.fd_hz, sys.sym_rate, nv_eq, 'dct', bem_opts_dd);
                for bi = 1:N_blocks
                    blk_mid = (bi-1)*sym_per_block + round(sym_per_block/2);
                    blk_mid = max(1, min(blk_mid, N_total_sym));
                    h_td_dd = zeros(1, blk_fft);
                    for p = 1:K_sparse
                        h_td_dd(eff_delays(p)+1) = h_tv_dd(p, blk_mid);
                    end
                    H_cur_blocks{bi} = fft(h_td_dd);
                end
            else
                % 静态：逐块 DD-LS
                for bi = 1:N_blocks
                    if var_x_blks(bi) < 0.5
                        X_bar_eff = x_bar_freq_blks{bi} * ofdm_norm;
                        H_dd_raw = Y_freq_blocks{bi} .* conj(X_bar_eff) ./ (abs(X_bar_eff).^2 + nv_eq);
                        h_dd = ifft(H_dd_raw);
                        h_dd_sparse = zeros(1, blk_fft);
                        eff_d = mod(sym_delays, blk_fft);
                        for p = 1:length(eff_d)
                            h_dd_sparse(eff_d(p)+1) = h_dd(eff_d(p)+1);
                        end
                        H_cur_blocks{bi} = fft(h_dd_sparse);
                    end
                end
            end
        end
    end
end

%% ---- 9. 截取信息比特 ----
N_info = meta.N_info;
if length(bits_decoded) >= N_info
    bits = bits_decoded(1:N_info);
else
    bits = [bits_decoded, zeros(1, N_info - length(bits_decoded))];
end

%% ---- 10. info ----
info = struct();
info.estimated_snr    = 10*log10(max(mean(abs(rx_sym_all).^2) / nv_eq, 1e-6));
abs_llr = abs(Lpost_info);
info.estimated_ber    = mean(0.5 * exp(-abs_llr));
info.turbo_iter       = turbo_iter;
info.convergence_flag = double(median(abs_llr) > 5);
info.H_est_block1     = H_est_blocks{1};
info.noise_var        = nv_eq;
info.sym_offset       = best_off;

% 星座图数据（UI 用）
pre_eq_syms = [];
for bi = 1:N_blocks
    blk = rx_sym_all((bi-1)*sym_per_block + blk_cp + 1 : bi*sym_per_block);
    pre_eq_syms = [pre_eq_syms, blk]; %#ok<AGROW>
end
info.pre_eq_syms = pre_eq_syms;

% 均衡后：用最终判决比特反推 QPSK 符号
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
coded_re = conv_encode(bits, codec.gen_polys, codec.constraint_len);
coded_re = coded_re(1:M_total);
[inter_re, ~] = random_interleave(coded_re, codec.interleave_seed);
idx_re = bi2de(reshape(inter_re, 2, []).', 'left-msb') + 1;
info.post_eq_syms = constellation(idx_re);

end
