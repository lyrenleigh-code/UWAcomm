function [bits, info] = modem_decode_sctde(body_bb, sys, meta)
% 功能：SC-TDE RX（RRC 匹配滤波 + 符号定时 + 信道估计 + Turbo 均衡）
% 版本：V1.0.0（P3.2 从 13_SourceCode/tests/SC-TDE/test_sctde_timevarying.m 抽取）
% 输入：
%   body_bb - 基带 body（已由外层完成 LFM 对齐 + Doppler 补偿；长度 ≈ meta.N_shaped）
%   sys     - 系统参数（用 sys.codec, sys.sctde, sys.sps, sys.sym_rate）
%   meta    - TX 侧 modem_encode_sctde 产出
% 输出：
%   bits - 1×N_info 解码信息比特
%   info - struct（含统一 API 字段 + 诊断）
%
% 依赖：
%   09_Waveform/match_filter
%   07_ChannelEstEq/{ch_est_gamp, ch_est_bem}
%   12_IterativeProc/turbo_equalizer_sctde
%   02_ChannelCoding/{conv_encode, siso_decode_conv}
%   03_Interleaving/{random_interleave, random_deinterleave}
%   12_IterativeProc/soft_mapper
%
% 备注：
%   静态路径：GAMP 信道估计 + turbo_equalizer_sctde（PLL 关闭）
%   时变路径：BEM(DCT) + 手写逐符号 ISI 消除 + MMSE Turbo（~200 行）
%   抽取自 test_sctde_timevarying L337-547。

cfg   = sys.sctde;
codec = sys.codec;

%% ---- 1. 关键参数 ----
known_map     = meta.known_map;
train_len     = meta.train_len;
N_total_sym   = meta.N_total_sym;
N_shaped      = meta.N_shaped;
M_coded       = meta.M_coded;
data_only_idx = meta.data_only_idx;
% 去oracle：不用 cfg.sym_delays，由训练段 GAMP 搜索发现
L_max         = min(train_len, 200);  % 搜索范围上界
K_sparse_max  = 10;
T             = train_len;
N_dsym        = N_total_sym - T;

% 去oracle：由帧结构判断是否时变（有散布导频→时变路径，无→静态路径）
is_timevarying = isfield(meta, 'pilot_positions') && ~isempty(meta.pilot_positions) && any(meta.pilot_positions > 0);

%% ---- 1b. 本地重生成训练序列和导频（seed=99，与 TX 端一致）----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
rng_st = rng;
rng(99);
training = constellation(randi(4, 1, train_len));
pilot_sym_ref = constellation(randi(4, 1, cfg.pilot_cluster_len));
rng(rng_st);

% 构建 known_values：仅在 known_map=true 位置填入已知值
known_values = zeros(1, N_total_sym);
known_values(1:T) = training;
if isfield(meta, 'pilot_positions') && ~isempty(meta.pilot_positions)
    for kk = 1:length(meta.pilot_positions)
        pp_start = meta.pilot_positions(kk);
        if pp_start > 0
            pp_end = min(pp_start + cfg.pilot_cluster_len - 1, N_total_sym);
            plen = pp_end - pp_start + 1;
            known_values(pp_start:pp_end) = pilot_sym_ref(1:plen);
        end
    end
end

%% ---- 2. body 长度对齐 ----
body_bb = body_bb(:).';
if length(body_bb) < N_shaped
    body_bb = [body_bb, zeros(1, N_shaped - length(body_bb))];
elseif length(body_bb) > N_shaped
    body_bb = body_bb(1:N_shaped);
end

%% ---- 3. RRC 匹配滤波 + 符号定时 ----
[rx_filt, ~] = match_filter(body_bb, sys.sps, 'rrc', cfg.rolloff, cfg.span);

pilot = training(1:min(10, train_len));  % 本地重生成的训练序列首段
N_pilot = length(pilot);
best_off = 0; best_corr = 0;
sym_off_corr_curve = zeros(1, sys.sps);
for off = 0 : sys.sps-1
    st = rx_filt(off+1 : sys.sps : end);
    n_check = min(length(st), N_pilot);
    if n_check >= 10
        c = abs(sum(st(1:n_check) .* conj(pilot(1:n_check))));
        sym_off_corr_curve(off+1) = c;
        if c > best_corr
            best_corr = c;
            best_off  = off;
        end
    end
end
rx_sym_recv = rx_filt(best_off+1 : sys.sps : end);
if length(rx_sym_recv) > N_total_sym
    rx_sym_recv = rx_sym_recv(1:N_total_sym);
