function [bits, info] = modem_decode_fhmfsk(body_bb, sys, meta)
% 功能：FH-MFSK 解调（FFT 能量检测 + 去跳频 + 软 LLR + Viterbi 译码）
% 版本：V1.1.0（软判决 LLR 替代硬判决，对 Jakes 衰落鲁棒）
% 输入：
%   body_bb - 基带复信号（已下变频+LFM 精确定时，长度 ≈ N_sym*samples_per_sym）
%   sys     - 系统参数
%   meta    - TX 侧 modem_encode_fhmfsk 产出的元数据（N_sym, hop_pattern, M_coded, N_info）
% 输出：
%   bits - 信息比特 (1×N_info)
%   info - 结构体
%       .energy_matrix      N_sym × num_freqs
%       .detected_indices   0..M-1（硬判决，用于可视化）
%       .soft_llr           1×M_coded LLR（软 bit 信息）
%       .N_info_out         = length(bits)
%
% 软 LLR 公式（非相干 M-FSK）：
%   对 8-FSK 每符号 3 bit，每位 j：
%     LLR(b_j) ≈ (max_e_b1 - max_e_b0) / N0_est
%   其中 max_e_bX 是该位为 X 的所有 M-FSK 符号对应频率的最大能量
%   sign 约定：正→bit=1（与 siso_decode_conv 兼容）

cfg = sys.fhmfsk;
codec = sys.codec;
body_bb = body_bb(:).';

N_sym = meta.N_sym;
N_samples_needed = N_sym * cfg.samples_per_sym;

% ---- 长度对齐 ----
if length(body_bb) < N_samples_needed
    body_bb = [body_bb, zeros(1, N_samples_needed - length(body_bb))];
elseif length(body_bb) > N_samples_needed
    body_bb = body_bb(1:N_samples_needed);
end

% ---- 1. FFT 能量检测 ----
fft_bin_idx = mod(round(cfg.fb_base * cfg.samples_per_sym / sys.fs), cfg.samples_per_sym) + 1;
energy_matrix = zeros(N_sym, cfg.num_freqs);
for k = 1:N_sym
    seg = body_bb((k-1)*cfg.samples_per_sym+1 : k*cfg.samples_per_sym);
    psd = abs(fft(seg, cfg.samples_per_sym)).^2;
    energy_matrix(k, :) = psd(fft_bin_idx);
end

% ---- 2. 去跳频 + 计算软 LLR + 硬判决索引（备份）----
% 预计算 bit-symbol mapping（哪些 M-FSK 符号的 bit j 是 0/1）
M = cfg.M;
bps = cfg.bits_per_sym;
sym_indices = (0:M-1).';
bit_table = zeros(M, bps);   % 行=符号, 列=bit 位（MSB first）
for j = 1:bps
    bit_table(:, j) = bitget(sym_indices, bps - j + 1);
end
sym_with_bit0 = cell(1, bps);
sym_with_bit1 = cell(1, bps);
for j = 1:bps
    sym_with_bit0{j} = find(bit_table(:, j) == 0);   % 1-based for indexing
    sym_with_bit1{j} = find(bit_table(:, j) == 1);
end

soft_llr = zeros(1, N_sym * bps);
detected_indices = zeros(1, N_sym);

for k = 1:N_sym
    shift = meta.hop_pattern(k);
    e_shifted = circshift(energy_matrix(k, :), -shift);
    e_freqs = e_shifted(1:M);   % M 个有效频率的能量

    % 硬判决（兼容旧 info）
    [~, idx_max] = max(e_freqs);
    detected_indices(k) = idx_max - 1;   % 0-based

    % 软 LLR：用本符号 M 个能量值的中位数作为 N0 估计（避免极端值）
    n0_est = max(median(e_freqs), 1e-12);

    for j = 1:bps
        max_e0 = max(e_freqs(sym_with_bit0{j}));
        max_e1 = max(e_freqs(sym_with_bit1{j}));
        % LLR 正→bit=1（与 siso_decode_conv 约定一致）
        soft_llr((k-1)*bps + j) = (max_e1 - max_e0) / n0_est;
    end
end

% trim 到 M_coded
soft_llr = soft_llr(1:meta.M_coded);

% ---- 3. 解交织（直接对 LLR 做置换）----
[~, perm] = random_interleave(zeros(1, meta.M_coded), codec.interleave_seed);
deint_llr = random_deinterleave(soft_llr, perm);

% saturate 防 Viterbi 溢出
deint_llr = max(min(deint_llr, 30), -30);

% ---- 4. SISO Viterbi（软输入）----
[~, Lp_info, ~] = siso_decode_conv(deint_llr, [], codec.gen_polys, ...
    codec.constraint_len, codec.decode_mode);
bits = double(Lp_info > 0);

% trim 到原始信息比特数
N_info = meta.N_info;
if length(bits) >= N_info
    bits = bits(1:N_info);
end

% ---- info ----
info = struct();
info.energy_matrix    = energy_matrix;
info.detected_indices = detected_indices;
info.soft_llr         = soft_llr;
info.N_info_out       = length(bits);

% ---- 统一 API info 字段（P3.1 新增）----
%   estimated_snr   : 用每符号(max_peak / median_noise) 平均估计
%   estimated_ber   : 基于 |LLR| 映射的估计误码率
%   turbo_iter      : FH-MFSK 非 Turbo = 0
%   convergence_flag: Viterbi 硬判决无迭代收敛语义；用 |LLR| 充分性 + 0 迭代 = 1
snr_per_sym = zeros(1, N_sym);
hop_peaks   = zeros(1, N_sym);   % 每符号实际选出的最大能量频点（hop tab 用）
hop_peak_val = zeros(1, N_sym);  % 对应峰值幅度
for k = 1:N_sym
    shift = meta.hop_pattern(k);
    e_shifted = circshift(energy_matrix(k, :), -shift);
    e_freqs = e_shifted(1:M);
    [peak, pk_idx] = max(e_freqs);
    hop_peaks(k)    = pk_idx - 1;  % 0..M-1
    hop_peak_val(k) = peak;
    noise = median(e_freqs);
    if noise > 1e-12
        snr_per_sym(k) = 10*log10(peak / noise);
    else
        snr_per_sym(k) = Inf;
    end
end
info.estimated_snr    = mean(snr_per_sym(isfinite(snr_per_sym)));
abs_llr = abs(deint_llr);
p_err   = 0.5 * exp(-abs_llr);   % Q-近似，|LLR| 映射到 BER
info.estimated_ber    = mean(p_err);
info.turbo_iter       = 0;
% 收敛：|LLR| 中位数 > 2（合理置信）= 1，否则 0
info.convergence_flag = double(median(abs_llr) > 2);
% 同步诊断（sync tab 用）：跳频 peak 位置 + 能量矩阵快照
info.hop_peaks       = hop_peaks;
info.hop_peak_val    = hop_peak_val;
info.hop_pattern     = meta.hop_pattern;
info.snr_per_sym     = snr_per_sym;

end
