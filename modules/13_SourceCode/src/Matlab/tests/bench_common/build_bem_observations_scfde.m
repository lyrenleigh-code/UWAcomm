function [obs_y, obs_x, obs_n] = build_bem_observations_scfde( ...
    rx_sym_all, train_cp, x_bar_blks_data, ...
    blk_cp, blk_fft, sym_per_block, N_total_sym, ...
    sym_delays, K_sparse, ...
    train_block_indices, data_block_indices)
% 功能：构造 SC-FDE BEM 信道估计观测矩阵（多训练块协议版）
% 版本：V2.0.0 (2026-04-26)
% Spec：specs/active/2026-04-26-scfde-time-varying-pilot-arch.md (Phase 4 方案 A)
% 历史：
%   V1.0 (2026-04-25, Phase 3b.1) - 单训练块 + x_bar_blks 全局 index
%   V2.0 (2026-04-26, Phase 4)    - 多训练块 + x_bar_blks data-only index
%
% V2.0 索引方案（与 14_Streaming production 一致）：
%   x_bar_blks_data{1..N_data}     = 数据块软符号（Turbo 反馈）
%   train_block_indices            = 1×N_train，全局 block index（哪些 block 是 train）
%   data_block_indices             = 1×N_data，全局 block index（哪些 block 是 data）
%   train_cp                       = 同一训练序列模板（所有 train block 共用 seed=77）
%
% 输入：
%   rx_sym_all              - 1×N_total_sym 接收符号序列（含 CP）
%   train_cp                - 1×sym_per_block 训练块模板（含 CP，本地重建）
%   x_bar_blks_data         - 1×N_data cell，每元素 1×blk_fft（不含 CP）
%   blk_cp / blk_fft        - 协议参数
%   sym_per_block           - blk_cp + blk_fft
%   N_total_sym             - N_blocks × sym_per_block
%   sym_delays              - 1×K_sparse 多径时延（样本，0-based）
%   K_sparse                - 多径数
%   train_block_indices     - 1×N_train 全局 block index
%   data_block_indices      - 1×N_data 全局 block index
%
% 输出：
%   obs_y - 1×N_obs 观测样本
%   obs_x - N_obs×K_sparse 重构发送符号矩阵
%   obs_n - 1×N_obs 观测时间索引（1-based）
%
% 备注：
%   仅每 block CP 段（n 落在 max_tau+1..blk_cp）作观测点。
%   x_vec 引用的 idx 可能跨块，跨块时 lookup 通过 train/data indices 定位。

%% 1. 入参校验
N_data = length(data_block_indices);
N_train = length(train_block_indices);
assert(iscell(x_bar_blks_data) && length(x_bar_blks_data) == N_data, ...
    sprintf('x_bar_blks_data 长度 %d ≠ N_data %d', length(x_bar_blks_data), N_data));
assert(length(train_cp) >= sym_per_block, 'train_cp 长度必须 >= sym_per_block');
assert(N_train >= 1, 'train_block_indices 至少含 1 个');

%% 2. 初始化
obs_y = [];
obs_x = [];
obs_n = [];
max_tau = max(sym_delays);

% 预分配 map: global block idx → ('train' | data 序号 d)
% 用稀疏向量加速 lookup
N_blocks_total = floor(N_total_sym / sym_per_block);
block_kind = zeros(1, N_blocks_total);  % 0=未知, 1=train, 2..=data 序号 +1（即 d+1）
for ti = 1:N_train
    block_kind(train_block_indices(ti)) = 1;
end
for di = 1:N_data
    block_kind(data_block_indices(di)) = di + 1;  % 偏移 1 区分 train
end

%% 3. 训练块 CP 段观测
for ti = 1:N_train
    blk_global = train_block_indices(ti);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = max_tau+1 : blk_cp
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            x_vec(pp) = lookup_x(idx, sym_per_block, blk_cp, blk_fft, ...
                                  block_kind, train_cp, x_bar_blks_data, N_total_sym);
        end
        if any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n);          %#ok<AGROW>
            obs_x = [obs_x; x_vec];                %#ok<AGROW>
            obs_n(end+1) = n;                      %#ok<AGROW>
        end
    end
end

%% 4. 数据块 CP 段观测
for di = 1:N_data
    blk_global = data_block_indices(di);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = max_tau+1 : blk_cp
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            x_vec(pp) = lookup_x(idx, sym_per_block, blk_cp, blk_fft, ...
                                  block_kind, train_cp, x_bar_blks_data, N_total_sym);
        end
        if any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n);          %#ok<AGROW>
            obs_x = [obs_x; x_vec];                %#ok<AGROW>
            obs_n(end+1) = n;                      %#ok<AGROW>
        end
    end
end

%% 5. 输出整理
obs_y = obs_y(:).';
obs_n = obs_n(:).';

end


%% ============================================================
%% lookup 函数：给定 idx 返回对应 x 值（train_cp 或 x_bar_blks_data）
%% ============================================================
function x_val = lookup_x(idx, sym_per_block, blk_cp, blk_fft, ...
                          block_kind, train_cp, x_bar_blks_data, N_total_sym)

if idx < 1 || idx > N_total_sym
    x_val = 0; return;
end
blk_global = floor((idx - 1) / sym_per_block) + 1;  % 1-based
local_n = idx - (blk_global - 1) * sym_per_block;
if blk_global > length(block_kind)
    x_val = 0; return;
end
kind = block_kind(blk_global);

if kind == 1
    % train block
    if local_n >= 1 && local_n <= length(train_cp)
        x_val = train_cp(local_n);
    else
        x_val = 0;
    end
elseif kind >= 2
    % data block: 第 (kind-1) 个 data
    d = kind - 1;
    xb = x_bar_blks_data{d};
    if local_n <= blk_cp
        % CP 段（data block 末 blk_cp 符号）
        cp_src = blk_fft - blk_cp + local_n;
        if cp_src >= 1 && cp_src <= blk_fft
            x_val = xb(cp_src);
        else
            x_val = 0;
        end
    else
        data_idx = local_n - blk_cp;
        if data_idx >= 1 && data_idx <= blk_fft
            x_val = xb(data_idx);
        else
            x_val = 0;
        end
    end
else
    x_val = 0;
end

end