elseif length(rx_sym_recv) < N_total_sym
    rx_sym_recv = [rx_sym_recv, zeros(1, N_total_sym - length(rx_sym_recv))];
end

%% ---- 4. 噪声方差粗估（训练段信号方差，BEM 后由 nv_post 精化）----
nv_eq = max(0.1 * var(rx_sym_recv(1:min(50, length(rx_sym_recv)))), 1e-10);

%% ---- 5. 信道时延盲估计（GAMP 全长搜索）----
T_mat_scan = zeros(train_len, L_max);
for col = 1:L_max
    T_mat_scan(col:train_len, col) = training(1:train_len-col+1).';
end
rx_train = rx_sym_recv(1:train_len);
[h_scan_vec, ~] = ch_est_gamp(rx_train(:), T_mat_scan, L_max, 50, nv_eq);

% 自动发现时延位置
h_abs = abs(h_scan_vec(:).');
thresh = 0.05 * max(h_abs);
detected = find(h_abs > thresh);
if length(detected) > K_sparse_max
    [~, si] = sort(h_abs(detected), 'descend');
    detected = sort(detected(si(1:K_sparse_max)));
end
if isempty(detected), detected = 1; end
sym_delays = detected - 1;
L_h = max(sym_delays) + 1;
P_paths = length(sym_delays);

%% ---- 5b. 信道估计 + Turbo 均衡 ----
if ~is_timevarying
    %% === 静态路径：GAMP + turbo_equalizer_sctde ===
    h_est_gamp = h_scan_vec(1:L_h).';

    % PLL 关闭（无多普勒时 PLL 不稳定，per debug history）
    eq_params = struct('num_ff', cfg.num_ff, 'num_fb', cfg.num_fb, ...
        'lambda', cfg.lambda, ...
        'pll', struct('enable', false, 'Kp', 0.01, 'Ki', 0.005));

    [bits_out, iter_info_out] = turbo_equalizer_sctde(rx_sym_recv, h_est_gamp, ...
        training, cfg.turbo_iter, nv_eq, eq_params, codec);

    H_est_block1 = fft(h_est_gamp, 256);
    turbo_iter_actual = iter_info_out.num_iter;
    final_llr = iter_info_out.llr_per_iter{end};
    med_llr_final = median(abs(final_llr));
    Lpost_info = final_llr;   % 统一命名供 decode_convergence 使用
else
    %% === 时变路径：BEM(DCT) + 手写 ISI 消除 Turbo ===
    pilot_positions = meta.pilot_positions;
    N_pilot_clusters = length(pilot_positions);

    % --- BEM 观测矩阵（训练 + 散布导频）---
    obs_y = []; obs_x = []; obs_n = [];
    for n = max(sym_delays)+1 : train_len
        x_vec = zeros(1, P_paths);
        for pp = 1:P_paths
            idx = n - sym_delays(pp);
            if idx >= 1, x_vec(pp) = training(idx); end
        end
        if any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_recv(n); %#ok<AGROW>
            obs_x = [obs_x; x_vec]; %#ok<AGROW>
            obs_n(end+1) = n; %#ok<AGROW>
        end
    end
    max_d = max(sym_delays);
    pilot_cluster_len = cfg.pilot_cluster_len;
    for kk = 1:N_pilot_clusters
        pp_pos = pilot_positions(kk);
        if pp_pos == 0, continue; end
        for jj = max_d : pilot_cluster_len-1
            n = pp_pos + jj;
            if n > N_total_sym, break; end
            x_vec = zeros(1, P_paths);
            all_known = true;
            for pp = 1:P_paths
                idx = n - sym_delays(pp);
                if idx >= 1 && idx <= N_total_sym && known_map(idx)
                    x_vec(pp) = known_values(idx);
                else
                    all_known = false;
                end
            end
            if all_known && any(x_vec ~= 0)
                obs_y(end+1) = rx_sym_recv(n); %#ok<AGROW>
                obs_x = [obs_x; x_vec]; %#ok<AGROW>
                obs_n(end+1) = n; %#ok<AGROW>
            end
        end
    end

    % BEM(DCT) 信道估计
    fd_hz_max = 10;  % 保守上界，不依赖 oracle fd_hz
    bem_opts = struct('Q_mode', 'bic', 'lambda_scale', 1.0);
    [h_tv, ~, ~] = ch_est_bem(obs_y(:), obs_x, obs_n(:), N_total_sym, ...
        sym_delays, fd_hz_max, sys.sym_rate, nv_eq, 'dct', bem_opts);

    % nv_post 实测噪声兜底
    nv_post_sum = 0; nv_post_cnt = 0;
    for n = max(sym_delays)+1 : train_len
        y_pred = 0;
        for pp = 1:P_paths
            idx = n - sym_delays(pp);
            if idx >= 1
                y_pred = y_pred + h_tv(pp, n) * training(idx);
            end
        end
        nv_post_sum = nv_post_sum + abs(rx_sym_recv(n) - y_pred)^2;
        nv_post_cnt = nv_post_cnt + 1;
    end
    nv_post_meas = nv_post_sum / max(nv_post_cnt, 1);
    nv_eq = max(nv_eq, nv_post_meas);

    % --- Turbo 迭代 ---
    [~, perm_turbo_tv] = random_interleave(zeros(1, M_coded), codec.interleave_seed);
    bits_decoded = [];
    Lp_coded = [];
    turbo_iter = cfg.turbo_iter;

    for titer = 1:turbo_iter
        if titer == 1
            % iter1: 已知位置 ISI 消除 + MMSE 单抽头
            data_eq = zeros(1, N_dsym);
            for n = 1:N_dsym
                nn = T + n;
                isi_known = 0;
                isi_unknown_pwr = 0;
                for pp = 1:P_paths
                    d = sym_delays(pp);
                    if d == 0, continue; end
                    idx = nn - d;
                    if idx >= 1 && idx <= N_total_sym
                        if known_map(idx)
                            isi_known = isi_known + h_tv(pp, nn) * known_values(idx);
                        else
                            isi_unknown_pwr = isi_unknown_pwr + abs(h_tv(pp, nn))^2;
                        end
                    end
                end
                h0_n = h_tv(1, nn);
                rx_ic = rx_sym_recv(nn) - isi_known;
                nv_total = nv_eq + isi_unknown_pwr;
                data_eq(n) = conj(h0_n) * rx_ic / (abs(h0_n)^2 + nv_total);
            end
            nv_post = max(nv_eq * 0.5, 1e-10);
        else
            % iter2+: 软符号全 ISI 消除 + MMSE + DD-BEM 重估计
            Lp_inter = random_interleave(Lp_coded, codec.interleave_seed);
            if length(Lp_inter) < M_coded
                Lp_inter = [Lp_inter, zeros(1, M_coded - length(Lp_inter))]; %#ok<AGROW>
            else
                Lp_inter = Lp_inter(1:M_coded);
            end
            [x_bar_data, var_x] = soft_mapper(Lp_inter, 'qpsk');
            var_x_avg = mean(var_x);

            full_soft = zeros(1, N_total_sym);
            full_soft(1:T) = training;
            n_fill = min(length(x_bar_data), length(data_only_idx));
            full_soft(T + data_only_idx(1:n_fill)) = x_bar_data(1:n_fill);
            pilot_idx_seg = find(known_map(T+1:end));
            full_soft(T + pilot_idx_seg) = known_values(T + pilot_idx_seg);

            % DD-BEM 重估计（置信门控）
            avg_confidence = mean(abs(Lp_coded));
            if avg_confidence > 0.5
                obs_y2 = []; obs_x2 = []; obs_n2 = [];
                dd_step = 4;
                for n = max(sym_delays)+1 : N_total_sym
                    if n <= T || known_map(n)
                        use = true;
                    elseif mod(n - T, dd_step) == 0
                        use = true;
                    else
                        use = false;
                    end
                    if use
                        x_vec = zeros(1, P_paths);
                        for pp = 1:P_paths
                            idx = n - sym_delays(pp);
                            if idx >= 1 && idx <= N_total_sym
                                x_vec(pp) = full_soft(idx);
                            end
                        end
                        if any(x_vec ~= 0)
                            obs_y2(end+1) = rx_sym_recv(n); %#ok<AGROW>
                            obs_x2 = [obs_x2; x_vec]; %#ok<AGROW>
                            obs_n2(end+1) = n; %#ok<AGROW>
                        end
                    end
                end
                [h_tv, ~, ~] = ch_est_bem(obs_y2(:), obs_x2, obs_n2(:), N_total_sym, ...
                    sym_delays, fd_hz_max, sys.sym_rate, nv_eq, 'dct', bem_opts);
            end

            % 逐符号全 ISI 消除 + 单抽头 MMSE
            data_eq = zeros(1, N_dsym);
            for n = 1:N_dsym
                nn = T + n;
                isi = 0;
                for pp = 1:P_paths
                    d = sym_delays(pp);
                    if d == 0, continue; end
                    idx = nn - d;
                    if idx >= 1 && idx <= N_total_sym
                        isi = isi + h_tv(pp, nn) * full_soft(idx);
                    end
                end
                h0_n = h_tv(1, nn);
                rx_ic = rx_sym_recv(nn) - isi;
                data_eq(n) = conj(h0_n) * rx_ic / ...
                    (abs(h0_n)^2 + nv_eq / max(1 - var_x_avg, 0.01));
            end
            nv_post = max(nv_eq * 0.5, 1e-10);
        end

        % 提取数据位置 LLR（排除导频）
        data_eq_clean = data_eq(data_only_idx);
        LLR_eq = zeros(1, 2*length(data_eq_clean));
        LLR_eq(1:2:end) = -2*sqrt(2) * real(data_eq_clean) / nv_post;
        LLR_eq(2:2:end) = -2*sqrt(2) * imag(data_eq_clean) / nv_post;

        % BCJR 译码
        LLR_trunc = LLR_eq(1:min(length(LLR_eq), M_coded));
        if length(LLR_trunc) < M_coded
            LLR_trunc = [LLR_trunc, zeros(1, M_coded - length(LLR_trunc))]; %#ok<AGROW>
        end
        Le_deint = random_deinterleave(LLR_trunc, perm_turbo_tv);
        Le_deint = max(min(Le_deint, 30), -30);
        [~, Lp_info, Lp_coded] = siso_decode_conv(Le_deint, [], codec.gen_polys, ...
            codec.constraint_len, codec.decode_mode);
        bits_decoded = double(Lp_info > 0);
    end
    bits_out = bits_decoded;
    turbo_iter_actual = turbo_iter;
    med_llr_final = median(abs(Lp_info));
    Lpost_info = Lp_info;   % 统一命名供 decode_convergence 使用

    % H_est 用于 UI（取训练段中点的 CIR）
    h_mid = zeros(1, L_h);
    mid_n = round(train_len / 2);
    for pp = 1:P_paths
        h_mid(sym_delays(pp)+1) = h_tv(pp, mid_n);
    end
    H_est_block1 = fft(h_mid, 256);
end

%% ---- 6. 截取信息比特 ----
N_info = meta.N_info;
if ~is_timevarying
    % 静态路径 bits_out 来自 turbo_equalizer_sctde
end
if length(bits_out) >= N_info
    bits = bits_out(1:N_info);
else
    bits = [bits_out, zeros(1, N_info - length(bits_out))];
end

%% ---- 7. info ----
info = struct();
% 训练段信道功率/噪声 → 信道 SNR（减去 RRC 处理增益）
P_sig_train = sum(abs(h_scan_vec).^2);
info.estimated_snr    = 10*log10(max(P_sig_train / nv_eq, 1e-6)) - 10*log10(sys.sps);
info.estimated_ber    = mean(0.5 * exp(-med_llr_final));
info.turbo_iter       = turbo_iter_actual;
% 统一收敛判据（decode_convergence helper，三选一 — 2026-04-19 HIGH-1 修复）
[info.convergence_flag, conv_extra] = decode_convergence(Lpost_info, [], []);
info.frac_confident = conv_extra.frac_confident;
info.H_est_block1     = H_est_block1;
info.noise_var        = nv_eq;
info.sym_offset       = best_off;
info.sym_off_best     = best_off;
info.sym_off_corr     = sym_off_corr_curve;
info.sym_off_best_val = best_corr;

% 星座图数据（UI 用）
info.pre_eq_syms = rx_sym_recv(T+1:end);
if exist('iter_info_out', 'var') && isfield(iter_info_out, 'x_hat_per_iter')
    xh_all = iter_info_out.x_hat_per_iter;
    info.post_eq_syms = xh_all{end}(T+1:min(end, T+N_dsym));
    eq_iters = cell(1, length(xh_all));
    for ki = 1:length(xh_all)
        eq_iters{ki} = xh_all{ki}(T+1:min(end, T+N_dsym));
    end
    info.eq_syms_iters = eq_iters;
elseif exist('data_eq', 'var')
    info.post_eq_syms = data_eq;
    info.eq_syms_iters = {};
else
    info.post_eq_syms = [];
    info.eq_syms_iters = {};
end

end
