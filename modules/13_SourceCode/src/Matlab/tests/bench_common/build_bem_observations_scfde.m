function [obs_y, obs_x, obs_n] = build_bem_observations_scfde( ...
    rx_sym_all, train_cp, x_bar_blks, blk_cp, blk_fft, sym_per_block, ...
    N_blocks, N_total_sym, sym_delays, K_sparse)
% 功能：构造 SC-FDE BEM 信道估计观测矩阵（去 oracle 判决反馈版）
% 版本：V1.0.0 (2026-04-25)
% Spec：specs/active/2026-04-24-scfde-bem-decision-feedback-arch.md (Phase 3b.1)
% 参考：modules/14_Streaming/src/Matlab/rx/modem_decode_scfde.m::build_bem_observations
%
% 13 SourceCode 全局 index 版本（与 14_Streaming 索引方案不同）：
%   x_bar_blks{1}     = train_sym（训练块符号，已知）
%   x_bar_blks{2..N}  = 数据块软符号（Turbo 反馈）
%
% 输入：
%   rx_sym_all      - 1×N_total_sym complex，接收符号序列（CP 未去除）
%   train_cp        - 1×sym_per_block complex，训练块（含 CP）模板（RX 本地重建）
%   x_bar_blks      - 1×N_blocks cell，{1}=train_sym（blk_fft），{2..N}=数据块软符号（blk_fft）
%   blk_cp          - CP 长度（样本数）
%   blk_fft         - block FFT 长度（样本数）
%   sym_per_block   - blk_cp + blk_fft
%   N_blocks        - 总 block 数（含训练块）
%   N_total_sym     - N_blocks × sym_per_block
%   sym_delays      - 1×K_sparse，多径时延（样本，0-based）
%   K_sparse        - 多径数
%
% 输出：
%   obs_y - 1×N_obs complex，观测样本
%   obs_x - N_obs×K_sparse complex，重构发送符号矩阵
%   obs_n - 1×N_obs，观测样本时间索引（1-based）
%
% 备注：
%   仅用每 block CP 段（n 落在 max_tau+1..blk_cp）作观测点，
%   但 x_vec 引用的 idx 可能跨块落到前一块的 data 段或 CP 段。
%   训练块用 train_cp 模板（合法）；数据块用 Turbo 软符号（去 oracle）。

%% 1. 入参校验
assert(iscell(x_bar_blks) && length(x_bar_blks) == N_blocks, ...
    'x_bar_blks 长度必须 = N_blocks');
assert(length(train_cp) >= sym_per_block, 'train_cp 长度必须 >= sym_per_block');

%% 2. 初始化
obs_y = [];
obs_x = [];
obs_n = [];
max_tau = max(sym_delays);

%% 3. 训练块（bi=1）的 CP 段：用 train_cp 重建
for n = max_tau+1 : blk_cp
    x_vec = zeros(1, K_sparse);
    for pp = 1:K_sparse
        idx = n - sym_delays(pp);
        if idx >= 1 && idx <= length(train_cp)
            x_vec(pp) = train_cp(idx);
        end
    end
    if any(x_vec ~= 0) && n <= length(rx_sym_all)
        obs_y(end+1) = rx_sym_all(n);          %#ok<AGROW>
        obs_x = [obs_x; x_vec];                %#ok<AGROW>
        obs_n(end+1) = n;                      %#ok<AGROW>
    end
end

%% 4. 数据块（bi=2..N_blocks）的 CP 段：用 x_bar_blks 软符号
for bi = 2:N_blocks
    blk_start = (bi-1) * sym_per_block;
    for kk = max_tau+1 : blk_cp
        n = blk_start + kk;
        x_vec = zeros(1, K_sparse);
        for pp = 1:K_sparse
            idx = n - sym_delays(pp);
            if idx >= 1 && idx <= N_total_sym
                blk_of_idx = floor((idx - 1) / sym_per_block) + 1;  % 1-based
                local_n    = idx - (blk_of_idx - 1) * sym_per_block;
                if blk_of_idx == 1
                    % idx 落在训练块
                    if local_n >= 1 && local_n <= length(train_cp)
                        x_vec(pp) = train_cp(local_n);
                    end
                else
                    % idx 落在某数据块
                    xb = x_bar_blks{blk_of_idx};   % 长度 blk_fft（不含 CP）
                    if local_n <= blk_cp
                        % CP 段 = data block 末 blk_cp 符号
                        cp_src_idx = blk_fft - blk_cp + local_n;
                        if cp_src_idx >= 1 && cp_src_idx <= blk_fft
                            x_vec(pp) = xb(cp_src_idx);
                        end
                    else
                        % 数据段
                        data_idx = local_n - blk_cp;
                        if data_idx >= 1 && data_idx <= blk_fft
                            x_vec(pp) = xb(data_idx);
                        end
                    end
                end
            end
        end
        if any(x_vec ~= 0) && n <= length(rx_sym_all)
            obs_y(end+1) = rx_sym_all(n);          %#ok<AGROW>
            obs_x = [obs_x; x_vec];                %#ok<AGROW>
            obs_n(end+1) = n;                      %#ok<AGROW>
        end
    end
end

%% 5. 输出转列向量（ch_est_bem 要求）
obs_y = obs_y(:).';
obs_n = obs_n(:).';

end
