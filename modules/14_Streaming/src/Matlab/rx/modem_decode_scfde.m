function [bits, info] = modem_decode_scfde(body_bb, sys, meta)
% 功能：SC-FDE RX（RRC匹配滤波 + 训练块信道估计 + Turbo LMMSE-IC/BCJR）
% 版本：V2.1.0（2026-04-17 修 convergence_flag 误判 + est_snr 偏低 10dB；详见
%               wiki/debug-logs/13_SourceCode/SC-FDE调试日志.md）
% 输入：
%   body_bb - 基带 body（已由外层完成 LFM 对齐 + Doppler 补偿）
%   sys     - 系统参数
%   meta    - 帧结构参数（不含 TX 数据）
%
% info 输出字段：
%   estimated_snr        — 符号域 SNR (dB)，不再多减 10*log10(sps)
%   estimated_ber        — 由 Lpost_info 的 0.5*exp(-|L|) 估算
%                          注：LLR scale 偏小时会虚高，BER=0 场景不能作为收敛依据
%   turbo_iter           — 实际运行迭代数
%   convergence_flag     — 三选一判据（见 §9 注释）
%   hard_converged_iter  — 硬判决稳定时的迭代号（0 = 从未稳定）
%   frac_confident       — |LLR| > 1.5 占比
%
% 依赖：
%   09_Waveform/match_filter
%   07_ChannelEstEq/{ch_est_gamp, ch_est_bem}
%   12_IterativeProc/{eq_mmse_ic_fde, soft_mapper, soft_demapper}
%   02_ChannelCoding/siso_decode_conv
%   03_Interleaving/{random_interleave, random_deinterleave}

cfg   = sys.scfde;
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
% 去oracle：不用 cfg.sym_delays，由训练块 GAMP 自动发现时延位置
L_max         = blk_cp;            % 最大时延扩展 = CP 长度（协议约定）
K_sparse_max  = 10;                % 稀疏径数上界

%% ---- 1b. 本地重生成训练块（seed=77，与 TX 一致）----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
rng_st = rng;
rng(meta.train_seed);
train_sym = constellation(randi(4, 1, blk_fft));
rng(rng_st);
train_cp = [train_sym(end-blk_cp+1:end), train_sym];  % 完整训练块含CP

%% ---- 2. body 长度对齐 ----
body_bb = body_bb(:).';
if length(body_bb) < N_shaped
    body_bb = [body_bb, zeros(1, N_shaped - length(body_bb))];
elseif length(body_bb) > N_shaped
    body_bb = body_bb(1:N_shaped);
end

%% ---- 3. RRC 匹配滤波 + 符号定时 ----
[rx_filt, ~] = match_filter(body_bb, sys.sps, 'rrc', cfg.rolloff, cfg.span);

% 用训练块首 10 符号做符号定时
pilot = train_cp(1:min(10, sym_per_block));
N_pilot = length(pilot);
best_off = 0; best_corr = 0;
sym_off_corr_curve = zeros(1, sys.sps);   % 每候选 off 的 |corr|
for off = 0 : sys.sps-1
    st = rx_filt(off+1 : sys.sps : end);
    if length(st) >= N_pilot
        c = abs(sum(st(1:N_pilot) .* conj(pilot)));
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

%% ---- 4. 从训练块估计噪声方差 ----
% 训练块残差粗估：用直达径粗估 h0，再算残差
rx_train = rx_sym_all(1:sym_per_block);
% 简单 LS 粗估直达径增益
h0_rough = sum(rx_train(blk_cp+1:end) .* conj(train_sym)) / blk_fft;
nv_eq = max(mean(abs(rx_train(blk_cp+1:end) - h0_rough * train_sym).^2), 1e-10);

%% ---- 5. 信道估计（训练块 GAMP 全长搜索 + 自动时延发现）----
usable = blk_cp;
T_mat = zeros(usable, L_max);
for col = 1:L_max
    for row = col:usable
        T_mat(row, col) = train_cp(row - col + 1);
    end
end
y_train = rx_sym_all(1:usable).';
[h_gamp_vec, ~] = ch_est_gamp(y_train, T_mat, L_max, 50, nv_eq);

