function [body_bb, meta] = modem_encode_ofdm(bits, sys)
% 功能：OFDM TX（编码+交织+QPSK+空子载波分配+ofdm_modulate+RRC成形 → 基带 body）
% 版本：V1.0.0（P3.2 从 13_SourceCode/tests/OFDM/test_ofdm_timevarying.m 抽取）
% 输入：
%   bits - 1×N_info 信息比特（含 header+payload+crc，已由上游组装）
%   sys  - 系统参数（用 sys.codec, sys.ofdm, sys.sps）
% 输出：
%   body_bb - 基带复信号 (1×M)，RRC 成形后
%   meta    - struct
%       .N_info                原始输入比特数
%       .M_total               编码后比特数（对齐到 N_blocks*N_data_sc*2）
%       .M_per_blk             每块 coded bits 数 = 2*N_data_sc
%       .perm_all              全局交织置换
%       .all_cp_data           分块+CP 后的符号流（RX 信道估计需要）
%       .N_total_sym           all_cp_data 长度
%       .blk_fft/blk_cp/N_blocks  分块参数
%       .sym_per_block         blk_cp + blk_fft
%       .null_idx              空子载波索引 (1-based)
%       .data_idx              数据子载波索引 (1-based)
%       .N_shaped              RRC 成形后的样本数
%       .pilot_sym             首 10 个 TX 已知符号（符号定时 hint）
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

M_per_blk = 2 * N_data_sc;           % QPSK: 2 bits/symbol, 仅数据子载波
M_total   = M_per_blk * N_blocks;
n_code    = 2;
mem       = codec.constraint_len - 1;

%% ---- 2. 信息比特对齐到可用长度 ----
N_info_needed = M_total / n_code - mem;
if N_info < N_info_needed
    bits = [bits, zeros(1, N_info_needed - N_info)];
elseif N_info > N_info_needed
    bits = bits(1:N_info_needed);
end

%% ---- 3. 卷积编码 + 截断 ----
coded = conv_encode(bits, codec.gen_polys, codec.constraint_len);
coded = coded(1:M_total);

%% ---- 4. 交织 ----
[inter_all, perm_all] = random_interleave(coded, codec.interleave_seed);

%% ---- 5. QPSK 映射 ----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
idx_qpsk = bi2de(reshape(inter_all, 2, []).', 'left-msb') + 1;
sym_all  = constellation(idx_qpsk);

%% ---- 6. OFDM 调制：数据映射 + ofdm_modulate 逐块 ----
all_cp_data = zeros(1, N_blocks * sym_per_block);
for bi = 1:N_blocks
    data_sym = sym_all((bi-1)*N_data_sc+1 : bi*N_data_sc);
    freq_sym = zeros(1, blk_fft);
    freq_sym(data_idx) = data_sym;          % 数据子载波
    % null_idx 保持 0（空子载波）
    [x_ofdm, ~] = ofdm_modulate(freq_sym, blk_fft, blk_cp, 'cp');
    all_cp_data((bi-1)*sym_per_block+1 : bi*sym_per_block) = x_ofdm;
end

%% ---- 7. RRC 成形 ----
[shaped_bb, ~, ~] = pulse_shape(all_cp_data, sys.sps, 'rrc', cfg.rolloff, cfg.span);
body_bb = shaped_bb(:).';

%% ---- meta ----
meta = struct();
meta.N_info        = N_info;
meta.M_total       = M_total;
meta.M_per_blk     = M_per_blk;
meta.perm_all      = perm_all;
meta.all_cp_data   = all_cp_data;
meta.N_total_sym   = length(all_cp_data);
meta.blk_fft       = blk_fft;
meta.blk_cp        = blk_cp;
meta.N_blocks      = N_blocks;
meta.sym_per_block = sym_per_block;
meta.null_idx      = null_idx;
meta.data_idx      = data_idx;
meta.N_shaped      = length(body_bb);
meta.pilot_sym     = all_cp_data(1:min(10, length(all_cp_data)));

end
