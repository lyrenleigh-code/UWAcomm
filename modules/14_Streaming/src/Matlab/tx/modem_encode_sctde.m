function [body_bb, meta] = modem_encode_sctde(bits, sys)
% 功能：SC-TDE TX（编码+交织+QPSK+训练序列+[散布导频]+RRC成形 → 基带 body）
% 版本：V1.0.0（P3.2 从 13_SourceCode/tests/SC-TDE/test_sctde_timevarying.m 抽取）
% 输入：
%   bits - 1×N_info 信息比特（含 header+payload+crc，已由上游组装）
%   sys  - 系统参数（用 sys.codec, sys.sctde, sys.sps）
% 输出：
%   body_bb - 基带复信号 (1×M)，RRC 成形后
%   meta    - struct
%       .N_info              原始输入比特数
%       .training            训练序列 (1×train_len 复数)
%       .known_map           逻辑数组，标记训练+导频位置
%       .pilot_positions     散布导频在 tx_sym 中的起始位置（时变用）
%       .pilot_sym_ref       导频簇参考符号
%       .all_sym             全部 TX 符号（训练+数据+导频）
%       .perm_all            交织置换
%       .train_len           训练序列长度
%       .N_data_sym          数据段总长（含导频占位）
%       .N_total_sym         all_sym 长度
%       .N_shaped            RRC 成形后样本数
%       .pilot_sym           首 10 个 TX 已知符号（符号定时 hint）
%       .M_coded             编码后比特数
%       .data_only_idx       数据段中非导频位置索引
%
% 依赖：
%   02_ChannelCoding/conv_encode
%   03_Interleaving/random_interleave
%   09_Waveform/pulse_shape

cfg   = sys.sctde;
codec = sys.codec;
bits  = bits(:).';
N_info_orig = length(bits);

%% ---- 1. 参数 ----
train_len         = cfg.train_len;
pilot_cluster_len = cfg.pilot_cluster_len;
pilot_spacing     = cfg.pilot_spacing;
n_code            = 2;
mem               = codec.constraint_len - 1;

constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);

%% ---- 2. 训练序列（固定 seed=99）----
rng_st = rng;
rng(99);
training = constellation(randi(4, 1, train_len));
pilot_sym_ref = constellation(randi(4, 1, pilot_cluster_len));
rng(rng_st);

%% ---- 3. 信源编码 ----
is_timevarying = ~strcmpi(cfg.fading_type, 'static');

if is_timevarying
    % 时变：数据段含散布导频，有效数据减少
    N_data_sym = 2000;  % 数据段总长（含导频）
    N_pilot_clusters = floor(N_data_sym / (pilot_spacing + pilot_cluster_len));
    N_total_pilots   = N_pilot_clusters * pilot_cluster_len;
    N_data_actual    = N_data_sym - N_total_pilots;
    M_coded          = 2 * N_data_actual;
    N_info_needed    = M_coded / n_code - mem;
else
    N_data_sym    = 2000;
    M_coded       = 2 * N_data_sym;
    N_info_needed = M_coded / n_code - mem;
    N_pilot_clusters = 0;
    N_total_pilots   = 0;
    N_data_actual    = N_data_sym;
end

% 比特对齐
if N_info_orig < N_info_needed
    bits = [bits, zeros(1, N_info_needed - N_info_orig)];
elseif N_info_orig > N_info_needed
    bits = bits(1:N_info_needed);
end

%% ---- 4. 卷积编码 + 交织 + QPSK ----
coded = conv_encode(bits, codec.gen_polys, codec.constraint_len);
coded = coded(1:M_coded);
[inter_all, perm_all] = random_interleave(coded, codec.interleave_seed);
idx_qpsk = bi2de(reshape(inter_all, 2, []).', 'left-msb') + 1;
data_sym = constellation(idx_qpsk);

%% ---- 5. 组装 TX 符号流 ----
if is_timevarying
    % 在数据段中插入散布导频簇
    mixed_seg = zeros(1, N_data_sym);
    known_seg = false(1, N_data_sym);
    pilot_positions = zeros(1, N_pilot_clusters);
    d_idx = 0; pos = 1;
    for kk = 1:N_pilot_clusters
        pilot_start = (kk-1) * pilot_spacing + 1;
        n_data_fill = pilot_start - pos;
        if n_data_fill > 0 && d_idx + n_data_fill <= N_data_actual
            mixed_seg(pos : pos+n_data_fill-1) = data_sym(d_idx+1 : d_idx+n_data_fill);
            d_idx = d_idx + n_data_fill;
            pos = pos + n_data_fill;
        end
        if pos + pilot_cluster_len - 1 <= N_data_sym
            mixed_seg(pos : pos+pilot_cluster_len-1) = pilot_sym_ref;
            known_seg(pos : pos+pilot_cluster_len-1) = true;
            pilot_positions(kk) = train_len + pos;
            pos = pos + pilot_cluster_len;
        end
    end
    n_remain = N_data_actual - d_idx;
    if n_remain > 0 && pos + n_remain - 1 <= N_data_sym
        mixed_seg(pos : pos+n_remain-1) = data_sym(d_idx+1 : d_idx+n_remain);
        pos = pos + n_remain;
    end
    mixed_seg = mixed_seg(1:pos-1);
    known_seg = known_seg(1:pos-1);

    tx_sym    = [training, mixed_seg];
    known_map = [true(1, train_len), known_seg];
else
    tx_sym    = [training, data_sym];
    known_map = [true(1, train_len), false(1, N_data_sym)];
    pilot_positions = [];
end

%% ---- 6. RRC 成形 ----
[shaped_bb, ~, ~] = pulse_shape(tx_sym, sys.sps, 'rrc', cfg.rolloff, cfg.span);
body_bb = shaped_bb(:).';

%% ---- 7. meta ----
data_only_idx = find(~known_map(train_len+1:end));

meta = struct();
meta.N_info          = N_info_orig;
% 去oracle：training/pilot_sym_ref/pilot_sym/all_sym 由 RX 本地重生成
meta.known_map       = known_map;
meta.pilot_positions = pilot_positions;
meta.perm_all        = perm_all;
meta.train_len       = train_len;
meta.N_data_sym      = length(tx_sym) - train_len;
meta.N_total_sym     = length(tx_sym);
meta.N_shaped        = length(body_bb);
meta.M_coded         = M_coded;
meta.data_only_idx   = data_only_idx;

end
