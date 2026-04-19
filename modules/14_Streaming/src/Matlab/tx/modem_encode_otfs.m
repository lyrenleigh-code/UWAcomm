function [body_bb, meta] = modem_encode_otfs(bits, sys)
% 功能：OTFS TX（编码+交织+QPSK+DD域导频嵌入+OTFS调制 → 基带 body）
% 版本：V1.0.0（P3.3 从 13_SourceCode/tests/OTFS/test_otfs_timevarying.m 抽取）
% 输入：
%   bits - 1×N_info 信息比特
%   sys  - 系统参数（用 sys.codec, sys.otfs）
% 输出：
%   body_bb - 基带复信号 (1×L)，OTFS 调制后（采样率 = sym_rate）
%   meta    - struct
%       .N_info              原始输入比特数
%       .dd_frame            TX DD域帧 (NxM)
%       .perm_all            交织置换
%       .N, .M, .cp_len      OTFS 格点参数
%       .data_indices        数据格点线性索引
%       .pilot_info          导频信息（由 otfs_pilot_embed 返回）
%       .guard_mask          保护区掩模
%       .pilot_sym           DD 域前 10 个数据符号（定时 hint）
%       .N_shaped            输出样本数
%
% 依赖：
%   02_ChannelCoding/conv_encode
%   03_Interleaving/random_interleave
%   06_MultiCarrier/otfs_pilot_embed, otfs_modulate

cfg   = sys.otfs;
codec = sys.codec;
bits  = bits(:).';
N_info = length(bits);

%% ---- 1. 参数派生 ----
N      = cfg.N;
M      = cfg.M;
cp_len = cfg.cp_len;
n_code = 2;
mem    = codec.constraint_len - 1;

%% ---- 2. 导频配置 + 数据格点数 ----
pilot_config = struct('mode', cfg.pilot_mode, ...
    'guard_k', 4, 'guard_l', max(cfg.sym_delays) + 2, ...
    'pilot_value', 1);

% 先用空数据探测可用数据格点数
[~, ~, ~, data_indices] = otfs_pilot_embed(zeros(1,1), N, M, pilot_config);
N_data_slots = length(data_indices);
% 调整导频功率使信道估计 SNR 合理
pilot_config.pilot_value = sqrt(N_data_slots);

%% ---- 3. 编码长度计算 ----
bits_per_sym = 2;  % QPSK
M_coded = N_data_slots * bits_per_sym;
N_info_needed = M_coded / n_code - mem;

if N_info < N_info_needed
    rng_st = rng; rng(42);
    bits = [bits, randi([0 1], 1, N_info_needed - N_info)];
    rng(rng_st);
elseif N_info > N_info_needed
    bits = bits(1:N_info_needed);
end

%% ---- 4. 卷积编码 + 截断 ----
coded = conv_encode(bits, codec.gen_polys, codec.constraint_len);
coded = coded(1:M_coded);

%% ---- 5. 交织 ----
[interleaved, perm_all] = random_interleave(coded, codec.interleave_seed);

%% ---- 6. QPSK 映射 ----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
idx_qpsk = bi2de(reshape(interleaved, 2, []).', 'left-msb') + 1;
data_sym = constellation(idx_qpsk);

%% ---- 7. DD 域导频嵌入 ----
[dd_frame, pilot_info, guard_mask, data_indices] = ...
    otfs_pilot_embed(data_sym, N, M, pilot_config);

%% ---- 8. OTFS 调制 ----
[otfs_signal, ~] = otfs_modulate(dd_frame, N, M, cp_len, 'dft');
body_bb = otfs_signal(:).';

%% ---- meta ----
meta = struct();
meta.N_info       = N_info;
meta.M_coded      = M_coded;
meta.dd_frame     = dd_frame;
meta.perm_all     = perm_all;
meta.N            = N;
meta.M            = M;
meta.cp_len       = cp_len;
meta.data_indices = data_indices;
meta.pilot_info   = pilot_info;
meta.pilot_config = pilot_config;
meta.guard_mask   = guard_mask;
meta.N_data_slots = N_data_slots;
meta.N_shaped     = length(body_bb);
% 去oracle：pilot_sym 不再导出，RX 用 DD 域导频估计

end
