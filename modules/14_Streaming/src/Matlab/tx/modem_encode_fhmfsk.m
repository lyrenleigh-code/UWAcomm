function [body_bb, meta] = modem_encode_fhmfsk(bits, sys)
% 功能：FH-MFSK 调制（编码+交织+8FSK映射+跳频+基带复指数波形）
% 版本：V1.0.0（P1 临时命名，P3 改为统一 API modem_encode(bits, 'FH-MFSK', sys)）
% 输入：
%   bits - 要发射的全部比特（含 header + payload + crc，已非编码）
%   sys  - 系统参数（使用 sys.fhmfsk.*, sys.codec.*, sys.fs）
% 输出：
%   body_bb - 基带复信号 (1×N)
%   meta    - struct
%       .M_coded         卷积编码后比特数
%       .N_sym           FSK 符号数
%       .N_pad           符号映射前补零位数
%       .samples_per_sym
%       .hop_pattern     跳频序列（RX 需要同款才能解跳）
%       .N_info          原始输入比特数（= length(bits)）
%
% 依赖：
%   02_ChannelCoding/conv_encode
%   03_Interleaving/random_interleave
%   05_SpreadSpectrum/gen_hop_pattern, fh_spread

cfg = sys.fhmfsk;
codec = sys.codec;
bits = bits(:).';

N_info = length(bits);

% ---- 1. 卷积编码 ----
coded = conv_encode(bits, codec.gen_polys, codec.constraint_len);
M_coded = length(coded);

% ---- 2. 交织 ----
[interleaved, ~] = random_interleave(coded, codec.interleave_seed);

% ---- 3. 补齐到 bits_per_sym 整数倍 ----
N_sym = ceil(M_coded / cfg.bits_per_sym);
N_pad = N_sym * cfg.bits_per_sym - M_coded;
coded_padded = [interleaved, zeros(1, N_pad)];

% ---- 4. 8-FSK 映射（每 3 bit → freq_index 0..7） ----
freq_indices = zeros(1, N_sym);
for k = 1:N_sym
    b3 = coded_padded((k-1)*cfg.bits_per_sym+1 : k*cfg.bits_per_sym);
    freq_indices(k) = bi2de(b3, 'left-msb');
end

% ---- 5. 跳频（freq_index 在 16 个跳频位中循环移位） ----
hop_pattern = gen_hop_pattern(N_sym, cfg.num_freqs, cfg.hop_seed);
hopped = fh_spread(freq_indices, hop_pattern, cfg.num_freqs);   % 0-based

% ---- 6. 基带 FSK 波形（复指数，相位连续） ----
N_samples = N_sym * cfg.samples_per_sym;
body_bb = zeros(1, N_samples);
t_sym = (0:cfg.samples_per_sym-1) / sys.fs;
phase_acc = 0;
for k = 1:N_sym
    f_k = cfg.fb_base(hopped(k) + 1);   % 基带频率
    seg = exp(1j * (2*pi*f_k*t_sym + phase_acc));
    body_bb((k-1)*cfg.samples_per_sym+1 : k*cfg.samples_per_sym) = seg;
    phase_acc = phase_acc + 2*pi*f_k * cfg.samples_per_sym / sys.fs;
end

% ---- meta ----
meta = struct();
meta.M_coded         = M_coded;
meta.N_sym           = N_sym;
meta.N_pad           = N_pad;
meta.samples_per_sym = cfg.samples_per_sym;
meta.hop_pattern     = hop_pattern;
meta.N_info          = N_info;
meta.N_shaped        = N_samples;   % 2026-04-30: 与其他 5 体制 meta 对齐，供 P4 UI 通带路径切 body_bb_rx

end
