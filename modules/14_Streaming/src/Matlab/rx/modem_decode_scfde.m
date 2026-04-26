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

% Phase 4 多训练块协议（向后兼容旧 meta）
if isfield(meta, 'train_block_indices') && ~isempty(meta.train_block_indices)
    train_block_indices = meta.train_block_indices;
    data_block_indices  = meta.data_block_indices;
    N_train_blocks      = length(train_block_indices);
else
    % 旧 meta：单训练块（block 1=train, blocks 2..N=data）
    train_block_indices = 1;
    data_block_indices  = 2:N_blocks;
    N_train_blocks      = 1;
end
% sanity
if length(data_block_indices) ~= N_data_blocks
    warning('modem_decode_scfde:meta_mismatch', ...
        'meta.N_data_blocks=%d 与 length(data_block_indices)=%d 不一致，按后者为准', ...
        N_data_blocks, length(data_block_indices));
    N_data_blocks = length(data_block_indices);
end

%% ---- 1b. 本地重生成训练块（seed=77，与 TX 一致）----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
rng_st = rng;
rng(meta.train_seed);
train_sym = constellation(randi(4, 1, blk_fft));
rng(rng_st);
train_cp = [train_sym(end-blk_cp+1:end), train_sym];  % 完整训练块含CP

% Phase 5: block-pilot 协议（向后兼容）
if isfield(meta, 'pilot_per_blk') && ~isempty(meta.pilot_per_blk)
    N_pilot_per_blk = meta.pilot_per_blk;
else
    N_pilot_per_blk = 0;
end
N_data_per_blk = blk_fft - N_pilot_per_blk;
if N_pilot_per_blk > 0
    pilot_seed_rx = 99;  % 与 TX modem_encode_scfde V4.0 同
    if isfield(meta, 'pilot_seed') && ~isempty(meta.pilot_seed)
        pilot_seed_rx = meta.pilot_seed;
    end
    rng_st = rng;
    rng(pilot_seed_rx);
    pilot_seq = constellation(randi(4, 1, N_pilot_per_blk));
    rng(rng_st);
else
    pilot_seq = [];
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

%% ---- 4. 从训练块估计噪声方差（用第一个训练块）----
% Phase 4：多训练块下用 train_block_indices(1) 作初始噪声估计
train_blk1_global = train_block_indices(1);
train_blk1_start = (train_blk1_global - 1) * sym_per_block;
rx_train = rx_sym_all(train_blk1_start+1 : train_blk1_start+sym_per_block);
% 简单 LS 粗估直达径增益
h0_rough = sum(rx_train(blk_cp+1:end) .* conj(train_sym)) / blk_fft;
nv_eq = max(mean(abs(rx_train(blk_cp+1:end) - h0_rough * train_sym).^2), 1e-10);

%% ---- 5. 信道估计（第一个训练块 GAMP + 自动时延发现）----
usable = blk_cp;
T_mat = zeros(usable, L_max);
for col = 1:L_max
    for row = col:usable
        T_mat(row, col) = train_cp(row - col + 1);
    end
end
y_train = rx_sym_all(train_blk1_start+1 : train_blk1_start+usable).';
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
Y_train_freq = fft(rx_sym_all(train_blk1_start+blk_cp+1 : train_blk1_start+sym_per_block));  % 训练块去CP后FFT
X_train_freq = fft(train_sym);
noise_freq   = Y_train_freq - H_est_init .* X_train_freq;
nv_eq = max(mean(abs(noise_freq).^2), 1e-10);
% 信号功率（供 SNR 估计用）
P_sig_train = mean(abs(H_est_init .* X_train_freq).^2);

