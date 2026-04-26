function [obs_y, obs_x, obs_n] = build_bem_obs_pretturbo_scfde( ...
    rx_sym_all, train_cp, pilot_seq, ...
    blk_cp, blk_fft, sym_per_block, N_total_sym, ...
    sym_delays, K_sparse, ...
    train_block_indices, data_block_indices, N_pilot_per_blk)
% 功能：SC-FDE pre-Turbo BEM 观测矩阵（Phase 5 方案 E 方案 — pure pilot only）
% 版本：V1.0.0 (2026-04-26)
% Spec：specs/active/2026-04-26-scfde-time-varying-pilot-arch.md (Phase 5)
%
% 与 build_bem_observations_scfde（mid-Turbo, V2.0）的关键区别：
%   - 不依赖 Turbo 软符号 x_bar_blks（pre-Turbo 阶段，软符号尚未产生）
%   - 仅用：训练块（train_cp 全已知）+ 每 data block 末 pilot 段（pilot_seq 已知）
%   - 跨 idx 跳转时，仅在 idx 落入 train block 或 data block 末 pilot 段时构造 obs
%   - 所有产出 obs 干净（无软符号污染）
%
% 帧 layout（每 data block）：
%   x_cp = [block_full(end-blk_cp+1:end), block_full]
%   block_full = [data_sym, pilot_seq]，长度 blk_fft
%   data_sym = blk_fft - N_pilot_per_blk
% 已知区：
%   - train block：全 sym_per_block 都是 train_cp（local index 1..sym_per_block）
%   - data block：pilot tail = local index [blk_cp + N_data_per_blk + 1, sym_per_block]
%                CP 含 pilot 部分 = local index [blk_cp - N_pilot_per_blk + 1, blk_cp]（当 N_pilot >= blk_cp 全 CP 是 pilot）
%
% 输入：
%   rx_sym_all       - 1×N_total_sym 接收符号
%   train_cp         - 1×sym_per_block 训练块模板
%   pilot_seq        - 1×N_pilot_per_blk pilot 序列模板
%   blk_cp/blk_fft   - 协议参数
%   sym_per_block    - blk_cp + blk_fft
%   N_total_sym      - N_blocks × sym_per_block
%   sym_delays       - 1×K_sparse 时延（样本，0-based）
%   K_sparse         - 多径数
%   train_block_indices, data_block_indices - 全局 block index
%   N_pilot_per_blk  - 每 data block 末嵌入 pilot 长度
%
% 输出：
%   obs_y - 1×N_obs 干净观测样本
%   obs_x - N_obs×K_sparse 干净重构发送符号矩阵
%   obs_n - 1×N_obs 时间索引（1-based）

%% 1. 校验
N_data_per_blk = blk_fft - N_pilot_per_blk;
assert(N_pilot_per_blk > 0, 'pilot_per_blk 必须 > 0（否则用 build_bem_observations_scfde V2.0 mid-Turbo 路径）');
assert(N_data_per_blk >= 0, 'N_data_per_blk = blk_fft - pilot_per_blk 必须 >= 0');

%% 2. 初始化
obs_y = []; obs_x = []; obs_n = [];
max_tau = max(sym_delays);
N_blocks_total = floor(N_total_sym / sym_per_block);

% block_kind: 0=空, 1=train, 2=data
block_kind = zeros(1, N_blocks_total);
for ti = 1:length(train_block_indices)
    block_kind(train_block_indices(ti)) = 1;
end
for di = 1:length(data_block_indices)
    block_kind(data_block_indices(di)) = 2;
end

%% 3. 训练块 CP 段：n ∈ [max_tau+1, blk_cp]
% x_vec[p] 跨 idx 跳转：n-tau_p ∈ [1, blk_cp]，全在当前 train block 内（已知）
for ti = 1:length(train_block_indices)
    blk_global = train_block_indices(ti);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = max_tau+1 : blk_cp
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        all_known = true;
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            [v, k] = lookup_known(idx, sym_per_block, blk_cp, blk_fft, ...
                                   block_kind, train_cp, pilot_seq, ...
                                   N_pilot_per_blk, N_data_per_blk, N_total_sym);
            x_vec(pp) = v;
            if ~k, all_known = false; break; end
        end
        if all_known && any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
            obs_x = [obs_x; x_vec];        %#ok<AGROW>
            obs_n(end+1) = n;              %#ok<AGROW>
        end
    end
end

%% 4. Data block CP 段（部分干净）：n ∈ [max_tau+1, blk_cp]
% CP 段内容 = block_full(end-blk_cp+1:end) = [data 末 (blk_cp-N_pilot), pilot]
%   当 N_pilot >= blk_cp：CP 全 pilot
%   当 N_pilot < blk_cp：CP 前 (blk_cp-N_pilot) 是 data 未知，后 N_pilot 是 pilot 已知
for di = 1:length(data_block_indices)
    blk_global = data_block_indices(di);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = max_tau+1 : blk_cp
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        all_known = true;
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            [v, k] = lookup_known(idx, sym_per_block, blk_cp, blk_fft, ...
                                   block_kind, train_cp, pilot_seq, ...
                                   N_pilot_per_blk, N_data_per_blk, N_total_sym);
            x_vec(pp) = v;
            if ~k, all_known = false; break; end
        end
        if all_known && any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
            obs_x = [obs_x; x_vec];        %#ok<AGROW>
            obs_n(end+1) = n;              %#ok<AGROW>
        end
    end
