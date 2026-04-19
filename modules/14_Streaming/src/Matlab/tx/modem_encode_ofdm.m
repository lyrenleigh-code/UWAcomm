function [body_bb, meta] = modem_encode_ofdm(bits, sys)
% 功能：OFDM TX（编码+交织+QPSK+导频块+空子载波分配+ofdm_modulate+RRC → 基带）
% 版本：V2.0.0（去oracle：block 1 为全导频 OFDM 符号，blocks 2~N 为数据）
% 输入：
%   bits - 1×N_info 信息比特
%   sys  - 系统参数（用 sys.codec, sys.ofdm, sys.sps）
% 输出：
%   body_bb - 基带复信号 (1×M)，RRC 成形后
%   meta    - struct（不含 all_cp_data，去 oracle）
%
% 依赖：
%   02_ChannelCoding/conv_encode
%   03_Interleaving/random_interleave
%   06_MultiCarrier/ofdm_modulate
%   09_Waveform/pulse_shape

cfg   = sys.ofdm;
codec = sys.codec;
bits  = bits(:).';
N_info = length(bits);

%% ---- 1. 参数派生 ----
blk_fft       = cfg.blk_fft;
blk_cp        = cfg.blk_cp;
N_blocks      = cfg.N_blocks;
null_spacing  = cfg.null_spacing;
sym_per_block = blk_cp + blk_fft;

% 空子载波配置
null_idx  = 1:null_spacing:blk_fft;
data_idx  = setdiff(1:blk_fft, null_idx);
N_data_sc = length(data_idx);

% block 1 = 导频块，不承载数据；数据块 = N_blocks - 1
N_data_blocks = N_blocks - 1;
M_per_blk = 2 * N_data_sc;
M_total   = M_per_blk * N_data_blocks;
n_code    = 2;
mem       = codec.constraint_len - 1;

%% ---- 2. 导频块生成（seed=78，RX 可独立重生成）----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
rng_st = rng;
rng(78);
pilot_freq = zeros(1, blk_fft);
pilot_freq(data_idx) = constellation(randi(4, 1, N_data_sc));  % 数据子载波位置放导频
% null_idx 保持 0
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
sym_all  = constellation(idx_qpsk);

%% ---- 7. OFDM 调制（block 1 = 导频，blocks 2~N = 数据）----
all_cp_data = zeros(1, N_blocks * sym_per_block);

% Block 1: 导频
[x_pilot, ~] = ofdm_modulate(pilot_freq, blk_fft, blk_cp, 'cp');
all_cp_data(1:sym_per_block) = x_pilot;

% Blocks 2~N: 数据
for bi = 1:N_data_blocks
    data_sym = sym_all((bi-1)*N_data_sc+1 : bi*N_data_sc);
    freq_sym = zeros(1, blk_fft);
    freq_sym(data_idx) = data_sym;
    [x_ofdm, ~] = ofdm_modulate(freq_sym, blk_fft, blk_cp, 'cp');
    all_cp_data(bi*sym_per_block+1 : (bi+1)*sym_per_block) = x_ofdm;
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
meta.null_idx       = null_idx;
meta.data_idx       = data_idx;
meta.N_shaped       = length(body_bb);
meta.pilot_seed     = 78;  % RX 重生成用

end