%% ---- 5b. Phase 5/4-revision: pre-Turbo BEM (pure pilot 估时变 H) ----
% 触发条件（任一满足）：
%   (a) Phase 5 方案 E：N_pilot_per_blk > 0（每 data block 末 pilot 段提供干净 obs）
%   (b) Phase 4-revision：N_train_blocks > 1（多 train block 提供干净 obs，无 pilot 也能 BEM）
% iter=0..1 H_est_blocks 由时变 BEM h_tv 替代单块 GAMP（避开软符号-BEM 鸡蛋耦合）
trigger_pretturbo = (N_pilot_per_blk > 0) || (length(train_block_indices) > 1);
if trigger_pretturbo
    fd_est_pretturbo = 20;   % Phase 5 调优：10→20 Hz 上界（覆盖 fd=5Hz 时变 V5c）
    [obs_y_pre, obs_x_pre, obs_n_pre] = build_bem_obs_pretturbo( ...
        rx_sym_all, train_cp, pilot_seq, blk_cp, blk_fft, sym_per_block, ...
        N_total_sym, sym_delays_est, K_sparse, ...
        train_block_indices, data_block_indices, N_pilot_per_blk);
    if length(obs_y_pre) >= 20
        bem_opts = struct('Q_mode', 'auto', 'lambda_scale', 1.0);
        try
            [h_tv_pre, ~, ~] = ch_est_bem(obs_y_pre(:), obs_x_pre, obs_n_pre(:), ...
                N_total_sym, sym_delays_est, fd_est_pretturbo, sys.sym_rate, ...
                nv_eq, 'dct', bem_opts);
            for bi = 1:N_data_blocks
                blk_idx = data_block_indices(bi);
                blk_mid = (blk_idx-1) * sym_per_block + round(sym_per_block/2);
                blk_mid = max(1, min(blk_mid, N_total_sym));
                h_td_blk = zeros(1, blk_fft);
                for p = 1:K_sparse
                    h_td_blk(eff_delays(p)+1) = h_tv_pre(p, blk_mid);
                end
                H_est_blocks{bi} = fft(h_td_blk);
            end
        catch
            % BEM 失败保留 H_est_init 单块 fallback
        end
    end
end

%% ---- 6. 数据块：去 CP + FFT（按 data_block_indices 提取）----
Y_freq_blocks = cell(1, N_data_blocks);
for bi = 1:N_data_blocks
    blk_idx = data_block_indices(bi);   % 全局 block index
    blk_sym = rx_sym_all((blk_idx-1)*sym_per_block+1 : blk_idx*sym_per_block);
    rx_nocp = blk_sym(blk_cp+1:end);
    Y_freq_blocks{bi} = fft(rx_nocp);
end

%% ---- 7. Turbo 均衡（仅数据块）----
% V3.0 (2026-04-19): 加 BEM 时变信道估计分支（spec 2026-04-19-p3-decoder-timevarying-branch）
%   titer=1 用静态 H_est_blocks 做均衡
%   titer=2 末尾用 x_bar 重构符号 → ch_est_bem 一次性跨块估计 h_tv
%   titer=3+ 用时变 H_cur（每块切 h_tv 对应段）
turbo_iter = cfg.turbo_iter;
x_bar_blks = cell(1, N_data_blocks);
var_x_blks = ones(1, N_data_blocks);
H_cur = H_est_blocks;
% Phase 5：x_bar_blks{bi} 长度 blk_fft = [data_part(N_data) + pilot_part(N_pilot)]
% pilot 段已知（pilot_seq），data 段从 0 软符号开始
for bi = 1:N_data_blocks
    if N_pilot_per_blk > 0
        x_bar_blks{bi} = [zeros(1, N_data_per_blk), pilot_seq];
    else
        x_bar_blks{bi} = zeros(1, blk_fft);
    end
end
bits_decoded = [];
bits_prev    = [];    % 上一次迭代硬判决，用于收敛检测
Lpost_info   = [];
eq_syms_iters = cell(1, turbo_iter);
hard_converged_iter = 0;   % 连续两轮硬判决相同时记录首次稳定的 iter（0 = 从未稳定）
bem_done = false;     % 标记 BEM 是否已估（只估一次）
fd_est_bem = 10;       % 保守上界 (Hz)；后续可从 sys.scfde.fd_hz_max 读