end

%% 5. Data block pilot tail 段：n ∈ [pilot_local_start, sym_per_block]
% pilot_local_start = blk_cp + N_data_per_blk + 1
pilot_local_start = blk_cp + N_data_per_blk + 1;
for di = 1:length(data_block_indices)
    blk_global = data_block_indices(di);
    blk_start = (blk_global - 1) * sym_per_block;
    for kk = pilot_local_start : sym_per_block
        n = blk_start + kk;
        if n > length(rx_sym_all), continue; end
        x_vec = zeros(1, K_sparse);
        all_known = true;
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            [v, k] = lookup_known(idx, sym_per_block, blk_cp, blk_fft, ...
                                   block_kind, train_cp, pilot_seq, ...
                                   N_pilot_per_blk, N_data_per_blk, N_total_sym);
            x_vec(pp) = v;
            if ~k, all_known = false; break; end
        end
        if all_known && any(x_vec ~= 0)
            obs_y(end+1) = rx_sym_all(n); %#ok<AGROW>
            obs_x = [obs_x; x_vec];        %#ok<AGROW>
            obs_n(end+1) = n;              %#ok<AGROW>
        end
    end
end

obs_y = obs_y(:).';
obs_n = obs_n(:).';

end


%% ============================================================
%% lookup_known: 给定 global idx，返回 (x_val, known)
%% known=true 当 idx 落入已知段（train block 全部 / data block CP 后部 / data block pilot 尾段）
%% ============================================================
function [x_val, known] = lookup_known(idx, sym_per_block, blk_cp, blk_fft, ...
                                  block_kind, train_cp, pilot_seq, ...
                                  N_pilot_per_blk, N_data_per_blk, N_total_sym)

if idx < 1 || idx > N_total_sym
    x_val = 0; known = false; return;
end
blk_global = floor((idx - 1) / sym_per_block) + 1;
local_n = idx - (blk_global - 1) * sym_per_block;
if blk_global > length(block_kind)
    x_val = 0; known = false; return;
end
kind = block_kind(blk_global);

if kind == 1
    % train block: 全已知（local_n 1..sym_per_block 都是 train_cp）
    if local_n >= 1 && local_n <= length(train_cp)
        x_val = train_cp(local_n);
        known = true;
    else
        x_val = 0; known = false;
    end
elseif kind == 2
    % data block:
    %   CP 段 [1, blk_cp]：含 [blk_cp-N_pilot ... blk_cp] 是 pilot 已知
    %     具体：x_cp(local_n) for local_n ∈ [1, blk_cp]
    %       = block_full(blk_fft - blk_cp + local_n)
    %       block_full = [data(N_data), pilot(N_pilot)]
    %       block_full(j) for j ∈ [1, N_data] = data UNKNOWN
    %       block_full(j) for j ∈ [N_data+1, blk_fft] = pilot KNOWN
    %       j = blk_fft - blk_cp + local_n
    %       j > N_data ⟺ local_n > N_data - blk_fft + blk_cp = blk_cp - N_pilot
    %     ⟹ local_n ∈ [blk_cp - N_pilot + 1, blk_cp] → pilot 已知
    %         pilot_idx = j - N_data = blk_fft - blk_cp + local_n - N_data = local_n - (blk_cp - N_pilot)
    %   data 段 [blk_cp+1, blk_cp+N_data]：data 未知
    %   pilot tail [blk_cp+N_data+1, sym_per_block]：pilot 已知
    %         pilot_idx = local_n - (blk_cp + N_data)

    if local_n >= 1 && local_n <= blk_cp
        % CP 段
        if local_n >= blk_cp - N_pilot_per_blk + 1
            % CP 内 pilot 部分
            pilot_idx = local_n - (blk_cp - N_pilot_per_blk);
            if pilot_idx >= 1 && pilot_idx <= N_pilot_per_blk
                x_val = pilot_seq(pilot_idx);
                known = true;
            else
                x_val = 0; known = false;
            end
        else
            % CP 内 data 部分（未知）
            x_val = 0; known = false;
        end
    elseif local_n >= blk_cp + 1 && local_n <= blk_cp + N_data_per_blk
        % data 段（未知）
        x_val = 0; known = false;
    elseif local_n >= blk_cp + N_data_per_blk + 1 && local_n <= sym_per_block
        % pilot tail（已知）
        pilot_idx = local_n - (blk_cp + N_data_per_blk);
        if pilot_idx >= 1 && pilot_idx <= N_pilot_per_blk
            x_val = pilot_seq(pilot_idx);
            known = true;
        else
            x_val = 0; known = false;
        end
    else
        x_val = 0; known = false;
    end
else
    x_val = 0; known = false;
end

end
