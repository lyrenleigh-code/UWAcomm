function [body_bb, meta] = modem_encode_scfde(bits, sys)
% 功能：SC-FDE TX（编码+交织+QPSK+多训练块+block-pilot+分块加CP+RRC成形 → 基带 body）
% 版本：V4.0.0（2026-04-26 Phase 5：block-pilot 末尾插入方案 E）
% 历史：
%   V2.0 (2026-04-24, Phase 1+2)  - 单训练块去 oracle
%   V3.0 (2026-04-26, Phase 4)    - cfg.train_period_K 多训练块插入
%   V4.0 (2026-04-26, Phase 5)    - cfg.pilot_per_blk 每 data block 末 pilot 段
%
% 输入：
%   bits - 1×N_info 信息比特
%   sys  - 系统参数（用 sys.codec, sys.scfde, sys.sps）
%          sys.scfde.train_period_K (可选，默认 N_blocks-1 = 单训练块)
%          sys.scfde.pilot_per_blk  (可选，默认 0 = 禁用 block-pilot)
% 输出：
%   body_bb - 基带复信号 (1×M)，RRC 成形后
%   meta    - struct（不含 all_cp_data，去 oracle）

cfg   = sys.scfde;
codec = sys.codec;
bits  = bits(:).';
N_info = length(bits);

%% ---- 1. 参数派生 ----
blk_fft   = cfg.blk_fft;
blk_cp    = cfg.blk_cp;
N_blocks  = cfg.N_blocks;
sym_per_block = blk_cp + blk_fft;

% Phase 5: block-pilot 末尾插入
if isfield(cfg, 'pilot_per_blk') && ~isempty(cfg.pilot_per_blk)
    N_pilot_per_blk = cfg.pilot_per_blk;
else
    N_pilot_per_blk = 0;   % 默认禁用（向后兼容）
end
N_data_per_blk = blk_fft - N_pilot_per_blk;
assert(N_data_per_blk > 0, 'pilot_per_blk 必须 < blk_fft');

M_per_blk = 2 * N_data_per_blk;         % QPSK: 2 bits/symbol（仅 data 槽位编码）
n_code    = 2;
mem       = codec.constraint_len - 1;

%% ---- 1b. 多训练块布局（Phase 4）----
if isfield(cfg, 'train_period_K') && ~isempty(cfg.train_period_K)
    K_train = cfg.train_period_K;
else
    K_train = N_blocks - 1;   % 默认：单训练块（V2.0 向后兼容）
end

if K_train >= N_blocks - 1
    N_train_blocks = 1;
    train_block_indices = 1;
else
    N_train_blocks = floor(N_blocks / (K_train + 1)) + 1;
    train_block_indices = round(linspace(1, N_blocks, N_train_blocks));
    train_block_indices = unique(train_block_indices);
    N_train_blocks = length(train_block_indices);
end
data_block_indices = setdiff(1:N_blocks, train_block_indices);
N_data_blocks = length(data_block_indices);
M_total = M_per_blk * N_data_blocks;

%% ---- 2. 训练块 + block-pilot 序列生成 ----
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
rng_st = rng;
rng(77);
train_sym = constellation(randi(4, 1, blk_fft));
rng(rng_st);
train_cp = [train_sym(end-blk_cp+1:end), train_sym];   % 长度 sym_per_block

% Phase 5：每 data block 末嵌入的 pilot 序列（seed=99，与 train_seed=77 错开）
if N_pilot_per_blk > 0
    rng_st = rng;
    rng(99);
    pilot_seq = constellation(randi(4, 1, N_pilot_per_blk));
    rng(rng_st);
else
    pilot_seq = [];
end

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

%% ---- 7. 帧装填（train block 与 data block 按 indices 分布）----
all_cp_data = zeros(1, N_blocks * sym_per_block);

% 训练块：所有 train_block_indices 位置共用同一 train_cp
for ti = 1:N_train_blocks
    bi = train_block_indices(ti);
    all_cp_data((bi-1)*sym_per_block+1 : bi*sym_per_block) = train_cp;
end

% 数据块：第 di 个数据块对应全局 data_block_indices(di)
% Phase 5：每 data block 末嵌入 N_pilot_per_blk 个 pilot symbol
for di = 1:N_data_blocks
    bi = data_block_indices(di);
    data_sym = sym_all((di-1)*N_data_per_blk+1 : di*N_data_per_blk);
    block_full = [data_sym, pilot_seq];   % blk_fft = N_data_per_blk + N_pilot_per_blk
    x_cp = [block_full(end-blk_cp+1:end), block_full];
    all_cp_data((bi-1)*sym_per_block+1 : bi*sym_per_block) = x_cp;
end

%% ---- 8. RRC 成形 ----
[shaped_bb, ~, ~] = pulse_shape(all_cp_data, sys.sps, 'rrc', cfg.rolloff, cfg.span);
body_bb = shaped_bb(:).';

%% ---- meta（去 oracle：不含 all_cp_data）----
meta = struct();
meta.N_info             = N_info;
meta.M_total            = M_total;
meta.M_per_blk          = M_per_blk;
meta.perm_all           = perm_all;
meta.N_total_sym        = length(all_cp_data);
meta.blk_fft            = blk_fft;
meta.blk_cp             = blk_cp;
meta.N_blocks           = N_blocks;
meta.N_data_blocks      = N_data_blocks;
meta.sym_per_block      = sym_per_block;
meta.N_shaped           = length(body_bb);
meta.train_seed         = 77;
% Phase 4：多训练块协议字段
meta.train_period_K     = K_train;
meta.N_train_blocks     = N_train_blocks;
meta.train_block_indices = train_block_indices;
meta.data_block_indices  = data_block_indices;
% Phase 5：block-pilot 协议字段
meta.pilot_per_blk      = N_pilot_per_blk;
meta.N_data_per_blk     = N_data_per_blk;
meta.pilot_seed         = 99;

end