% 自动发现非零时延位置（阈值 = 最大幅度的 5%）
h_abs = abs(h_gamp_vec(:).');
thresh = 0.05 * max(h_abs);
detected = find(h_abs > thresh);
if length(detected) > K_sparse_max
    [~, si] = sort(h_abs(detected), 'descend');
    detected = sort(detected(si(1:K_sparse_max)));
end
if isempty(detected), detected = 1; end
sym_delays_est = detected - 1;   % 0-based 时延
K_sparse = length(sym_delays_est);
eff_delays = mod(sym_delays_est, blk_fft);

% 构建稀疏时域 CIR
h_td_est = zeros(1, blk_fft);
for p = 1:K_sparse
    h_td_est(eff_delays(p)+1) = h_gamp_vec(sym_delays_est(p)+1);
end
H_est_init = fft(h_td_est);

% 初始化所有数据块的频域信道估计
H_est_blocks = cell(1, N_data_blocks);
for bi = 1:N_data_blocks
    H_est_blocks{bi} = H_est_init;
end

% 训练块频域残差精化噪声方差（H 和 X 都已知，直接分离 S/N）
Y_train_freq = fft(rx_sym_all(sym_per_block-blk_fft+1 : sym_per_block));  % 训练块去CP后FFT
X_train_freq = fft(train_sym);
noise_freq   = Y_train_freq - H_est_init .* X_train_freq;
nv_eq = max(mean(abs(noise_freq).^2), 1e-10);
% 信号功率（供 SNR 估计用）
P_sig_train = mean(abs(H_est_init .* X_train_freq).^2);

%% ---- 6. 数据块：去 CP + FFT ----
Y_freq_blocks = cell(1, N_data_blocks);
for bi = 1:N_data_blocks
    blk_idx = bi + 1;  % block 1 是训练，数据从 block 2 开始
    blk_sym = rx_sym_all((blk_idx-1)*sym_per_block+1 : blk_idx*sym_per_block);
    rx_nocp = blk_sym(blk_cp+1:end);
    Y_freq_blocks{bi} = fft(rx_nocp);
end

%% ---- 7. Turbo 均衡（仅数据块）----
% LLR clip ±30 (L170) 限制了 Lpost 的 scale —— 单一 `median(|L|) > 5` 判据过严，
% 需要 §9 的硬判决稳定性 / 高置信占比兜底。
turbo_iter = cfg.turbo_iter;
x_bar_blks = cell(1, N_data_blocks);
var_x_blks = ones(1, N_data_blocks);
H_cur = H_est_blocks;
for bi = 1:N_data_blocks, x_bar_blks{bi} = zeros(1, blk_fft); end
bits_decoded = [];
bits_prev    = [];    % 上一次迭代硬判决，用于收敛检测
Lpost_info   = [];
eq_syms_iters = cell(1, turbo_iter);
hard_converged_iter = 0;   % 连续两轮硬判决相同时记录首次稳定的 iter（0 = 从未稳定）

for titer = 1:turbo_iter
    LLR_all = zeros(1, M_total);
    eq_syms_t = [];
    for bi = 1:N_data_blocks
        [x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq_blocks{bi}, ...
            H_cur{bi}, x_bar_blks{bi}, var_x_blks(bi), nv_eq);
        LLR_all((bi-1)*M_per_blk+1 : bi*M_per_blk) = ...
            soft_demapper(x_tilde, mu, nv_tilde, zeros(1, M_per_blk), 'qpsk');
        eq_syms_t = [eq_syms_t, x_tilde(:).']; %#ok<AGROW>
    end
    eq_syms_iters{titer} = eq_syms_t;

    Le_deint = random_deinterleave(LLR_all, meta.perm_all);
    Le_deint = max(min(Le_deint, 30), -30);
    [~, Lpost_info, Lpost_coded] = siso_decode_conv( ...
        Le_deint, [], codec.gen_polys, codec.constraint_len, codec.decode_mode);
    bits_decoded = double(Lpost_info > 0);

    % 硬判决稳定性判据：连续两轮 bit 输出相同视为收敛
    if ~isempty(bits_prev) && length(bits_prev) == length(bits_decoded) && ...
       hard_converged_iter == 0
        if isequal(bits_prev, bits_decoded)
            hard_converged_iter = titer;
        end
    end
    bits_prev = bits_decoded;

    if titer < turbo_iter
        Lp_inter = random_interleave(Lpost_coded, codec.interleave_seed);
        if length(Lp_inter) < M_total
            Lp_inter = [Lp_inter, zeros(1, M_total - length(Lp_inter))]; %#ok<AGROW>
        else
            Lp_inter = Lp_inter(1:M_total);
        end
        for bi = 1:N_data_blocks
            coded_blk = Lp_inter((bi-1)*M_per_blk+1 : bi*M_per_blk);
            [x_bar_blks{bi}, var_x_raw] = soft_mapper(coded_blk, 'qpsk');
            var_x_blks(bi) = max(var_x_raw, nv_eq);
            if titer >= 2 && var_x_blks(bi) < 0.5
                X_bar = fft(x_bar_blks{bi});
                H_dd = Y_freq_blocks{bi} .* conj(X_bar) ./ (abs(X_bar).^2 + nv_eq);
                H_cur{bi} = H_dd;
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
med_llr = median(abs(Lpost_info));
frac_confident = mean(abs(Lpost_info) > 1.5);   % 高置信度 LLR 占比
info = struct();
% 符号域 SNR（P_sig_train / nv_eq 已经是符号域比值；rx_filt 未做 RRC 能量归一化，
%  因此不需减 10*log10(sps) —— 之前减去导致估计偏低 ~10dB，BER=0 场景仍显示 SNR≈5dB）
info.estimated_snr    = 10*log10(max(P_sig_train / nv_eq, 1e-6));
info.estimated_ber    = mean(0.5 * exp(-abs(Lpost_info)));
info.turbo_iter       = turbo_iter;
% 收敛判据三选一（任一成立视为收敛）：
%   A. median |LLR| > 5（高 SNR 场景）
%   B. 连续两轮硬判决稳定（低 LLR scale 但硬决一致）
%   C. 高置信度 LLR 占比 > 70%（稳健兜底）
info.convergence_flag = double( ...
    med_llr > 5 || hard_converged_iter > 0 || frac_confident > 0.70);
info.hard_converged_iter = hard_converged_iter;
info.frac_confident      = frac_confident;
% 同步诊断（sync tab 用）：符号定时搜索结果
info.sym_off_best        = best_off;
info.sym_off_corr        = sym_off_corr_curve;  % 1×sps 向量
info.sym_off_best_val    = best_corr;
info.H_est_block1     = H_est_init;
info.noise_var        = nv_eq;
info.sym_offset       = best_off;

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