for titer = 1:turbo_iter
    LLR_all = zeros(1, M_total);
    eq_syms_t = [];
    for bi = 1:N_data_blocks
        [x_tilde, mu, nv_tilde] = eq_mmse_ic_fde(Y_freq_blocks{bi}, ...
            H_cur{bi}, x_bar_blks{bi}, var_x_blks(bi), nv_eq);
        % Phase 5：仅对 data 段（前 N_data_per_blk symbols）做 soft_demapper
        x_tilde_data = x_tilde(1:N_data_per_blk);
        if isscalar(mu), mu_data = mu; else, mu_data = mu(1:N_data_per_blk); end
        if isscalar(nv_tilde), nv_tilde_data = nv_tilde; else, nv_tilde_data = nv_tilde(1:N_data_per_blk); end
        LLR_all((bi-1)*M_per_blk+1 : bi*M_per_blk) = ...
            soft_demapper(x_tilde_data, mu_data, nv_tilde_data, zeros(1, M_per_blk), 'qpsk');
        eq_syms_t = [eq_syms_t, x_tilde_data(:).']; %#ok<AGROW>
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
            [x_bar_data, var_x_raw] = soft_mapper(coded_blk, 'qpsk');
            % Phase 5：拼回 [data 软符号 + pilot 已知] 形成 blk_fft 长度
            if N_pilot_per_blk > 0
                x_bar_blks{bi} = [x_bar_data(:).', pilot_seq];
            else
                x_bar_blks{bi} = x_bar_data(:).';
            end
            var_x_blks(bi) = max(var_x_raw, nv_eq);
        end

        % --- V3.0/V4.0: BEM 跨块时变信道估计（titer==2 后一次性做）---
        % V4.0 (2026-04-26 Phase 4): 多训练块支持，build_bem_observations 接受
        % train_block_indices/data_block_indices 参数
        if ~bem_done && titer >= 2 && mean(var_x_blks) < 0.6
            try
                [obs_y, obs_x_mat, obs_n] = build_bem_observations( ...
                    rx_sym_all, train_cp, x_bar_blks, blk_cp, blk_fft, ...
                    sym_per_block, N_total_sym, ...
                    sym_delays_est, K_sparse, ...
                    train_block_indices, data_block_indices);
                if length(obs_y) >= 20   % 至少 20 观测才调 BEM
                    bem_opts = struct('Q_mode', 'auto', 'lambda_scale', 1.0);
                    [h_tv_bem, ~, ~] = ch_est_bem(obs_y(:), obs_x_mat, obs_n(:), ...
                        N_total_sym, sym_delays_est, fd_est_bem, sys.sym_rate, ...
                        nv_eq, 'dct', bem_opts);
                    % 每数据块取中点时刻的 h 作为该块代表
                    for bi = 1:N_data_blocks
                        blk_idx = data_block_indices(bi);
                        blk_mid = (blk_idx-1) * sym_per_block + round(sym_per_block/2);
                        blk_mid = max(1, min(blk_mid, N_total_sym));
                        h_td_blk = zeros(1, blk_fft);
                        for p = 1:K_sparse
                            h_td_blk(eff_delays(p)+1) = h_tv_bem(p, blk_mid);
                        end
                        H_cur{bi} = fft(h_td_blk);
                    end
                    bem_done = true;
                end
            catch
                % BEM 失败 → 回退到下面的 per-block 判决辅助估计
            end
        end

        % --- 原 V2.1: per-block 判决辅助 H 更新（BEM 未成功时的 fallback）---
        if ~bem_done
            for bi = 1:N_data_blocks
                if titer >= 2 && var_x_blks(bi) < 0.5
                    X_bar = fft(x_bar_blks{bi});
                    H_dd = Y_freq_blocks{bi} .* conj(X_bar) ./ (abs(X_bar).^2 + nv_eq);
                    H_cur{bi} = H_dd;
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
    blk_idx = data_block_indices(bi);
    blk = rx_sym_all((blk_idx-1)*sym_per_block + blk_cp + 1 : blk_idx*sym_per_block);
    pre_eq_syms = [pre_eq_syms, blk]; %#ok<AGROW>
end
info.pre_eq_syms = pre_eq_syms;
info.post_eq_syms = eq_syms_iters{end};
info.eq_syms_iters = eq_syms_iters;

end


%% ============================================================
%% 辅助: 构造 ch_est_bem 的观测矩阵（多训练块协议版）
%% V4.0 (2026-04-26 Phase 4 方案 A)
%% ============================================================
function [obs_y, obs_x, obs_n] = build_bem_observations(rx_sym_all, ...
    train_cp, x_bar_blks_data, blk_cp, blk_fft, sym_per_block, ...
    N_total_sym, sym_delays, K_sparse, ...
    train_block_indices, data_block_indices)

obs_y = []; obs_x = []; obs_n = [];
max_tau = max(sym_delays);

% 预分配 block_kind: 0=空, 1=train, d+1=第 d 个 data
N_blocks_total = floor(N_total_sym / sym_per_block);
block_kind = zeros(1, N_blocks_total);
for ti = 1:length(train_block_indices)
    block_kind(train_block_indices(ti)) = 1;
end
for di = 1:length(data_block_indices)
    block_kind(data_block_indices(di)) = di + 1;
end

% 1. 所有训练块的 CP 段（用 train_cp）
for ti = 1:length(train_block_indices)
    blk_global = train_block_indices(ti);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = max_tau+1 : blk_cp
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            x_vec(pp) = lookup_x_at_idx(idx, sym_per_block, blk_cp, blk_fft, ...
                                         block_kind, train_cp, x_bar_blks_data, N_total_sym);
        end
        if any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
            obs_x = [obs_x; x_vec];        %#ok<AGROW>
            obs_n(end+1) = n;              %#ok<AGROW>
        end
    end
end

% 2. 所有数据块的 CP 段（用 Turbo 软符号 x_bar_blks_data）
for di = 1:length(data_block_indices)
    blk_global = data_block_indices(di);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = max_tau+1 : blk_cp
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            x_vec(pp) = lookup_x_at_idx(idx, sym_per_block, blk_cp, blk_fft, ...
                                         block_kind, train_cp, x_bar_blks_data, N_total_sym);
        end
        if any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
            obs_x = [obs_x; x_vec];        %#ok<AGROW>
            obs_n(end+1) = n;              %#ok<AGROW>
        end
    end
end

end


%% ============================================================
%% lookup 函数：给定 idx 返回对应 x 值（train_cp 或 x_bar_blks_data）
%% ============================================================
function x_val = lookup_x_at_idx(idx, sym_per_block, blk_cp, blk_fft, ...
                                  block_kind, train_cp, x_bar_blks_data, N_total_sym)

if idx < 1 || idx > N_total_sym
    x_val = 0; return;
end
blk_global = floor((idx - 1) / sym_per_block) + 1;  % 1-based
local_n = idx - (blk_global - 1) * sym_per_block;
if blk_global > length(block_kind)
    x_val = 0; return;
end
kind = block_kind(blk_global);

if kind == 1
    if local_n >= 1 && local_n <= length(train_cp)
        x_val = train_cp(local_n);
    else
        x_val = 0;
    end
elseif kind >= 2
    d = kind - 1;
    xb = x_bar_blks_data{d};
    if local_n <= blk_cp
        cp_src = blk_fft - blk_cp + local_n;
        if cp_src >= 1 && cp_src <= blk_fft
            x_val = xb(cp_src);
        else
            x_val = 0;
        end
    else
        data_idx = local_n - blk_cp;
        if data_idx >= 1 && data_idx <= blk_fft
            x_val = xb(data_idx);
        else
            x_val = 0;
        end
    end
else
    x_val = 0;
end

end


%% ============================================================
%% Phase 5 (V4.1): pre-Turbo BEM 观测构造（pure pilot only）
%% 用：所有 train block + 每 data block 末 pilot 段
%% 不依赖 Turbo 软符号
%% ============================================================
function [obs_y, obs_x, obs_n] = build_bem_obs_pretturbo( ...
    rx_sym_all, train_cp, pilot_seq, ...
    blk_cp, blk_fft, sym_per_block, N_total_sym, ...
    sym_delays, K_sparse, ...
    train_block_indices, data_block_indices, N_pilot_per_blk)

obs_y = []; obs_x = []; obs_n = [];
N_data_per_blk = blk_fft - N_pilot_per_blk;
max_tau = max(sym_delays);
N_blocks_total = floor(N_total_sym / sym_per_block);

block_kind = zeros(1, N_blocks_total);
for ti = 1:length(train_block_indices)
    block_kind(train_block_indices(ti)) = 1;
end
for di = 1:length(data_block_indices)
    block_kind(data_block_indices(di)) = 2;
end

% 1. Train block CP 段
for ti = 1:length(train_block_indices)
    blk_global = train_block_indices(ti);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = max_tau+1 : blk_cp
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        all_known = true;
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            [v, k] = lookup_known_pretturbo(idx, sym_per_block, blk_cp, blk_fft, ...
                                   block_kind, train_cp, pilot_seq, ...
                                   N_pilot_per_blk, N_data_per_blk, N_total_sym);
            x_vec(pp) = v;
            if ~k, all_known = false; break; end
        end
        if all_known && any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
            obs_x = [obs_x; x_vec];        %#ok<AGROW>
            obs_n(end+1) = n;              %#ok<AGROW>
        end
    end
end

% 2. Data block CP 段
for di = 1:length(data_block_indices)
    blk_global = data_block_indices(di);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = max_tau+1 : blk_cp
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        all_known = true;
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            [v, k] = lookup_known_pretturbo(idx, sym_per_block, blk_cp, blk_fft, ...
                                   block_kind, train_cp, pilot_seq, ...
                                   N_pilot_per_blk, N_data_per_blk, N_total_sym);
            x_vec(pp) = v;
            if ~k, all_known = false; break; end
        end
        if all_known && any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
            obs_x = [obs_x; x_vec];        %#ok<AGROW>
            obs_n(end+1) = n;              %#ok<AGROW>
        end
    end
end

% 3. Data block pilot tail 段
pilot_local_start = blk_cp + N_data_per_blk + 1;
for di = 1:length(data_block_indices)
    blk_global = data_block_indices(di);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = pilot_local_start : sym_per_block
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        all_known = true;
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            [v, k] = lookup_known_pretturbo(idx, sym_per_block, blk_cp, blk_fft, ...
                                   block_kind, train_cp, pilot_seq, ...
                                   N_pilot_per_blk, N_data_per_blk, N_total_sym);
            x_vec(pp) = v;
            if ~k, all_known = false; break; end
        end
        if all_known && any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
            obs_x = [obs_x; x_vec];        %#ok<AGROW>
            obs_n(end+1) = n;              %#ok<AGROW>
        end
    end
end

obs_y = obs_y(:).';
obs_n = obs_n(:).';

end


function [x_val, known] = lookup_known_pretturbo(idx, sym_per_block, blk_cp, blk_fft, ...
                                  block_kind, train_cp, pilot_seq, ...
                                  N_pilot_per_blk, N_data_per_blk, N_total_sym)

if idx < 1 || idx > N_total_sym
    x_val = 0; known = false; return;
end
blk_global = floor((idx - 1) / sym_per_block) + 1;
local_n = idx - (blk_global - 1) * sym_per_block;
if blk_global > length(block_kind)
    x_val = 0; known = false; return;
end
kind = block_kind(blk_global);

if kind == 1
    if local_n >= 1 && local_n <= length(train_cp)
        x_val = train_cp(local_n);
        known = true;
    else
        x_val = 0; known = false;
    end
elseif kind == 2
    if local_n >= 1 && local_n <= blk_cp
        if local_n >= blk_cp - N_pilot_per_blk + 1
            pilot_idx = local_n - (blk_cp - N_pilot_per_blk);
            if pilot_idx >= 1 && pilot_idx <= N_pilot_per_blk
                x_val = pilot_seq(pilot_idx);
                known = true;
            else
                x_val = 0; known = false;
            end
        else
            x_val = 0; known = false;
        end
    elseif local_n >= blk_cp + 1 && local_n <= blk_cp + N_data_per_blk
        x_val = 0; known = false;
    elseif local_n >= blk_cp + N_data_per_blk + 1 && local_n <= sym_per_block
        pilot_idx = local_n - (blk_cp + N_data_per_blk);
        if pilot_idx >= 1 && pilot_idx <= N_pilot_per_blk
            x_val = pilot_seq(pilot_idx);
            known = true;
        else
            x_val = 0; known = false;
        end
    else
        x_val = 0; known = false;
    end
else
    x_val = 0; known = false;
end

end
