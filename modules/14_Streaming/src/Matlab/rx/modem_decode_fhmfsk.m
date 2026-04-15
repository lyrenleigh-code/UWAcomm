function [bits, info] = modem_decode_fhmfsk(body_bb, sys, meta)
% 功能：FH-MFSK 解调（FFT 能量检测 + 去跳频 + 解交织 + 硬判决 Viterbi）
% 版本：V1.0.0（P1 临时命名，P3 统一 API）
% 输入：
%   body_bb - 基带复信号（已下变频+LFM 精确定时，长度 ≈ N_sym*samples_per_sym）
%   sys     - 系统参数
%   meta    - TX 侧 modem_encode_fhmfsk 产出的元数据（N_sym, hop_pattern, M_coded, N_info）
% 输出：
%   bits - 信息比特 (1×N_info)
%   info - 结构体
%       .energy_matrix      N_sym × num_freqs
%       .detected_indices   0..M-1
%       .N_info_out         = length(bits)
%
% 依赖：
%   02_ChannelCoding/siso_decode_conv
%   03_Interleaving/random_interleave, random_deinterleave

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

% ---- 1. FFT 能量检测（每 sym 一个 FFT，长度 = samples_per_sym） ----
% 基带频率对应的 FFT bin
fft_bin_idx = mod(round(cfg.fb_base * cfg.samples_per_sym / sys.fs), cfg.samples_per_sym) + 1;

energy_matrix = zeros(N_sym, cfg.num_freqs);
for k = 1:N_sym
    seg = body_bb((k-1)*cfg.samples_per_sym+1 : k*cfg.samples_per_sym);
    psd = abs(fft(seg, cfg.samples_per_sym)).^2;
    energy_matrix(k, :) = psd(fft_bin_idx);
end

% ---- 2. 去跳频（循环移位回 0..M-1 窗口，取能量最大） ----
detected_indices = zeros(1, N_sym);
for k = 1:N_sym
    shift = meta.hop_pattern(k);
    e_shifted = circshift(energy_matrix(k, :), -shift);
    [~, idx_max] = max(e_shifted(1:cfg.M));
    detected_indices(k) = idx_max - 1;   % 0-based
end

% ---- 3. 解映射 → 比特 ----
detected_bits = zeros(1, N_sym * cfg.bits_per_sym);
for k = 1:N_sym
    b3 = de2bi(detected_indices(k), cfg.bits_per_sym, 'left-msb');
    detected_bits((k-1)*cfg.bits_per_sym+1 : k*cfg.bits_per_sym) = b3;
end
detected_bits = detected_bits(1:meta.M_coded);

% ---- 4. 解交织 ----
[~, perm] = random_interleave(zeros(1, meta.M_coded), codec.interleave_seed);
deint_bits = random_deinterleave(detected_bits, perm);

% ---- 5. 硬判决 → LLR → Viterbi 译码 ----
hard_llr = (2*deint_bits - 1) * 10;  % bit=1→+10, bit=0→-10
[~, Lp_info, ~] = siso_decode_conv(hard_llr, [], codec.gen_polys, ...
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
info.N_info_out       = length(bits);

end
