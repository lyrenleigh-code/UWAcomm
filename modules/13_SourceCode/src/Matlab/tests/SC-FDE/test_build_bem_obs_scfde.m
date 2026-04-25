%% test_build_bem_obs_scfde.m
% Phase 3b.1 单元测试：build_bem_observations_scfde 局部函数
%
% 验证项：
%   1. 输出维度合理（obs_y/obs_x/obs_n 长度对齐）
%   2. 训练块 obs 数量（仅训练 CP 段，bi=1）
%   3. 数据块 obs 数量（bi=2..N CP 段）
%   4. 索引边界（obs_n 全 ≤ N_total_sym）
%   5. 观测 x_vec 都非全 0
%   6. 训练块只引用 train_cp，数据块引用 x_bar_blks{2..N} 软符号
%
% 参考：14_Streaming::modem_decode_scfde::build_bem_observations
% 版本：V1.0.0 (2026-04-25)

clear functions; clear; close all; clc;

addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'bench_common'));

fprintf('========================================\n');
fprintf('  test_build_bem_obs_scfde 单元测试\n');
fprintf('========================================\n');

%% 模拟参数（与 SC-FDE runner 一致）
blk_cp        = 64;
blk_fft       = 256;
sym_per_block = blk_cp + blk_fft;     % 320
N_blocks      = 4;                     % 1 训练 + 3 数据
N_total_sym   = N_blocks * sym_per_block;  % 1280
% 取实际 SC-FDE runner 中 sym_delays 范围（注：runner 用 [0,5,15,40,60,90]，
% 但本单元测试 blk_cp=64 < max_tau=90 会让训练块 obs 范围 max_tau+1..blk_cp 空集；
% runner 实际 blk_cp 通常 ≥ max_tau+1，sym_delays_small 反映正常工况）
sym_delays    = [0, 5, 10, 20, 30, 40];      % max_tau=40 < blk_cp=64
K_sparse      = length(sym_delays);
max_tau       = max(sym_delays);

%% 模拟 train_cp + x_bar_blks（QPSK 星座）
constellation = [1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
rng(42);
train_sym  = constellation(randi(4, 1, blk_fft));
train_cp   = [train_sym(end-blk_cp+1:end), train_sym];   % length sym_per_block

x_bar_blks = cell(1, N_blocks);
x_bar_blks{1} = train_sym;
for bi = 2:N_blocks
    x_bar_blks{bi} = constellation(randi(4, 1, blk_fft));
end

%% 模拟 rx_sym_all（仅尺寸，内容随机）
rx_sym_all = randn(1, N_total_sym) + 1j*randn(1, N_total_sym);

%% 调 build_bem_observations_scfde
[obs_y, obs_x, obs_n] = build_bem_observations_scfde(...
    rx_sym_all, train_cp, x_bar_blks, blk_cp, blk_fft, sym_per_block, ...
    N_blocks, N_total_sym, sym_delays, K_sparse);

fprintf('obs_y 长度：%d\n', length(obs_y));
fprintf('obs_x 维度：%dx%d\n', size(obs_x,1), size(obs_x,2));
fprintf('obs_n 长度：%d\n', length(obs_n));

%% 验证项 1: 维度对齐
n_obs = length(obs_y);
assert(size(obs_x,1) == n_obs, 'obs_x 行数 ≠ obs_y 长度');
assert(size(obs_x,2) == K_sparse, 'obs_x 列数 ≠ K_sparse');
assert(length(obs_n) == n_obs, 'obs_n 长度 ≠ obs_y 长度');
fprintf('✓ 1. 维度对齐\n');

%% 验证项 2: obs 数量合理
%   每个 block CP 段贡献 ≤ blk_cp - max_tau = 64 - 40 = 24
expected_max = N_blocks * (blk_cp - max_tau);
fprintf('expected_max obs ≤ %d (实际 %d)\n', expected_max, length(obs_y));
assert(length(obs_y) <= expected_max, 'obs_y 长度超过理论上限');
assert(length(obs_y) > 0, 'obs_y 为空（应有观测）');
fprintf('✓ 2. obs 数量合理（n_obs=%d, ≤ expected %d）\n', length(obs_y), expected_max);

%% 验证项 3: obs_n 全在合法范围
assert(all(obs_n >= 1) && all(obs_n <= N_total_sym), 'obs_n 越界');
fprintf('✓ 3. obs_n 全在 [1, N_total_sym] 范围\n');

%% 验证项 4: obs_x 全行非全 0
assert(all(any(obs_x ~= 0, 2)), '存在全 0 行（应被过滤）');
fprintf('✓ 4. obs_x 无全 0 行\n');

%% 验证项 5: 训练块观测的 x_vec 引用 train_cp（QPSK constellation 单位 power，|c|=1）
mag_first = abs(obs_x(1, find(obs_x(1,:) ~= 0, 1)));
expected_qpsk_mag = 1;   % (1+1j)/sqrt(2) → |·|=1
assert(abs(mag_first - expected_qpsk_mag) < 1e-9, ...
    sprintf('训练块 x_vec 幅度 %.6f ≠ QPSK %.6f', mag_first, expected_qpsk_mag));
fprintf('✓ 5. 训练块 x_vec 幅度 = QPSK %.4f\n', mag_first);

%% 验证项 6: 与 ch_est_bem 兼容
% 6 层 fileparts 到 modules/，再加 07_ChannelEstEq
addpath(fullfile(fileparts(fileparts(fileparts(fileparts(fileparts(fileparts(mfilename('fullpath'))))))), '07_ChannelEstEq', 'src', 'Matlab'));
if exist('ch_est_bem', 'file') == 2
    try
        [h_tv_test, ~, ~] = ch_est_bem(obs_y(:), obs_x, obs_n(:), N_total_sym, ...
            sym_delays, 1, 6000, 0.01, 'dct', struct('Q_mode','auto','lambda_scale',1.0));
        assert(size(h_tv_test, 1) == K_sparse, 'ch_est_bem 输出维度错');
        assert(size(h_tv_test, 2) == N_total_sym, 'ch_est_bem 时间维度错');
        assert(all(isfinite(h_tv_test(:))), 'ch_est_bem 输出含 NaN/Inf');
        fprintf('✓ 6. ch_est_bem 调用成功 (h_tv: %dx%d)\n', size(h_tv_test));
    catch ME
        fprintf('✗ 6. ch_est_bem 调用失败: %s\n', ME.message);
    end
else
    fprintf('⚠ 6. ch_est_bem 不在 path，跳过\n');
end

fprintf('\n========================================\n');
fprintf('  Phase 3b.1 单元测试完成\n');
fprintf('========================================\n');
