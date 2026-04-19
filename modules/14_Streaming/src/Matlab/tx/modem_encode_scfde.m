function [body_bb, meta] = modem_encode_scfde(bits, sys)
% 功能：SC-FDE TX（编码+交织+QPSK+训练块+分块加CP+RRC成形 → 基带 body）
% 版本：V2.0.0（去oracle：block 1 为训练块，blocks 2~N 为数据）
% 输入：
%   bits - 1×N_info 信息比特
%   sys  - 系统参数（用 sys.codec, sys.scfde, sys.sps）
% 输出：
%   body_bb - 基带复信号 (1×M)，RRC 成形后
%   meta    - struct（不含 all_cp_data，去 oracle）
%
% 依赖：
%   02_ChannelCoding/conv_encode
%   03_Interleaving/random_interleave
%   09_Waveform/pulse_shape

cfg   = sys.scfde;
codec = sys.codec;
bits  = bits(:).';
N_info = length(bits);

%% ---- 1. 参数派生 ----
blk_fft   = cfg.blk_fft;
blk_cp    = cfg.blk_cp;
N_blocks  = cfg.N_blocks;
sym_per_block = blk_cp + blk_fft;
M_per_blk = 2 * blk_fft;                % QPSK: 2 bits/symbol

% block 1 = 训练块，不承载数据；数据块 = N_blocks - 1
N_data_blocks = N_blocks - 1;
M_total   = M_per_blk * N_data_blocks;
n_code    = 2;
mem       = codec.constraint_len - 1;

%% ---- 2. 训练块生成（seed=77，RX 可独立重生成）----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
rng_st = rng;
rng(77);
train_sym = constellation(randi(4, 1, blk_fft));
rng(rng_st);

%% ---- 3. 信息比特对齐 ----
N_info_needed = M_total / n_code - mem;
if N_info < N_info_needed
    bits = [bits, zeros(1, N_info_needed - N_info)];
elseif N_info > N_info_needed
    bits = bits(1:N_info_needed);
end

%% ---- 4. 卷积编码 + 截断 ----
coded = conv_encode(bits, codec.gen_polys, codec.constraint_len);
coded = coded(1:M_total);

%% ---- 5. 交织 ----
[inter_all, perm_all] = random_interleave(coded, codec.interleave_seed);

%% ---- 6. QPSK 映射 ----
idx_qpsk = bi2de(reshape(inter_all, 2, []).', 'left-msb') + 1;
sym_all = constellation(idx_qpsk);

%% ---- 7. 分块 + CP（block 1 = 训练，blocks 2~N = 数据）----
all_cp_data = zeros(1, N_blocks * sym_per_block);

% Block 1: 训练块
train_cp = [train_sym(end-blk_cp+1:end), train_sym];
all_cp_data(1:sym_per_block) = train_cp;

% Blocks 2~N: 数据块
for bi = 1:N_data_blocks
    data_sym = sym_all((bi-1)*blk_fft+1 : bi*blk_fft);
    x_cp = [data_sym(end-blk_cp+1:end), data_sym];
    all_cp_data(bi*sym_per_block+1 : (bi+1)*sym_per_block) = x_cp;
end

%% ---- 8. RRC 成形 ----
[shaped_bb, ~, ~] = pulse_shape(all_cp_data, sys.sps, 'rrc', cfg.rolloff, cfg.span);
body_bb = shaped_bb(:).';

%% ---- meta（去 oracle：不含 all_cp_data）----
meta = struct();
meta.N_info         = N_info;
meta.M_total        = M_total;
meta.M_per_blk      = M_per_blk;
meta.perm_all       = perm_all;
meta.N_total_sym    = length(all_cp_data);
meta.blk_fft        = blk_fft;
meta.blk_cp         = blk_cp;
meta.N_blocks       = N_blocks;
meta.N_data_blocks  = N_data_blocks;
meta.sym_per_block  = sym_per_block;
meta.N_shaped       = length(body_bb);
meta.train_seed     = 77;   % RX 重生成用

end
