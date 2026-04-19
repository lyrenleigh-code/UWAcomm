function [body_bb, meta] = modem_encode_dsss(bits, sys)
% 功能：DSSS TX（编码+交织+DBPSK差分编码+Gold扩频+RRC成形 → 基带 body）
% 版本：V1.0.0（P3.3 从 13_SourceCode/tests/DSSS/test_dsss_timevarying.m 抽取）
% 输入：
%   bits - 1×N_info 信息比特
%   sys  - 系统参数（用 sys.codec, sys.dsss, sys.sps）
% 输出：
%   body_bb - 基带复信号 (1×M)，RRC 成形后（采样率 = chip_rate * sps）
%   meta    - struct
%       .N_info              原始输入比特数
%       .gold_code           Gold 扩频码（±1）
%       .training            训练符号序列（±1）
%       .perm_all            交织置换
%       .train_len           训练符号数
%       .N_data_sym          数据符号数（含参考符号）
%       .N_total_chips       总码片数（训练+数据）
%       .code_len            码长 L
%       .N_shaped            RRC 成形后样本数
%       .pilot_sym           首段训练码片（符号定时 hint）
%
% 依赖：
%   02_ChannelCoding/conv_encode
%   03_Interleaving/random_interleave
%   05_SpreadSpectrum/gen_gold_code, dsss_spread
%   09_Waveform/pulse_shape

cfg   = sys.dsss;
codec = sys.codec;
bits  = bits(:).';
N_info = length(bits);

%% ---- 1. 参数派生 ----
L         = cfg.code_len;                  % 31
train_len = cfg.train_len;                 % 100
n_code    = 2;
mem       = codec.constraint_len - 1;

%% ---- 2. 编码长度计算 ----
% 卷积码率 1/2，编码后长度 = 2*(N_info_pad + mem)
% DBPSK: M_coded 个编码比特 → M_coded+1 个差分符号（+1 参考符号）
M_coded_target = n_code * (N_info + mem);
N_info_needed  = M_coded_target / n_code - mem;
if N_info < N_info_needed
    rng_st = rng; rng(42);
    bits = [bits, randi([0 1], 1, N_info_needed - N_info)];
    rng(rng_st);
elseif N_info > N_info_needed
    bits = bits(1:N_info_needed);
end
M_coded = n_code * (length(bits) + mem);

%% ---- 3. 卷积编码 + 截断 ----
coded = conv_encode(bits, codec.gen_polys, codec.constraint_len);
coded = coded(1:M_coded);

%% ---- 4. 交织 ----
[interleaved, perm_all] = random_interleave(coded, codec.interleave_seed);

%% ---- 5. DBPSK 差分编码 ----
% d(0) = 1 (参考), d(k) = b(k) XOR d(k-1)
diff_encoded = zeros(1, M_coded + 1);
diff_encoded(1) = 1;  % 参考比特
for k = 1:M_coded
    diff_encoded(k+1) = xor(interleaved(k), diff_encoded(k));
end
data_sym = 2 * diff_encoded - 1;  % BPSK 映射: 0→-1, 1→+1
N_data_sym = length(data_sym);     % M_coded + 1

%% ---- 6. Gold 码生成 ----
gold_01 = gen_gold_code(cfg.code_poly(1), cfg.code_poly(2));
gold_code = 2 * gold_01 - 1;     % 转为 ±1

%% ---- 7. 训练序列（固定种子，±1） ----
rng_st = rng; rng(88);
training = 2 * randi([0 1], 1, train_len) - 1;
rng(rng_st);

%% ---- 8. 扩频 ----
train_spread = dsss_spread(training, gold_code);
data_spread  = dsss_spread(data_sym, gold_code);
all_chips    = [train_spread, data_spread];
N_total_chips = length(all_chips);

%% ---- 9. RRC 成形 ----
[shaped_bb, ~, ~] = pulse_shape(all_chips, cfg.sps, 'rrc', cfg.rolloff, cfg.span);
body_bb = shaped_bb(:).';

%% ---- meta ----
meta = struct();
meta.N_info        = N_info;
meta.M_coded       = M_coded;
% 去oracle：gold_code/training/pilot_sym 由 RX 本地重生成，不再导出
meta.perm_all      = perm_all;
meta.train_len     = train_len;
meta.N_data_sym    = N_data_sym;
meta.N_total_chips = N_total_chips;
meta.code_len      = L;
meta.N_shaped      = length(body_bb);

end
